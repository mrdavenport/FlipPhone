import SwiftUI

enum SessionCategory: String, Codable, CaseIterable, Identifiable {
    case other = "Focus session"
    case work = "Work"
    case famTime = "Family"
    case sleep = "Sleep"
    case chores = "Chores"
    case justChilling = "Chilling"
    
    // Legacy categories - kept for backward compatibility but not shown in CaseIterable
    case study = "Study"
    case reading = "Reading"
    case exercise = "Exercise"
    case meditation = "Meditation"
    case creative = "Creative"
    case inTheZone = "In the zone"
    case touchingGrass = "Touching grass"
    case traveling = "Traveling"
    case hangingOut = "Social"
    
    var id: String { rawValue }
    
    // Custom decoder to handle backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        // Map old "Other" value to new "Focus session" case
        if rawValue == "Other" {
            self = .other
        } else {
            // Try to initialize from the raw value
            if let category = SessionCategory(rawValue: rawValue) {
                // Map legacy categories to default categories for display
                switch category {
                case .reading, .exercise, .meditation, .creative:
                    self = .other // Map to "Focus session"
                case .study:
                    self = .famTime // Map old "Study" to "Family"
                case .inTheZone:
                    self = .work // Map to "Work"
                case .touchingGrass, .traveling:
                    self = .justChilling // Map to "Chilling"
                case .hangingOut:
                    self = .justChilling // Map to "Chilling"
                default:
                    self = category // Keep the category as-is if it's still valid
                }
            } else {
                // Fallback to .other if value is unknown
                self = .other
            }
        }
    }
    
    // Override CaseIterable to only return the 6 default categories
    static var allCases: [SessionCategory] {
        return [.other, .work, .famTime, .sleep, .chores, .justChilling]
    }
    
    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .famTime: return "heart.fill"
        case .sleep: return "moon.stars.fill"
        case .chores: return "house.fill"
        case .justChilling: return "cup.and.saucer.fill"
        case .other: return "iphone.rear.camera"
        // Legacy categories
        case .study: return "book.fill"
        case .reading: return "book.pages.fill"
        case .exercise: return "figure.run"
        case .meditation: return "figure.mind.and.body"
        case .creative: return "paintbrush.fill"
        case .inTheZone: return "bolt.fill"
        case .touchingGrass: return "camera.macro"
        case .traveling: return "airplane"
        case .hangingOut: return "person.3.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .work: return Color(red: 245/255.0, green: 121/255.0, blue: 59/255.0) // #f5793b
        case .famTime: return Color(red: 242/255.0, green: 150/255.0, blue: 189/255.0) // #f296bd
        case .sleep: return Color(red: 153/255.0, green: 183/255.0, blue: 245/255.0) // #99b7f5
        case .chores: return .brown
        case .justChilling: return Color(red: 38/255.0, green: 127/255.0, blue: 83/255.0) // #267f53
        case .other: return Color(red: 182/255.0, green: 137/255.0, blue: 255/255.0) // #B689FF
        // Legacy categories
        case .study: return .purple
        case .reading: return Color(red: 0x1E/255.0, green: 0x94/255.0, blue: 0x96/255.0) // #1E9496
        case .exercise: return .orange
        case .meditation: return .indigo
        case .creative: return .pink
        case .inTheZone: return Color(red: 1.0, green: 0.8, blue: 0.0) // Yellow
        case .touchingGrass: return Color(red: 0.2, green: 0.7, blue: 0.3) // Forest green
        case .traveling: return Color(red: 0.0, green: 0.7, blue: 0.8) // Teal
        case .hangingOut: return Color(red: 1.0, green: 0.6, blue: 0.2) // Orange
        }
    }
    
    var displayName: String { rawValue }
}





