import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let session: FocusSession
    let user: User?
    var onDelete: (() -> Void)? // Callback when session is deleted
    
    @State private var editedNote: String = ""
    @State private var editedCategory: SessionCategory = .other
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Session Duration
                    VStack(spacing: 8) {
                        // Personal Best Badge
                        if session.isPersonalRecord {
                            personalBestBadge
                                .padding(.top, 32)
                        }
                        
                        Text(session.formattedDuration)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Focus Duration")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, session.isPersonalRecord ? 8 : 32)
                    .padding(.bottom, 32)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    
                    // Date and Time
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(icon: "calendar", title: "Date", value: formattedDate)
                        detailRow(icon: "clock", title: "Time", value: formattedTimeRange)
                        detailRow(icon: "star.fill", title: "Points", value: "+\(session.points)")
                        detailRow(icon: session.category.icon, title: "Category", value: session.category.displayName, iconColor: session.category.color)
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    
                    // Note Editor
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Note")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        ZStack(alignment: .topLeading) {
                            if editedNote.isEmpty {
                                Text("Add a note about this session...")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            
                            TextEditor(text: $editedNote)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .frame(minHeight: 100)
                                .padding(4)
                        }
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    
                    // Category Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(SessionCategory.allCases) { category in
                                categoryButton(category: category)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    
                    // Delete Button
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("Delete Session")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 32)
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                editedNote = session.note
                editedCategory = session.category
            }
            .alert("Delete Session?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSession()
                }
            } message: {
                Text("This action cannot be undone. The session and its points will be permanently removed.")
            }
        }
    }
    
    private func deleteSession() {
        // Capture session ID before deletion
        let sessionId = session.id
        let points = session.points
        let duration = session.duration
        
        // Get all sessions before deletion to check milestones
        let allSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let remainingSessions = allSessions.filter { $0.id != sessionId }
        
        // Update user stats if needed
        if let user = user {
            user.totalPoints = max(0, user.totalPoints - points)
            user.totalFocusTime = max(0, user.totalFocusTime - duration)
            user.sessionsCompleted = max(0, user.sessionsCompleted - 1)
            
            // Recalculate longest session from all remaining sessions
            user.longestSession = remainingSessions.map { $0.duration }.max() ?? 0
            
            // Recalculate streaks with remaining sessions
            user.updateStats(with: session, allSessions: remainingSessions)
            
            // Check if deleted session achieved a milestone, and if so, check if any other session also achieved it
            if let deletedMilestone = Milestone.milestoneForDuration(duration) {
                let achievedMilestones = user.achievedMilestones ?? []
                
                // Check if any remaining session falls within this milestone's duration range
                let otherSessionsAchievedThisMilestone = remainingSessions.contains { remainingSession in
                    if let remainingMilestone = Milestone.milestoneForDuration(remainingSession.duration) {
                        return remainingMilestone.seconds == deletedMilestone.seconds
                    }
                    return false
                }
                
                // If no other session achieved this milestone, remove it from achieved milestones
                if !otherSessionsAchievedThisMilestone && achievedMilestones.contains(deletedMilestone.seconds) {
                    var updatedMilestones = achievedMilestones
                    updatedMilestones.removeAll { $0 == deletedMilestone.seconds }
                    user.achievedMilestones = updatedMilestones
                }
            }
        }
        
        // Delete the session
        modelContext.delete(session)
        try? modelContext.save()
        
        // Call onDelete callback
        onDelete?()
        
        // Dismiss the view
        dismiss()
    }
    
    private func detailRow(icon: String, title: String, value: String, iconColor: Color = .white) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
    }
    
    private func categoryButton(category: SessionCategory) -> some View {
        Button {
            editedCategory = category
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(category.color)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text(category.displayName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(editedCategory == category ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(editedCategory == category ? category.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: session.endTime)
    }
    
    private var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: session.startTime)) - \(formatter.string(from: session.endTime))"
    }
    
    private func saveChanges() {
        // Update session properties directly (not using @Bindable)
        session.note = editedNote
        session.category = editedCategory
        try? modelContext.save()
        dismiss()
    }
    
    private var personalBestBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Personal best!")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.69, green: 0.49, blue: 1.0),
                    Color(red: 0.55, green: 0.39, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
    }
}

