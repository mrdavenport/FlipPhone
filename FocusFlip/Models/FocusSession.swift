import Foundation
import SwiftData

@Model
final class FocusSession: Identifiable {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval
    var note: String
    var points: Int
    var isPersonalRecord: Bool
    var category: SessionCategory
    var pauseCount: Int? // Number of times the session was paused (optional for migration compatibility)
    
    /// Get pause count with default of 0 for nil values
    var pauseCountValue: Int {
        pauseCount ?? 0
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
    
    init(
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        note: String = "",
        points: Int = 0,
        isPersonalRecord: Bool = false,
        category: SessionCategory = .other,
        pauseCount: Int? = 0
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.note = note
        self.points = points
        self.isPersonalRecord = isPersonalRecord
        self.category = category
        self.pauseCount = pauseCount
    }
}



