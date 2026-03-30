import SwiftUI

private struct MonthOffset: Equatable {
    let month: Date
    let minY: CGFloat
}

// Tracks each month block's top-edge position in the scroll coordinate space
private struct MonthOffsetPreference: PreferenceKey {
    static var defaultValue: [MonthOffset] = []
    static func reduce(value: inout [MonthOffset], nextValue: () -> [MonthOffset]) {
        value.append(contentsOf: nextValue())
    }
}

private enum ScrollDirection {
    case up, down
}

struct FullCalendarView: View {
    let sessions: [FocusSession]
    let user: User?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date?

    @State private var sessionsByDay: [Date: [FocusSession]]? = nil
    @State private var visibleMonthTitle: String = ""
    @State private var excludedCategories: Set<SessionCategory> = []
    @State private var isTodayInView = true
    @State private var hasCompletedInitialScroll = false
    @State private var lastScrollDirection: ScrollDirection = .down
    @State private var todayIsAbove = false // true when today is above viewport (arrow points up)
    @State private var previousTopMonthMinY: CGFloat?

    private let calendar = Calendar.current
    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: Date())!.start
    }

    // All months from earliest session through next month (so current month can
    // scroll high enough to update the header title)
    private var months: [Date] {
        let today = Date()
        let currentMonthStart = calendar.dateInterval(of: .month, for: today)!.start
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart)!

        let earliest: Date
        if let firstSession = sessions.min(by: { $0.endTime < $1.endTime }) {
            let sessionMonthStart = calendar.dateInterval(of: .month, for: firstSession.endTime)!.start
            let cap = calendar.date(byAdding: .month, value: -24, to: currentMonthStart)!
            earliest = max(sessionMonthStart, cap)
        } else {
            earliest = calendar.date(byAdding: .month, value: -3, to: currentMonthStart)!
        }

        var result: [Date] = []
        var cursor = earliest
        while cursor <= nextMonthStart {
            result.append(cursor)
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
        }
        return result
    }

    private var currentMonthID: String {
        monthID(for: calendar.dateInterval(of: .month, for: Date())!.start)
    }

    // MARK: Extracted sub-views (keeps body type-check complexity low)

    @ViewBuilder
    private var calendarContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let sessionsByDay {
                calendarScrollView(sessionsByDay: sessionsByDay, excludedCategories: excludedCategories)
                    .transition(.opacity)
            } else {
                CalendarSkeletonView()
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.2), value: sessionsByDay != nil)
    }

    @ViewBuilder
    private func calendarScrollView(sessionsByDay: [Date: [FocusSession]], excludedCategories: Set<SessionCategory>) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                lazyMonthStack(sessionsByDay: sessionsByDay, excludedCategories: excludedCategories)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
            }
            .coordinateSpace(name: "calendarScroll")
            .onPreferenceChange(MonthOffsetPreference.self) { offsets in
                // Threshold ~200pt: the month whose top is nearest the viewport top
                guard let best = offsets.filter({ $0.minY <= 200 }).max(by: { $0.minY < $1.minY }) else { return }
                visibleMonthTitle = monthYearString(from: best.month)
                let topIsCurrentMonth = calendar.isDate(best.month, equalTo: currentMonthStart, toGranularity: .month)
                isTodayInView = topIsCurrentMonth
                todayIsAbove = best.month > currentMonthStart
                if let prev = previousTopMonthMinY {
                    lastScrollDirection = best.minY < prev ? .down : .up
                }
                previousTopMonthMinY = best.minY
            }
            .onAppear {
                proxy.scrollTo(currentMonthID, anchor: .top)
                if visibleMonthTitle.isEmpty {
                    visibleMonthTitle = monthYearString(from: Date())
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    hasCompletedInitialScroll = true
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hasCompletedInitialScroll && !isTodayInView {
                    backToTodayFAB(proxy: proxy)
                }
            }
        }
    }

    private func backToTodayFAB(proxy: ScrollViewProxy) -> some View {
        Button {
            let anchor: UnitPoint = lastScrollDirection == .down ? .top : .bottom
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(currentMonthID, anchor: anchor)
            }
        } label: {
            Image(systemName: todayIsAbove ? "chevron.up" : "chevron.down")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .transition(.scale.combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: isTodayInView)
    }

    @ViewBuilder
    private func lazyMonthStack(sessionsByDay: [Date: [FocusSession]], excludedCategories: Set<SessionCategory>) -> some View {
        LazyVStack(spacing: 32) {
            ForEach(months, id: \.self) { month in
                MonthCalendarBlock(
                    month: month,
                    sessionsByDay: sessionsByDay,
                    excludedCategories: excludedCategories,
                    selectedDay: $selectedDay
                )
                .id(monthID(for: month))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: MonthOffsetPreference.self,
                            value: [MonthOffset(month: month, minY: geo.frame(in: .named("calendarScroll")).minY)]
                        )
                    }
                )
            }
        }
    }

    // Fixed weekday header row — shared across all months, pinned below the nav bar
    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // Category color legend — tappable pills to exclude from milestone totals
    private var categoryLegendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SessionCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            let allExceptTapped = Set(SessionCategory.allCases.filter { $0 != category })
                            if excludedCategories == allExceptTapped {
                                excludedCategories = []
                            } else {
                                excludedCategories = allExceptTapped
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 8, height: 8)
                            Text(category.displayName)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(category.color.opacity(excludedCategories.contains(category) ? 0.2 : 0.25))
                        .clipShape(Capsule())
                        .overlay {
                            if excludedCategories.contains(category) {
                                Capsule()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            }
                        }
                        .opacity(excludedCategories.contains(category) ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }

    var body: some View {
        NavigationStack {
            calendarContent
            .navigationTitle(visibleMonthTitle.isEmpty ? monthYearString(from: Date()) : visibleMonthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    categoryLegendRow
                    weekdayHeaderRow
                }
            }
        }
        .task {
            let built = await Task.detached(priority: .userInitiated) {
                Dictionary(grouping: sessions) {
                    Calendar.current.startOfDay(for: $0.endTime)
                }
            }.value
            sessionsByDay = built

            let badgePairs: [(name: String, color: Color)] = built.flatMap { (_, daySessions) -> [(String, Color)] in
                guard let milestone = Milestone.dayMilestoneForTotalTime(
                    daySessions.reduce(0) { $0 + $1.duration }
                ) else { return [] }
                let color = daySessions.sorted(by: { $0.duration > $1.duration }).first?.category.color
                    ?? Color(red: 1.0, green: 0.84, blue: 0.0)
                let name = "badge-\(milestone.label)"
                return [(name, color)]
            }
            await BadgeImageCache.shared.prefetch(badges: badgePairs)
        }
        .sheet(item: Binding(
            get: { selectedDay },
            set: { selectedDay = $0 }
        )) { day in
            DayDetailView(day: day, sessions: sessions, user: user)
        }
    }

    private func monthID(for month: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: month)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Skeleton placeholder

private struct CalendarSkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 32) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonMonthBlock()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

private struct SkeletonMonthBlock: View {
    @State private var shimmer = false

    private let pulse = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Month label placeholder — narrow pill in the first-day column position
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(shimmer ? 0.10 : 0.05))
                    .frame(width: 32, height: 14)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }

            // 5 rows of day cells
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(shimmer ? 0.07 : 0.03))
                            .frame(height: 36)
                            .frame(maxWidth: .infinity)
                            .padding(4)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(pulse) { shimmer = true }
        }
    }
}

// MARK: - Single month block

private struct MonthCalendarBlock: View {
    let month: Date
    let sessionsByDay: [Date: [FocusSession]]
    let excludedCategories: Set<SessionCategory>
    @Binding var selectedDay: Date?

    private let calendar = Calendar.current

    private func includedSessions(for day: Date) -> [FocusSession] {
        (sessionsByDay[day] ?? []).filter { !excludedCategories.contains($0.category) }
    }

    var body: some View {
        VStack(spacing: 4) {
            monthLabelRow
            calendarGrid
        }
    }

    // MARK: Month label row
    // Abbreviated month name appears above the column where day 1 falls —
    // matches the Apple Fitness+ calendar style

    private var firstWeekdayIndex: Int {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return calendar.component(.weekday, from: monthInterval.start) - 1
    }

    private var abbreviatedMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: month)
    }

    private var monthLabelRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Group {
                    if index == firstWeekdayIndex {
                        Text(abbreviatedMonthName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            }
        }
    }

    // MARK: Grid

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                dayCell(date: date)
            }
        }
    }

    private func dayCell(date: Date?) -> some View {
        Group {
            if let date {
                let dayNumber = calendar.component(.day, from: date)
                let milestone = milestoneForDay(date)
                let isToday = calendar.isDateInToday(date)
                let isFuture = date > calendar.startOfDay(for: Date())
                let categoryColor = badgeColorForDay(date)

                Button {
                    if !isFuture, milestone != nil {
                        selectedDay = date
                    }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            ZStack {
                                if isToday && (milestone == nil || isFuture) {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .padding(6)
                                }

                                if let milestone, !isFuture {
                                    badgeImage(for: milestone, categoryColor: categoryColor)
                                        .padding(2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                }

                                if milestone == nil || isFuture {
                                    Text("\(dayNumber)")
                                        .font(.system(size: 15, weight: isToday ? .semibold : .regular, design: .rounded))
                                        .foregroundStyle(isFuture ? .white.opacity(0.2) : (isToday ? .white : .white.opacity(0.7)))
                                } else {
                                    VStack {
                                        HStack {
                                            Text("\(dayNumber)")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(isToday ? .black : .white)
                                                .padding(2)
                                                .background(isToday ? Color.white : Color.black.opacity(0.4))
                                                .clipShape(Circle())
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(4)
                                }
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isFuture || milestone == nil)
                .id(isToday ? "today" : "day-\(date.timeIntervalSince1970)")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    // MARK: Helpers

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: monthInterval.end).day ?? 0
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        return days
    }

    private func totalTimeForDay(_ day: Date) -> TimeInterval {
        includedSessions(for: day).reduce(0) { $0 + $1.duration }
    }

    private func milestoneForDay(_ day: Date) -> Milestone? {
        Milestone.dayMilestoneForTotalTime(totalTimeForDay(day))
    }

    private func badgeColorForDay(_ day: Date) -> Color {
        includedSessions(for: day)
            .sorted(by: { $0.duration > $1.duration })
            .first?.category.color
            ?? Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    private func badgeImage(for milestone: Milestone, categoryColor: Color) -> some View {
        let primary = "badge-\(milestone.label)"
        let fallback = "badge-\(milestone.label.replacingOccurrences(of: "+", with: "plus"))"
        let resolvedName: String? = SVGCache.shared.rawSVG(named: primary) != nil ? primary
            : SVGCache.shared.rawSVG(named: fallback) != nil ? fallback
            : nil

        if let name = resolvedName {
            return AnyView(AsyncBadgeImageView(badgeName: name, color: categoryColor))
        }
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(categoryColor)
        )
    }
}
