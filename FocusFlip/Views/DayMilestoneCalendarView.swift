import SwiftUI

struct DayMilestoneCalendarView: View {
    let sessions: [FocusSession]
    let user: User?

    @State private var currentMonth: Date = Date()
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 16) {
            monthHeader
            weekdayHeaders
            calendarGrid
        }
        .sheet(item: Binding(
            get: { selectedDay },
            set: { selectedDay = $0 }
        )) { day in
            DayDetailView(day: day, sessions: sessions, user: user)
        }
    }

    // MARK: - Month navigation header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                        currentMonth = prev
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearString(from: currentMonth))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                withAnimation {
                    if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                        let nextStart = calendar.startOfDay(for: calendar.dateInterval(of: .month, for: next)?.start ?? next)
                        let todayStart = calendar.startOfDay(for: Date())
                        if nextStart <= todayStart {
                            currentMonth = next
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonthAtOrBeyondToday)
        }
        .padding(.horizontal, 4)
    }

    private var isCurrentMonthAtOrBeyondToday: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { return true }
        let nextStart = calendar.startOfDay(for: calendar.dateInterval(of: .month, for: next)?.start ?? next)
        let todayStart = calendar.startOfDay(for: Date())
        return nextStart > todayStart
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(daysInMonth, id: \.self) { date in
                dayCell(date: date)
            }
        }
    }

    // MARK: - Day cell

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
                                    badgeImage(for: milestone, isCompleted: true, categoryColor: categoryColor)
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
                                                .foregroundStyle(.white)
                                                .padding(2)
                                                .background(Color.black.opacity(0.4))
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
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    // MARK: - Helpers

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: monthInterval.end).day ?? 0
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        return days
    }

    private func sessionsByDay() -> [Date: [FocusSession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.endTime) }
    }

    private func totalTimeForDay(_ day: Date) -> TimeInterval {
        (sessionsByDay()[day] ?? []).reduce(0) { $0 + $1.duration }
    }

    private func milestoneForDay(_ day: Date) -> Milestone? {
        Milestone.dayMilestoneForTotalTime(totalTimeForDay(day))
    }

    private func badgeColorForDay(_ day: Date) -> Color {
        let daySessions = sessionsByDay()[day] ?? []
        if let top = daySessions.sorted(by: { $0.duration > $1.duration }).first {
            return top.category.color
        }
        return Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func badgeImage(for milestone: Milestone, isCompleted: Bool, categoryColor: Color) -> some View {
        let badgeName = "badge-\(milestone.label)"
        if let view = loadSVGWithColorReplacement(named: badgeName, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        let sanitized = "badge-\(milestone.label.replacingOccurrences(of: "+", with: "plus"))"
        if let view = loadSVGWithColorReplacement(named: sanitized, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(isCompleted ? categoryColor : .white.opacity(0.3))
        )
    }

    private func loadSVGWithColorReplacement(named badgeName: String, isCompleted: Bool, color: Color) -> AnyView? {
        guard let svgString = SVGCache.shared.rawSVG(named: badgeName) else { return nil }
        return AnyView(SVGColorReplacementView(
            svgString: svgString,
            replacementColor: isCompleted ? color : .white,
            isCompleted: isCompleted
        ))
    }
}
