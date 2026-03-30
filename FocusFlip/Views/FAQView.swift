import SwiftUI

struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Introduction Section
                        introductionSection
                        
                        // FAQ Items (16px spacing between cards, 0px after intro section)
                        VStack(spacing: 16) {
                            FAQItem(
                            question: "Why did I make Flip Phone?",
                            answer: "As someone who's struggled with ADHD their entire life, I made Flip Phone to help bring intentionality to my phone usage.\n\nI hope it helps you as much as its helped me."
                        )
                        
                        FAQItem(
                            question: "How does it work?",
                            answer: "FlipPhone uses your device's motion sensors to detect when your phone is face down. When you flip your phone over, it automatically starts a focus session. Flip it back over to end the session and see your results."
                        )
                        
                        FAQItem(
                            question: "Do I need to keep the app open?",
                            answer: "Yes, FlipPhone needs to be running in the foreground to track your focus sessions. Make sure to keep the app open and your phone face down during your focus time. Your phone will automatically go to sleep after 30 seconds (unless you've changed your phone's auto-lock settings), which helps conserve battery while still tracking your session."
                        )
                        
                        FAQItem(
                            question: "What counts as a focus session?",
                            answer: "Any time your phone is face down for at least 5 seconds counts as a focus session. The longer you keep it face down, the more focus time you accumulate and the more points you earn."
                        )
                        
                        FAQItem(
                            question: "How do streaks work?",
                            answer: "Your streak increases each day you complete at least one focus session. If you miss a day, your current streak resets to 1. Your longest streak tracks your all-time best consecutive days."
                        )
                        
                        FAQItem(
                            question: "Can I use it with other apps?",
                            answer: "FlipPhone needs to be the active app to track your focus sessions. However, you can still receive notifications and use other features while your phone is face down."
                        )
                        
                        FAQItem(
                            question: "How are points calculated?",
                            answer: "You earn 1 point for every minute of focus time. Longer sessions earn more points, helping you track your progress and build healthy focus habits."
                        )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("FAQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Introduction Section
    
    private var introductionSection: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Speech bubble - spans to right edge
                HStack(alignment: .bottom, spacing: 0) {
                    // Spacer to push speech bubble to right (bio pic width + spacing)
                    Spacer()
                        .frame(width: 145) // 129 (bio pic) + 16 (spacing)
                    
                    // Speech bubble container
                    ZStack(alignment: .bottomTrailing) {
                        // Speech bubble background
                        Text("Hey! I'm Zack, the human behind Flip Phone.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(16)
                        
                        // "Say hi" button - hanging 20px lower than speech bubble
                        Button(action: {
                            openTwitter()
                        }) {
                            HStack(spacing: 6) {
                                Text("Say hi")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
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
                        .buttonStyle(.plain)
                        .offset(x: -8, y: 20) // 20px lower than speech bubble
                    }
                    .frame(maxWidth: .infinity) // Span to right edge
                }
                
                // Bio pic - bottom left aligned, larger size, offset 20px to match button
                Image("bio-pic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 129, height: 129)
                    .offset(y: 20) // Offset to share bottom edge with "Say hi" button
            }
        }
        .frame(height: 150) // Increased height for larger bio pic
        .padding(.horizontal, 20)
    }
    
    private func openTwitter() {
        let url = URL(string: "https://www.x.com/mrdavenport")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        AnalyticsService.shared.logButtonTap("say_hi_twitter")
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text(answer)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
    }
}

