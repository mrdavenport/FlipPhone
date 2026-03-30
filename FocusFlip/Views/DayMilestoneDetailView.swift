import SwiftUI
import SwiftData

struct DayMilestoneDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let milestone: Milestone
    let sessions: [FocusSession]
    let user: User?
    
    @State private var selectedDay: Date?
    @State private var currentMonth: Date = Date()
    
    private let calendar = Calendar.current
    
    // Group sessions by day and calculate total time per day
    private func sessionsByDay() -> [Date: [FocusSession]] {
        return Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.endTime)
        }
    }
    
    // Calculate total time for a specific day
    private func totalTimeForDay(_ day: Date) -> TimeInterval {
        let daySessions = sessionsByDay()[day] ?? []
        return daySessions.reduce(0.0) { $0 + $1.duration }
    }
    
    // Check if a day achieved this milestone
    private func dayAchievedMilestone(_ day: Date) -> Bool {
        let totalTime = totalTimeForDay(day)
        if let dayMilestone = Milestone.dayMilestoneForTotalTime(totalTime) {
            return dayMilestone.seconds == milestone.seconds
        }
        return false
    }
    
    // Find all days that achieved this milestone
    private var daysForMilestone: Set<Date> {
        let sessionsByDayDict = sessionsByDay()
        var days: Set<Date> = []
        
        for (day, daySessions) in sessionsByDayDict {
            let totalTime = daySessions.reduce(0.0) { $0 + $1.duration }
            if let dayMilestone = Milestone.dayMilestoneForTotalTime(totalTime),
               dayMilestone.seconds == milestone.seconds {
                days.insert(day)
            }
        }
        
        return days
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(milestone.label)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(daysForMilestone.count) day\(daysForMilestone.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Calendar View
                ScrollView {
                    VStack(spacing: 24) {
                        // Month navigation and calendar
                        monthCalendarView
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: Binding(
            get: { selectedDay },
            set: { selectedDay = $0 }
        )) { day in
            DayDetailView(day: day, sessions: sessions, user: user)
        }
    }
    
    private var monthCalendarView: some View {
        VStack(spacing: 16) {
            // Month header with navigation
            HStack {
                Button {
                    withAnimation {
                        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                            currentMonth = previousMonth
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(monthYearString(from: currentMonth))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation {
                        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                            let today = Date()
                            let nextMonthStart = calendar.startOfDay(for: calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth)
                            let todayStart = calendar.startOfDay(for: today)
                            // Don't allow navigation to future months
                            if nextMonthStart <= todayStart {
                                currentMonth = nextMonth
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled({
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                        let today = Date()
                        let nextMonthStart = calendar.startOfDay(for: calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth)
                        let todayStart = calendar.startOfDay(for: today)
                        return nextMonthStart > todayStart
                    }
                    return true
                }())
            }
            .padding(.horizontal, 4)
            
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(daysInMonth, id: \.self) { date in
                    calendarDayCell(date: date)
                }
            }
        }
    }
    
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        let firstDayOfMonth = monthInterval.start
        let lastDayOfMonth = monthInterval.end
        
        // Get the first weekday of the month (0 = Sunday, 1 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
        
        // Get number of days in the month
        let daysInMonth = calendar.dateComponents([.day], from: firstDayOfMonth, to: lastDayOfMonth).day ?? 0
        
        var days: [Date?] = []
        
        // Add empty cells for days before the first day of the month
        for _ in 0..<firstWeekday {
            days.append(nil)
        }
        
        // Add all days in the month
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func calendarDayCell(date: Date?) -> some View {
        Group {
            if let date = date {
                let dayNumber = calendar.component(.day, from: date)
                let isAchieved = dayAchievedMilestone(date)
                let isToday = calendar.isDateInToday(date)
                let isFuture = date > calendar.startOfDay(for: Date())
                
                Button {
                    if !isFuture {
                        selectedDay = date
                    }
                } label: {
                    ZStack {
                        // Background circle for today
                        if isToday {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .padding(6)
                        }
                        
                        // Day number
                        Text("\(dayNumber)")
                            .font(.system(size: 15, weight: isToday ? .semibold : .regular, design: .rounded))
                            .foregroundColor(isFuture ? .white.opacity(0.2) : (isToday ? .white : .white.opacity(0.7)))
                        
                        // Badge marker for achieved days
                        if isAchieved && !isFuture {
                            VStack {
                                Spacer()
                                Circle()
                                    .fill(milestoneBadgeColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
            } else {
                // Empty cell
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
    
    private var milestoneBadgeColor: Color {
        // Get color from the most recent day that achieved this milestone
        if let mostRecentDay = daysForMilestone.sorted(by: >).first {
            let daySessions = sessionsByDay()[mostRecentDay] ?? []
            if let topSession = daySessions.sorted(by: { $0.duration > $1.duration }).first {
                return topSession.category.color
            }
        }
        return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold fallback
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// Extension to make Date Identifiable for sheet binding
extension Date: Identifiable {
    public var id: Date { self }
}
