import SwiftUI

/// 7-day horizontal strip centered on today.
/// Today's cell is the matchedGeometryEffect landing target for the hero badge.
struct WeekCalendarStripView: View {
    let sessions: [FocusSession]
    let user: User?
    var namespace: Namespace.ID
    var isBottomSheetExpanded: Bool
    let onCalendarTap: () -> Void

    private let calendar = Calendar.current

    // 3 past days, today, 3 future days
    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        Button(action: onCalendarTap) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    dayCell(for: date)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > calendar.startOfDay(for: Date())
        let dayNumber = calendar.component(.day, from: date)
        let milestone = milestoneForDay(date)

        VStack(spacing: 4) {
            // Short weekday label
            Text(weekdayLetter(for: date))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isToday ? .white : .white.opacity(0.4))

            if isToday {
                // Today: matchedGeometryEffect target — the hero badge flies here
                todayCellContent(milestone: milestone)
                    .frame(width: 40, height: 40)
                    .matchedGeometryEffect(
                        id: "dailyBadge",
                        in: namespace,
                        isSource: isBottomSheetExpanded
                    )
            } else if let milestone, !isFuture {
                // Past day that hit a daily milestone: show small badge
                smallBadge(for: milestone, date: date)
                    .frame(width: 30, height: 30)
            } else {
                // Future day or no milestone: day number
                Text("\(dayNumber)")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(isFuture ? .white.opacity(0.2) : .white.opacity(0.55))
                    .frame(width: 30, height: 30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Today cell content

    @ViewBuilder
    private func todayCellContent(milestone: Milestone?) -> some View {
        if let milestone {
            badgeImage(
                for: milestone,
                isCompleted: true,
                categoryColor: todayBadgeColor
            )
        } else {
            // No milestone yet today — neutral ring with day number
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                Text("\(calendar.component(.day, from: Date()))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Small past-day badge

    @ViewBuilder
    private func smallBadge(for milestone: Milestone, date: Date) -> some View {
        badgeImage(
            for: milestone,
            isCompleted: true,
            categoryColor: badgeColorForDay(date)
        )
    }

    // MARK: - Data helpers

    private func sessionsByDay() -> [Date: [FocusSession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.endTime) }
    }

    private func totalTimeForDay(_ day: Date) -> TimeInterval {
        (sessionsByDay()[day] ?? []).reduce(0) { $0 + $1.duration }
    }

    private func milestoneForDay(_ day: Date) -> Milestone? {
        Milestone.dayMilestoneForTotalTime(totalTimeForDay(day))
    }

    private var todayBadgeColor: Color {
        let today = calendar.startOfDay(for: Date())
        let todaySessions = sessionsByDay()[today] ?? []
        return todaySessions
            .sorted(by: { $0.duration > $1.duration })
            .first
            .map { $0.category.color }
            ?? Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    private func badgeColorForDay(_ day: Date) -> Color {
        let daySessions = sessionsByDay()[day] ?? []
        return daySessions
            .sorted(by: { $0.duration > $1.duration })
            .first
            .map { $0.category.color }
            ?? Color(red: 1.0, green: 0.84, blue: 0.0)
    }

    private func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    // MARK: - Badge image rendering

    private func badgeImage(for milestone: Milestone, isCompleted: Bool, categoryColor: Color) -> some View {
        let badgeName = "badge-\(milestone.label)"
        if let view = loadSVG(named: badgeName, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        let sanitized = "badge-\(milestone.label.replacingOccurrences(of: "+", with: "plus"))"
        if let view = loadSVG(named: sanitized, isCompleted: isCompleted, color: categoryColor) {
            return AnyView(view)
        }
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isCompleted ? categoryColor : .white.opacity(0.3))
        )
    }

    private func loadSVG(named badgeName: String, isCompleted: Bool, color: Color) -> AnyView? {
        let url = Bundle.main.url(forResource: badgeName, withExtension: "svg", subdirectory: "Badges")
            ?? Bundle.main.url(forResource: badgeName, withExtension: "svg")
        guard let url,
              let data = try? Data(contentsOf: url),
              let svgString = String(data: data, encoding: .utf8) else { return nil }
        return AnyView(SVGColorReplacementView(
            svgString: svgString,
            replacementColor: isCompleted ? color : .white,
            isCompleted: isCompleted
        ))
    }
}
