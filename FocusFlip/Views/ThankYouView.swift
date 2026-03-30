import SwiftUI

struct ThankYouView: View {
    @Binding var isPresented: Bool
    // Update this with your actual App Store URL
    // Format: https://apps.apple.com/app/id[YOUR_APP_ID]
    // Or use: https://apps.apple.com/app/flipphone/id[YOUR_APP_ID]
    private var appStoreURL: String {
        // You can find your App Store ID in App Store Connect
        // For now, using a placeholder - update this before building
        return "https://apps.apple.com/app/flipphone/id6739702000"
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Thank you message
                VStack(spacing: 16) {
                    Text("Thank You!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Flip Phone is now live in the App Store!")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text("Thank you so much for being a beta tester. Your feedback and support helped make Flip Phone what it is today.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // CTA Button
                Button(action: {
                    openAppStore()
                }) {
                    HStack(spacing: 8) {
                        Text("Download from App Store")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
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
                    .cornerRadius(24)
                }
                .buttonStyle(.plain)
                
                // Dismiss button
                Button(action: {
                    isPresented = false
                }) {
                    Text("Continue with TestFlight")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                
                Spacer()
            }
        }
    }
    
    private func openAppStore() {
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ThankYouView(isPresented: .constant(true))
}

