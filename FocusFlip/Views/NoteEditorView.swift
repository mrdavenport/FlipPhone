import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var note: String
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                TextEditor(text: $note)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .font(.system(size: 16, design: .rounded))
                    .padding()
                    .background(Color.black)
                    .overlay(
                        Group {
                            if note.isEmpty {
                                VStack {
                                    HStack {
                                        Text("What were you focusing on?")
                                            .foregroundColor(.white.opacity(0.4))
                                            .font(.system(size: 16, design: .rounded))
                                            .padding(.leading, 20)
                                            .padding(.top, 20)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
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
        }
    }
}



