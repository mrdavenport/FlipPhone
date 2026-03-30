import SwiftUI
import StoreKit
import MessageUI

#if canImport(RiveRuntime)
import RiveRuntime
#endif

// Preference key to measure content height
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = false
    @State private var showShareSheet = false
    @State private var showFAQ = false
    @State private var contentHeight: CGFloat = 0

    #if DEBUG
    @AppStorage("rive_use_experimental_api") private var useExperimentalRiveAPI: Bool = false
    #endif
    
    var body: some View {
        ZStack {
            // Use material background for visual separation from content behind (iOS 18+ style)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Settings options
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "questionmark.circle.fill",
                        title: "About Flip Phone",
                        iconColor: Color(red: 0.0, green: 0.48, blue: 1.0)
                    ) {
                        showFAQ = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 60)
                    
                    SettingsRow(
                        icon: "star.fill",
                        title: "Rate on App Store",
                        iconColor: Color(red: 1.0, green: 0.84, blue: 0.0)
                    ) {
                        rateApp()
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 60)
                    
                    SettingsRow(
                        icon: "square.and.arrow.up.fill",
                        title: "Share Flip Phone",
                        iconColor: Color(red: 0.0, green: 0.78, blue: 0.33)
                    ) {
                        showShareSheet = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 60)
                    
                    SettingsRow(
                        icon: "hand.wave.fill",
                        title: "I'd love to hear from you!",
                        iconColor: Color(red: 1.0, green: 1.0, blue: 1.0)
                            
                    ) {
                        openTwitter()
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 60)
                    
                    // Sound Effects Toggle
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(ThemeManager.defaultColor.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeManager.defaultColor)
                        }
                        
                        Text("Sound Effects")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { AudioService.shared.isSoundEffectsEnabled },
                            set: { AudioService.shared.isSoundEffectsEnabled = $0 }
                        ))
                        .tint(ThemeManager.defaultColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    #if DEBUG
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 60)

                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(ThemeManager.defaultColor.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeManager.defaultColor)
                        }
                        
                        Text("Experimental Rive API")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: $useExperimentalRiveAPI)
                            .tint(ThemeManager.defaultColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    #endif
                }
                .glassEffect()
                .padding(.horizontal, 16)
                
                // Privacy Policy and Terms links
                HStack(spacing: 16) {
                    Button(action: {
                        openPrivacyPolicy()
                    }) {
                        Text("Privacy Policy")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text("•")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Button(action: {
                        openTermsOfUse()
                    }) {
                        Text("Terms of Use")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
                .padding(.horizontal, 16)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ContentHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
            .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                contentHeight = height
            }
        }
        .padding(.top, 24)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + 40)] : [.medium])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareAppText()])
        }
        .sheet(isPresented: $showFAQ) {
            FAQView()
        }
    }
    
    private func rateApp() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
        AnalyticsService.shared.logButtonTap("rate_app")
    }
    
    private func openTwitter() {
        let twitterURL = URL(string: "https://www.x.com/mrdavenport")!
        if UIApplication.shared.canOpenURL(twitterURL) {
            UIApplication.shared.open(twitterURL)
        }
        AnalyticsService.shared.logButtonTap("follow_twitter")
    }
    
    private func shareAppText() -> String {
        return "Check out FlipPhone - a focus app that helps you stay away from your phone! flipphone.co"
    }
    
    private func openPrivacyPolicy() {
        if let url = URL(string: "https://flipphone.co/privacy") {
            UIApplication.shared.open(url)
        }
        AnalyticsService.shared.logButtonTap("privacy_policy")
    }
    
    private func openTermsOfUse() {
        if let url = URL(string: "https://flipphone.co/terms") {
            UIApplication.shared.open(url)
        }
        AnalyticsService.shared.logButtonTap("terms_of_use")
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(iconColor)
                }
                
                // Title
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


