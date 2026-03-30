import SwiftUI

struct AddSessionView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onSave: (SessionData) -> Void
    
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var selectedCategory: SessionCategory = .other
    @State private var note: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Duration preview
                        durationPreview
                            .padding(.top, 20)
                        
                        // Start time picker
                        dateTimeSection(
                            title: "Start Time",
                            date: $startDate
                        )
                        
                        // End time picker
                        dateTimeSection(
                            title: "End Time",
                            date: $endDate
                        )
                        
                        // Category selector
                        categorySection
                        
                        // Note field
                        noteSection
                        
                        // Save button
                        saveButton
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Add Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private var durationPreview: some View {
        VStack(spacing: 8) {
            Text("Duration")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            
            Text(formatDuration(calculatedDuration))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func dateTimeSection(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .accentColor(.white)
                .colorScheme(.dark)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .onChange(of: date.wrappedValue) { _, _ in
                    // Ensure end date is after start date
                    if title == "Start Time" && endDate < startDate {
                        endDate = startDate.addingTimeInterval(3600) // Default to 1 hour later
                    } else if title == "End Time" && endDate < startDate {
                        endDate = startDate.addingTimeInterval(3600)
                    }
                }
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SessionCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: category.icon)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            
                            Text(category.displayName)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if selectedCategory == category {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding()
                        .background(selectedCategory == category ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note (Optional)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            TextField("Add a note...", text: $note, axis: .vertical)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.white)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .lineLimit(3...6)
        }
    }
    
    private var saveButton: some View {
        Button {
            let sessionData = SessionData(
                startTime: startDate,
                endTime: endDate,
                duration: calculatedDuration,
                category: selectedCategory,
                note: note
            )
            onSave(sessionData)
            dismiss()
        } label: {
            Text("Save Session")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(calculatedDuration <= 0)
        .opacity(calculatedDuration <= 0 ? 0.5 : 1.0)
    }
    
    private var calculatedDuration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
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
}

struct SessionData {
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let category: SessionCategory
    let note: String
}





