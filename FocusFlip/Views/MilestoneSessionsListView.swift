import SwiftUI
import SwiftData

struct MilestoneSessionsListView: View {
    @Environment(\.dismiss) private var dismiss
    let milestone: Milestone
    let sessions: [FocusSession]
    let user: User?
    
    @State private var selectedSessionForDetail: FocusSession?
    
    // Filter sessions that achieved this milestone
    private var milestoneSessions: [FocusSession] {
        // Find the next milestone to determine the upper bound for this milestone's range
        let nextMilestone = Milestone.allMilestones.first { $0.seconds > milestone.seconds }
        let upperBound = nextMilestone?.seconds ?? Int.max
        
        // Filter sessions that fall within this milestone's duration range
        let filtered = sessions.filter { session in
            let durationSeconds = Int(session.duration)
            return durationSeconds >= milestone.seconds && durationSeconds < upperBound
        }
        
        // Sort by endTime (most recent first)
        return filtered.sorted { $0.endTime > $1.endTime }
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
                    
                    Text("\(milestoneSessions.count) session\(milestoneSessions.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Sessions List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(milestoneSessions, id: \.id) { session in
                            sessionRow(session: session)
                        }
                    }
                    .padding(.horizontal, 20)
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
    
    private func sessionRow(session: FocusSession) -> some View {
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
                    Text(formattedDate(for: session.endTime))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(session.category.displayName)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
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
        let calendar = Calendar.current
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
}

