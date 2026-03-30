import Foundation
import SwiftData

@Model
final class User {
    var id: UUID
    var username: String
    var totalPoints: Int
    var longestSession: TimeInterval
    var totalFocusTime: TimeInterval
    var sessionsCompleted: Int
    var createdAt: Date
    
    var currentStreak: Int
    var longestStreak: Int
    var lastSessionDate: Date?
    var achievedMilestones: [Int]? // Array of milestone threshold seconds that have been achieved (optional for migration)
    var achievedDayMilestones: [Int]? // Array of day milestone threshold seconds that have been achieved (optional for migration)
    
    init(username: String) {
        self.id = UUID()
        self.username = username
        self.totalPoints = 0
        self.longestSession = 0
        self.totalFocusTime = 0
        self.sessionsCompleted = 0
        self.createdAt = Date()
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastSessionDate = nil
        self.achievedMilestones = []
        self.achievedDayMilestones = []
    }
    
    func updateStats(with session: FocusSession, allSessions: [FocusSession]? = nil) {
        totalPoints += session.points
        totalFocusTime += session.duration
        sessionsCompleted += 1
        
        if session.duration > longestSession {
            longestSession = session.duration
        }
        
        // Always recalculate streaks from all sessions to ensure 5-minute requirement is met
        // This ensures accuracy when sessions are added in any order
        if let allSessions = allSessions {
            recalculateStreaks(from: allSessions)
        } else {
            // Fallback to incremental update if sessions not provided
            updateStreak(sessionDate: session.endTime)
        }
    }
    
    private func updateStreak(sessionDate: Date) {
        // Note: This method is called incrementally, but we can't check 5min requirement here
        // without access to all sessions. The recalculateStreaks method handles the 5min requirement.
        // For incremental updates, we'll still update, but recalculateStreaks should be called
        // periodically or when needed to ensure accuracy.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: sessionDate)
        
        guard let lastDate = lastSessionDate else {
            currentStreak = 1
            longestStreak = 1
            lastSessionDate = today
            return
        }
        
        let lastSessionDay = calendar.startOfDay(for: lastDate)
        let daysBetween = calendar.dateComponents([.day], from: lastSessionDay, to: today).day ?? 0
        
        switch daysBetween {
        case 0:
            break
        case 1:
            currentStreak += 1
            if currentStreak > longestStreak {
                longestStreak = currentStreak
            }
            lastSessionDate = today
        default:
            currentStreak = 1
            lastSessionDate = today
        }
    }
    
    /// Recalculate streaks from all sessions (used when adding sessions for past dates)
    /// Only counts days with at least 5 minutes of total session time
    func recalculateStreaks(from sessions: [FocusSession]) {
        guard !sessions.isEmpty else {
            currentStreak = 0
            longestStreak = 0
            lastSessionDate = nil
            return
        }
        
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let minimumDailyTime: TimeInterval = 300 // 5 minutes in seconds
        
        // Group sessions by day and calculate total time per day
        let sessionsByDay = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.endTime)
        }
        
        // Filter to only days with >= 5 minutes total
        let validDays = sessionsByDay.compactMapValues { daySessions -> TimeInterval? in
            let totalTime = daySessions.reduce(0.0) { $0 + $1.duration }
            return totalTime >= minimumDailyTime ? totalTime : nil
        }.keys.sorted(by: >)
        
        guard let mostRecentDay = validDays.first else {
            currentStreak = 0
            longestStreak = 0
            lastSessionDate = nil
            return
        }
        
        // Calculate current streak (consecutive days from most recent valid day backwards)
        // Current streak only counts if there's a valid session today or yesterday
        var currentStreakCount = 0
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        
        // If most recent valid day is today or yesterday, count backwards from the most recent valid day
        // Otherwise, current streak is 0 (broken)
        if mostRecentDay == now || mostRecentDay == yesterday {
            // Count consecutive days backwards from the most recent valid day
            // If today isn't completed yet, count from yesterday instead
            var checkDate = mostRecentDay
            while validDays.contains(checkDate) {
                currentStreakCount += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
            }
        } else {
            // Most recent valid day is more than 1 day ago, streak is broken
            currentStreakCount = 0
        }
        
        // Calculate longest streak (find longest consecutive sequence)
        var longestStreakCount = 0
        var tempStreak = 0
        var previousDay: Date?
        
        for day in validDays.sorted(by: <) {
            if let prev = previousDay {
                let daysBetween = calendar.dateComponents([.day], from: prev, to: day).day ?? 0
                if daysBetween == 1 {
                    // Consecutive day
                    tempStreak += 1
                } else {
                    // Gap found, reset temp streak
                    longestStreakCount = max(longestStreakCount, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            previousDay = day
        }
        longestStreakCount = max(longestStreakCount, tempStreak)
        
        // Update streak values
        currentStreak = currentStreakCount
        longestStreak = max(longestStreak, longestStreakCount)
        lastSessionDate = mostRecentDay
    }
    
    /// Determines if the current streak is active (today's 5-minute goal achieved)
    /// Returns true if there's a valid session today, false otherwise
    func isStreakActive(sessions: [FocusSession]) -> Bool {
        guard currentStreak > 0 else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let minimumDailyTime: TimeInterval = 300 // 5 minutes
        
        // Check if there's a valid session today (>= 5 minutes)
        let todaySessions = sessions.filter { session in
            session.endTime >= today && session.endTime < tomorrow
        }
        let todayTotalTime = todaySessions.reduce(0.0) { $0 + $1.duration }
        
        return todayTotalTime >= minimumDailyTime
    }
}





