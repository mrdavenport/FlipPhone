import SwiftUI
import SwiftData

#if canImport(RiveRuntime)
import RiveRuntime
#endif

struct StreakStatsView: View {
    @Environment(\.dismiss) private var dismiss
    let user: User?
    let sessions: [FocusSession]
    @State private var selectedSessionForDetail: FocusSession?
    
    private var totalSessions: Int {
        sessions.count
    }
    
    private var averageSessionTime: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
    }
    
    private var totalFocusTime: TimeInterval {
        user?.totalFocusTime ?? sessions.reduce(0) { $0 + $1.duration }
    }
    
    private var longestSession: TimeInterval {
        user?.longestSession ?? sessions.map { $0.duration }.max() ?? 0
    }
    
    private var totalPoints: Int {
        user?.totalPoints ?? sessions.reduce(0) { $0 + $1.points }
    }
    
    private var sessionsThisWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
            return 0
        }
        return sessions.filter { $0.endTime >= weekStart && $0.endTime <= now }.count
    }
    
    private var todayTotalTime: TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        
        return sessions
            .filter { $0.endTime >= today && $0.endTime < tomorrow }
            .reduce(0.0) { $0 + $1.duration }
    }
    
    private var todayProgress: Double {
        let minimumTime: TimeInterval = 300 // 5 minutes
        return min(1.0, todayTotalTime / minimumTime)
    }
    
    private var streakActionText: String {
        let hasStreak = (user?.currentStreak ?? 0) > 0
        return hasStreak ? "continue" : "start"
    }
    
    var body: some View {
        ZStack {
            // Use material background for visual separation from content behind (iOS 18+ style)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress bar section at top
                streakProgressSection
                    .padding(.horizontal, 16)
                
                // Stats grid - two columns (only first two cards)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    // Current Streak
                    CompactStatCard(
                        title: "Current Streak",
                        value: "\(user?.currentStreak ?? 0)",
                        subtitle: "days",
                        icon: "flame.fill",
                        iconColor: Color(red: 1.0, green: 0.5, blue: 0.0),
                        isActive: user?.isStreakActive(sessions: sessions) ?? false
                    )
                    .frame(minHeight: 280)
                    
                    // Longest Streak
                    CompactStatCard(
                        title: "Longest Streak",
                        value: "\(user?.longestStreak ?? 0)",
                        subtitle: "days",
                        icon: "trophy.fill",
                        iconColor: Color(red: 1.0, green: 0.84, blue: 0.0)
                    )
                    .frame(minHeight: 280)
                }
                .padding(.horizontal, 16)
                
                // Focus Points - Full width card
                VStack(spacing: 12) {
                    HStack {
                        Text("Focus Points")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text("\(totalPoints)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
                .glassEffect()
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 24)
        .presentationDetents([.height(560)]) // Increased height for progress bar
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
    }
    
    private var streakProgressSection: some View {
        VStack(spacing: 12) {
            // Explainer text
            Text("Flip for 5min today to \(streakActionText) your streak")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 1.0, green: 0.5, blue: 0.0))
                        .frame(width: geometry.size.width * todayProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: todayProgress)
                }
            }
            .frame(height: 8)
            
            // Time remaining text
            if todayProgress < 1.0 {
                let remaining = 300 - todayTotalTime
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                Text("\(minutes)m \(seconds)s remaining")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("Streak goal achieved! 🔥")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.5, blue: 0.0))
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .glassEffect()
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(seconds))s"
        }
    }
}

struct CompactStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    var isActive: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 72, height: 72)
                
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(iconColor)
            }
            
            // Text content
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                if !subtitle.isEmpty {
                    VStack(spacing: 4) {
                        Text(value)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(isActive ? .white : .white.opacity(0.5))
                        
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    Text(value)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .glassEffect()
    }
}
