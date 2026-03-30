import Foundation

struct Milestone: Identifiable {
    var id: Int { seconds }
    let seconds: Int
    let label: String
    let icon: String
    let pointBonus: Int
    let badgeShape: String // Rive badge shape name (e.g., "badge-shape-1")
    
    // Helper to get metaTag ("m" for minutes, "hr" for hours)
    var metaTag: String {
        if label.contains("hr") {
            return "hr"
        } else if label.contains("m") {
            return "m"
        }
        return "m" // default
    }
    
    // Helper to get metaTag as a number for Rive converter (0 = minutes, 1 = hours)
    var metaTagNumber: Double {
        if label.contains("hr") {
            return 1.0 // hours
        } else {
            return 0.0 // minutes
        }
    }
    
    // Helper to get milestoneTime (just the number)
    var milestoneTime: Int {
        // Extract number from label (e.g., "5m" -> 5, "10m" -> 10, "1hr" -> 1, "24hr+" -> 24)
        // Use regex to extract the numeric part
        let pattern = #"(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let range = Range(match.range(at: 1), in: label) {
            return Int(String(label[range])) ?? 0
        }
        // Fallback: remove non-numeric characters
        let numberString = label.replacingOccurrences(of: "m", with: "")
            .replacingOccurrences(of: "hr", with: "")
            .replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int(numberString) ?? 0
    }
    
    static let allMilestones: [Milestone] = [
        // Streak achieved - Badge-shape-0 (5 minutes, unique entry milestone)
        Milestone(seconds: 300, label: "5m", icon: "flame.fill", pointBonus: 10, badgeShape: "badge-shape-0"),       // 5min

        // badge-shape-1 (10-15 min)
        Milestone(seconds: 600, label: "10m", icon: "trophy.fill", pointBonus: 20, badgeShape: "badge-shape-1"),     // 10min
        Milestone(seconds: 900, label: "15m", icon: "trophy.fill", pointBonus: 30, badgeShape: "badge-shape-1"),     // 15min
        
        // badge-shape-2 (20-30 min)
        Milestone(seconds: 1200, label: "20m", icon: "trophy.fill", pointBonus: 40, badgeShape: "badge-shape-2"),    // 20min
        Milestone(seconds: 1800, label: "30m", icon: "trophy.fill", pointBonus: 60, badgeShape: "badge-shape-2"),   // 30min
        
        // badge-shape-3 (40-50 min)
        Milestone(seconds: 2400, label: "40m", icon: "trophy.fill", pointBonus: 80, badgeShape: "badge-shape-3"),   // 40min
        Milestone(seconds: 3000, label: "50m", icon: "trophy.fill", pointBonus: 100, badgeShape: "badge-shape-3"),   // 50min
        
        // badge-shape-4 (1-3 hr)
        Milestone(seconds: 3600, label: "1hr", icon: "trophy.fill", pointBonus: 100, badgeShape: "badge-shape-4"),      // 1hr
        Milestone(seconds: 7200, label: "2hr", icon: "trophy.fill", pointBonus: 200, badgeShape: "badge-shape-4"),      // 2hr
        Milestone(seconds: 10800, label: "3hr", icon: "trophy.fill", pointBonus: 300, badgeShape: "badge-shape-4"),     // 3hr
        
        // badge-shape-5 (4-6 hr)
        Milestone(seconds: 14400, label: "4hr", icon: "trophy.fill", pointBonus: 400, badgeShape: "badge-shape-5"),     // 4hr
        Milestone(seconds: 18000, label: "5hr", icon: "trophy.fill", pointBonus: 500, badgeShape: "badge-shape-5"),     // 5hr
        Milestone(seconds: 21600, label: "6hr", icon: "trophy.fill", pointBonus: 600, badgeShape: "badge-shape-5"),      // 6hr
        
        // badge-shape-6 (7+ hr)
        Milestone(seconds: 25200, label: "7hr", icon: "trophy.fill", pointBonus: 700, badgeShape: "badge-shape-6"),     // 7hr
        Milestone(seconds: 28800, label: "8hr", icon: "trophy.fill", pointBonus: 800, badgeShape: "badge-shape-6"),      // 8hr
        Milestone(seconds: 32400, label: "9hr", icon: "trophy.fill", pointBonus: 900, badgeShape: "badge-shape-6"),     // 9hr
        Milestone(seconds: 36000, label: "10hr", icon: "trophy.fill", pointBonus: 1000, badgeShape: "badge-shape-6"),    // 10hr
        Milestone(seconds: 39600, label: "11hr", icon: "trophy.fill", pointBonus: 1100, badgeShape: "badge-shape-6"),   // 11hr
        Milestone(seconds: 43200, label: "12hr", icon: "trophy.fill", pointBonus: 1200, badgeShape: "badge-shape-6"),    // 12hr
        Milestone(seconds: 46800, label: "13hr", icon: "trophy.fill", pointBonus: 1300, badgeShape: "badge-shape-6"),    // 13hr
        Milestone(seconds: 50400, label: "14hr", icon: "trophy.fill", pointBonus: 1400, badgeShape: "badge-shape-6"),   // 14hr
        Milestone(seconds: 54000, label: "15hr", icon: "trophy.fill", pointBonus: 1500, badgeShape: "badge-shape-6"),   // 15hr
        Milestone(seconds: 57600, label: "16hr", icon: "trophy.fill", pointBonus: 1600, badgeShape: "badge-shape-6"),   // 16hr
        Milestone(seconds: 61200, label: "17hr", icon: "trophy.fill", pointBonus: 1700, badgeShape: "badge-shape-6"),   // 17hr
        Milestone(seconds: 64800, label: "18hr", icon: "trophy.fill", pointBonus: 1800, badgeShape: "badge-shape-6"),  // 18hr
        Milestone(seconds: 68400, label: "19hr", icon: "trophy.fill", pointBonus: 1900, badgeShape: "badge-shape-6"),  // 19hr
        Milestone(seconds: 72000, label: "20hr", icon: "trophy.fill", pointBonus: 2000, badgeShape: "badge-shape-6"),    // 20hr
        Milestone(seconds: 75600, label: "21hr", icon: "trophy.fill", pointBonus: 2100, badgeShape: "badge-shape-6"),    // 21hr
        Milestone(seconds: 79200, label: "22hr", icon: "trophy.fill", pointBonus: 2200, badgeShape: "badge-shape-6"),  // 22hr
        Milestone(seconds: 82800, label: "23hr", icon: "trophy.fill", pointBonus: 2300, badgeShape: "badge-shape-6"),   // 23hr
        Milestone(seconds: 86400, label: "24hr", icon: "trophy.fill", pointBonus: 2400, badgeShape: "badge-shape-6"),  // 24hr
        
        // Secret 24+ hour milestone
        Milestone(seconds: 86401, label: "24hr+", icon: "trophy.fill", pointBonus: 5000, badgeShape: "badge-shape-6")   // Secret milestone
    ]
    
    static func milestoneForDuration(_ duration: TimeInterval) -> Milestone? {
        let durationInSeconds = Int(duration)
        
        // Find the milestone that matches this duration's range
        // Each milestone is unlocked by sessions within a specific duration range:
        // - 10m milestone: sessions 10-14.99 min (600-899 seconds)
        // - 15m milestone: sessions 15-19.99 min (900-1199 seconds)
        // - 20m milestone: sessions 20-29.99 min (1200-1799 seconds)
        // - 30m milestone: sessions 30-39.99 min (1800-2399 seconds)
        // - 40m milestone: sessions 40-49.99 min (2400-2999 seconds)
        // - 50m milestone: sessions 50-59.99 min (3000-3599 seconds)
        // etc.
        
        for (index, milestone) in allMilestones.enumerated() {
            // Find the next milestone to determine the upper bound for this milestone's range
            let nextMilestone = index < allMilestones.count - 1 ? allMilestones[index + 1] : nil
            let upperBound = nextMilestone?.seconds ?? Int.max
            
            // Check if duration falls within this milestone's range
            if durationInSeconds >= milestone.seconds && durationInSeconds < upperBound {
                return milestone
            }
        }
        
        return nil
    }
    
    static func newMilestoneAchieved(duration: TimeInterval, achievedMilestones: [Int]) -> Milestone? {
        guard let milestone = milestoneForDuration(duration) else { return nil }
        
        // Check if this milestone has already been achieved
        if achievedMilestones.contains(milestone.seconds) {
            return nil
        }
        
        return milestone
    }
    
    /// Finds the milestone that matches a given daily total time
    /// Similar to milestoneForDuration but for cumulative daily totals
    static func dayMilestoneForTotalTime(_ totalTime: TimeInterval) -> Milestone? {
        let totalTimeInSeconds = Int(totalTime)
        
        // Find the milestone that matches this total time's range
        // Uses the same range logic as milestoneForDuration
        for (index, milestone) in allMilestones.enumerated() {
            // Find the next milestone to determine the upper bound for this milestone's range
            let nextMilestone = index < allMilestones.count - 1 ? allMilestones[index + 1] : nil
            let upperBound = nextMilestone?.seconds ?? Int.max
            
            // Check if total time falls within this milestone's range
            if totalTimeInSeconds >= milestone.seconds && totalTimeInSeconds < upperBound {
                return milestone
            }
        }
        
        return nil
    }
    
    /// The immediate next milestone in the canonical sequence (ascending by seconds).
    /// Use this to ensure level-up badge transitions always go from → to in correct order.
    static func nextInSequence(after milestone: Milestone) -> Milestone? {
        guard let idx = allMilestones.firstIndex(where: { $0.id == milestone.id }),
              idx + 1 < allMilestones.count else { return nil }
        return allMilestones[idx + 1]
    }

    /// Checks if a new day milestone was achieved based on daily total time
    /// Similar to newMilestoneAchieved but for daily totals
    static func newDayMilestoneAchieved(totalTime: TimeInterval, achievedDayMilestones: [Int]) -> Milestone? {
        guard let milestone = dayMilestoneForTotalTime(totalTime) else { return nil }
        
        // Check if this day milestone has already been achieved
        if achievedDayMilestones.contains(milestone.seconds) {
            return nil
        }
        
        return milestone
    }
}

