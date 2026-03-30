import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let sessions: [FocusSession]
    let user: User?
    
    @State private var selectedSessionForDetail: FocusSession?
    
    private let calendar = Calendar.current
    
    // Get sessions for this day
    private var daySessions: [FocusSession] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        
        return sessions.filter { session in
            session.endTime >= dayStart && session.endTime < dayEnd
        }.sorted { $0.endTime > $1.endTime } // Most recent first
    }
    
    // Calculate total time for the day
    private var totalTime: TimeInterval {
        daySessions.reduce(0.0) { $0 + $1.duration }
    }
    
    // Get highlighted top sessions
    private var topSessions: [FocusSession] {
        // Prioritize sessions with note AND category is not .other
        let uniqueSessions = daySessions.filter { session in
            !session.note.isEmpty && session.category != .other
        }
        
        // If we have unique sessions, return them sorted by duration (longest first)
        if !uniqueSessions.isEmpty {
            return uniqueSessions.sorted { $0.duration > $1.duration }
        }
        
        // Otherwise, return longest sessions (top 3)
        return Array(daySessions.sorted { $0.duration > $1.duration }.prefix(3))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(formattedDate(for: day))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(daySessions.count) session\(daySessions.count == 1 ? "" : "s") · \(formatDuration(totalTime))")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Highlighted top sessions section
                        if !topSessions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top Sessions")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                LazyVStack(spacing: 12) {
                                    ForEach(topSessions, id: \.id) { session in
                                        highlightedSessionRow(session: session)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // All sessions section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Sessions")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(daySessions, id: \.id) { session in
                                    sessionRow(session: session, isHighlighted: topSessions.contains { $0.id == session.id })
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $selectedSessionForDetail) { session in
            SessionResultView(session: session, user: user) {
                selectedSessionForDetail = nil
            }
        }
    }
    
    private func highlightedSessionRow(session: FocusSession) -> some View {
        Button {
            selectedSessionForDetail = session
        } label: {
            HStack(spacing: 16) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(session.category.color)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: session.category.icon)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                
                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatTimeRange(for: session))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if !session.note.isEmpty {
                        Text(session.note)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    } else {
                        Text(session.category.displayName)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Duration
                Text(session.formattedDuration)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                // Star icon for highlighted
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(session.category.color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func sessionRow(session: FocusSession, isHighlighted: Bool) -> some View {
        Button {
            selectedSessionForDetail = session
        } label: {
            HStack(spacing: 16) {
                // Category icon
                Image(systemName: session.category.icon)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(session.category.color)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(session.category.color.opacity(0.2))
                    )
                
                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatTimeRange(for: session))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if !session.note.isEmpty {
                        Text(session.note)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    } else {
                        Text(session.category.displayName)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Duration
                Text(session.formattedDuration)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
    
    // Helper to format the date
    private func formattedDate(for date: Date) -> String {
        let now = Date()
        
        // Today
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        // Yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // This week - show day name
        if let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        
        // This year - show month and day
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        }
        
        // Older - show month, day, and year
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    // Helper to format time range
    private func formatTimeRange(for session: FocusSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: session.startTime).lowercased()
        let end = formatter.string(from: session.endTime).lowercased()
        return "\(start) - \(end)"
    }
    
    // Helper to format duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
