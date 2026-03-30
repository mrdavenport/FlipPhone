import SwiftUI
import MessageUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText: String = ""
    @State private var showMailComposer = false
    @State private var showMailError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("We'd love to hear your feedback!")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                TextEditor(text: $feedbackText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .frame(minHeight: 200)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
                    .overlay(
                        Group {
                            if feedbackText.isEmpty {
                                VStack {
                                    HStack {
                                        Text("Share your thoughts, suggestions, or report issues...")
                                            .foregroundColor(.white.opacity(0.4))
                                            .padding(.leading, 16)
                                            .padding(.top, 20)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
                
                Button(action: submitFeedback) {
                    Text("Submit Feedback")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .disabled(feedbackText.isEmpty)
                .opacity(feedbackText.isEmpty ? 0.6 : 1.0)
                
                Spacer()
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showMailComposer) {
                if MFMailComposeViewController.canSendMail() {
                    MailComposeView(
                        recipients: ["zack.davenport@gmail.com"],
                        subject: "FocusFlip App Feedback",
                        messageBody: feedbackText,
                        onDismiss: {
                            showMailComposer = false
                            dismiss()
                        }
                    )
                }
            }
            .alert("Cannot Send Email", isPresented: $showMailError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please configure an email account in the Mail app to send feedback.")
            }
        }
    }
    
    private func submitFeedback() {
        // Log feedback submission
        AnalyticsService.shared.logFeedbackSubmitted()
        
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            // Fallback: Open Mail app with mailto: link
            let email = "zack.davenport@gmail.com"
            let subject = "FocusFlip App Feedback"
            let body = feedbackText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            
            if let mailtoURL = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body)") {
                if UIApplication.shared.canOpenURL(mailtoURL) {
                    UIApplication.shared.open(mailtoURL)
                    // Dismiss after a short delay to allow Mail app to open
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                } else {
                    showMailError = true
                }
            } else {
                showMailError = true
            }
        }
    }
}

// MARK: - Mail Compose View

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let messageBody: String
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(recipients)
        composer.setSubject(subject)
        composer.setMessageBody(messageBody, isHTML: false)
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) {
                self.onDismiss()
            }
        }
    }
}

