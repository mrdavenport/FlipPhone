import SwiftUI
import SwiftData
import WebKit

#if canImport(RiveRuntime)
import RiveRuntime
#endif

struct MilestonesView: View {
    @Environment(\.dismiss) private var dismiss
    let user: User?
    let sessions: [FocusSession]
    @State private var selectedSessionForDetail: FocusSession?
    @State private var selectedMilestoneForList: Milestone?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - native bottom sheet style
                VStack(spacing: 8) {
                    // Title - smaller, more subtle
                    Text("Milestones")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Progress count - secondary text
                    Text("\(completedMilestonesCount) of \(totalMilestonesCount) complete")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Milestones Grid
                ScrollView {
                    sessionMilestonesGrid
                }
            }
        }
        .sheet(item: $selectedMilestoneForList) { milestone in
            MilestoneSessionsListView(
                milestone: milestone,
                sessions: sessions,
                user: user
            )
        }
        .sheet(item: $selectedSessionForDetail) { session in
            SessionResultView(session: session, user: user) {
                selectedSessionForDetail = nil
            }
        }
        .onAppear {
            // Show skeletons briefly, then fade in real badges
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoading = false
            }
        }
    }
    
    // Filter milestones to only include those that have SVG badge files
    private var availableMilestones: [Milestone] {
        return Milestone.allMilestones.filter { milestone in
            let badgeName = "badge-\(milestone.label)"
            
            // Check if SVG file exists in Badges folder
            if Bundle.main.url(forResource: badgeName, withExtension: "svg", subdirectory: "Badges") != nil {
                return true
            }
            
            // Also check root bundle as fallback
            if Bundle.main.url(forResource: badgeName, withExtension: "svg") != nil {
                return true
            }
            
            // Handle 24hr+ case - try with "plus" instead of "+"
            let sanitizedLabel = milestone.label.replacingOccurrences(of: "+", with: "plus")
            let sanitizedBadgeName = "badge-\(sanitizedLabel)"
            if Bundle.main.url(forResource: sanitizedBadgeName, withExtension: "svg", subdirectory: "Badges") != nil {
                return true
            }
            
            return false
        }
    }
    
    private var totalMilestonesCount: Int {
        availableMilestones.count
    }

    private var completedMilestonesCount: Int {
        guard let user else { return 0 }
        let achieved = user.achievedMilestones ?? []
        return availableMilestones.filter { achieved.contains($0.seconds) }.count
    }
    
    private var sessionMilestonesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 32) {
            ForEach(availableMilestones, id: \.seconds) { milestone in
                milestoneCard(milestone: milestone)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .opacity(isLoading ? 0 : 1)
        .animation(.easeIn(duration: 0.3), value: isLoading)
    }
    
    // Helper to format the date when a milestone was achieved
    private func formattedDate(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    // Helper to get the range needed to achieve a milestone
    private func rangeForMilestone(_ milestone: Milestone) -> String {
        // Find the next milestone to determine the upper bound
        let nextMilestone = Milestone.allMilestones.first { $0.seconds > milestone.seconds }
        let upperBound = nextMilestone?.seconds ?? Int.max
        
        // Format the range
        let lowerMinutes = milestone.seconds / 60
        let upperMinutes = (upperBound - 1) / 60
        
        // Format based on whether it's minutes or hours
        if milestone.seconds < 3600 {
            // Minutes range
            if upperBound == Int.max {
                // Last milestone, show "X min+"
                return "\(lowerMinutes) min+"
            } else {
                return "\(lowerMinutes)-\(upperMinutes) min"
            }
        } else {
            // Hours range
            let lowerHours = milestone.seconds / 3600
            let upperHours = (upperBound - 1) / 3600
            
            if upperBound == Int.max {
                // Last milestone, show "X hr+"
                return "\(lowerHours) hr+"
            } else {
                return "\(lowerHours)-\(upperHours) hr"
            }
        }
    }
    
    
    private func isMilestoneCompleted(_ milestone: Milestone) -> Bool {
        guard let user = user else { return false }
        return (user.achievedMilestones ?? []).contains(milestone.seconds)
    }
    
    private func sessionForMilestone(_ milestone: Milestone) -> FocusSession? {
        // Find the MOST RECENT session that achieved this specific milestone
        // Each milestone is unlocked by sessions within a specific duration range:
        // - 10m milestone: sessions 10-14.99 min (600-899 seconds)
        // - 15m milestone: sessions 15-19.99 min (900-1199 seconds)
        // - 20m milestone: sessions 20-29.99 min (1200-1799 seconds)
        // - 30m milestone: sessions 30-39.99 min (1800-2399 seconds)
        // etc.
        
        // Find the next milestone to determine the upper bound for this milestone's range
        let nextMilestone = Milestone.allMilestones.first { $0.seconds > milestone.seconds }
        let upperBound = nextMilestone?.seconds ?? Int.max
        
        // Sort sessions by endTime (most recent first) to find the latest one in this range
        let sortedSessions = sessions.sorted { $0.endTime > $1.endTime }
        
        // Find the most recent session that falls within this milestone's duration range
        return sortedSessions.first { session in
            let durationSeconds = Int(session.duration)
            return durationSeconds >= milestone.seconds && durationSeconds < upperBound
        }
    }
    
    // Count how many sessions achieved this milestone
    private func achievementCount(for milestone: Milestone) -> Int {
        // Find the next milestone to determine the upper bound for this milestone's range
        let nextMilestone = Milestone.allMilestones.first { $0.seconds > milestone.seconds }
        let upperBound = nextMilestone?.seconds ?? Int.max
        
        // Count all sessions that fall within this milestone's duration range
        return sessions.filter { session in
            let durationSeconds = Int(session.duration)
            return durationSeconds >= milestone.seconds && durationSeconds < upperBound
        }.count
    }
    
    private func milestoneCard(milestone: Milestone) -> some View {
        let isCompleted = isMilestoneCompleted(milestone)
        let session = sessionForMilestone(milestone)
        let achievementCount = achievementCount(for: milestone)
        
        // Get category color from the session that achieved the milestone, or use default gold for completed
        let categoryColor: Color = {
            if isCompleted {
                if let session = session {
                    return session.category.color
                }
                return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold fallback
            }
            return Color.white.opacity(0.3) // Grey for incomplete
        }()
        
        return Button {
            if isCompleted {
                // If multiple sessions, show list view; otherwise show session detail directly
                if achievementCount > 1 {
                    selectedMilestoneForList = milestone
                } else if let session = session {
                    selectedSessionForDetail = session
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    // Show skeleton while loading, otherwise show badge
                    if isLoading {
                        skeletonImage(for: milestone)
                            .frame(width: 103, height: 103)
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        badgeImage(for: milestone, isCompleted: isCompleted, categoryColor: categoryColor)
                            .frame(width: 103, height: 103)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    
                    // Only show label for incomplete milestones (and not while loading)
                    if !isCompleted && !isLoading {
                        Text(milestone.label)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    
                    // Show date if completed (and not while loading)
                    if isCompleted && !isLoading, let session = session {
                        Text(formattedDate(for: session.endTime))
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Achievement count badge - only show if count > 1 and not loading
                if achievementCount > 1 && !isLoading {
                    Text("\(achievementCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(categoryColor)
                        .cornerRadius(10)
                        .offset(x: -16, y: 80)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isCompleted)
    }
    
    // Helper function to create skeleton placeholder using native SwiftUI shapes
    private func skeletonImage(for milestone: Milestone) -> some View {
        // Simple rounded rectangle skeleton - fast and native
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 103, height: 103)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
    
    // Helper function to load and display badge SVG with selective color replacement
    private func badgeImage(for milestone: Milestone, isCompleted: Bool, categoryColor: Color) -> some View {
        let badgeName = "badge-\(milestone.label)"
        
        // Try loading SVG and replacing the specific color
        if let svgView = loadSVGWithColorReplacement(badgeName: badgeName, isCompleted: isCompleted, categoryColor: categoryColor) {
            return AnyView(svgView)
        }
        
        // Handle 24hr+ case - try with "plus" instead of "+"
        let sanitizedLabel = milestone.label.replacingOccurrences(of: "+", with: "plus")
        let sanitizedBadgeName = "badge-\(sanitizedLabel)"
        if let svgView = loadSVGWithColorReplacement(badgeName: sanitizedBadgeName, isCompleted: isCompleted, categoryColor: categoryColor) {
            return AnyView(svgView)
        }
        
        // Final fallback: system icon
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(isCompleted ? categoryColor : .white.opacity(0.3))
        )
    }
    
    // Helper to load SVG and replace #8A49F4 with theme color
    private func loadSVGWithColorReplacement(badgeName: String, isCompleted: Bool, categoryColor: Color) -> AnyView? {
        // Try loading from Badges folder
        var url: URL?
        
        // Try 1: Badges subdirectory
        url = Bundle.main.url(forResource: badgeName, withExtension: "svg", subdirectory: "Badges")
        if url == nil {
            // Try 2: Root bundle (fallback)
            url = Bundle.main.url(forResource: badgeName, withExtension: "svg")
        }
        
        guard let fileURL = url else {
            #if DEBUG
            print("⚠️ Badge SVG file not found: \(badgeName).svg")
            #endif
            return nil
        }
        
        // Load SVG data and replace color
        guard let svgData = try? Data(contentsOf: fileURL),
              let svgString = String(data: svgData, encoding: .utf8) else {
            #if DEBUG
            print("⚠️ Failed to load SVG data from: \(fileURL.path)")
            #endif
            return nil
        }
        
        #if DEBUG
        print("✅ Successfully loaded SVG from Badges folder: \(badgeName).svg")
        #endif
        
        // Use SVGColorReplacementView to selectively replace #8A49F4
        return AnyView(SVGColorReplacementView(
            svgString: svgString,
            replacementColor: isCompleted ? categoryColor : Color.white,
            isCompleted: isCompleted
        ))
    }
}

// Helper extension to convert hex color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// View that loads SVG from string and replaces color
struct SVGColorReplacementView: View {
    let svgString: String
    let replacementColor: Color
    let isCompleted: Bool
    
    // Computed property to replace #8A49F4 with the replacement color hex value
    private var modifiedSVG: String {
        let replacementHex = replacementColor.toHexString()
        let replacementHexNoHash = replacementHex.replacingOccurrences(of: "#", with: "")
        
        // Replace #8A49F4 (with hash)
        var result = svgString.replacingOccurrences(
            of: "#8A49F4",
            with: replacementHex,
            options: .caseInsensitive
        )
        // Replace 8A49F4 (without hash)
        result = result.replacingOccurrences(
            of: "8A49F4",
            with: replacementHexNoHash,
            options: .caseInsensitive
        )
        // Replace #8a49f4 (lowercase with hash)
        result = result.replacingOccurrences(
            of: "#8a49f4",
            with: replacementHex,
            options: .caseInsensitive
        )
        // Replace 8a49f4 (lowercase without hash)
        result = result.replacingOccurrences(
            of: "8a49f4",
            with: replacementHexNoHash,
            options: .caseInsensitive
        )
        
        return result
    }
    
    var body: some View {
        // Render using WKWebView
        SVGWebView(svgString: modifiedSVG)
            .grayscale(isCompleted ? 0 : 1)
            .opacity(isCompleted ? 1.0 : 0.5)
    }
}

// WebView wrapper for SVG rendering
struct SVGWebView: UIViewRepresentable {
    let svgString: String
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        
        // Load the SVG immediately
        loadSVG(in: webView)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        loadSVG(in: webView)
    }
    
    private func loadSVG(in webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { 
                    width: 100%; 
                    height: 100%; 
                    overflow: hidden; 
                    background: transparent; 
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                svg { 
                    width: 100%; 
                    height: 100%; 
                    display: block;
                    max-width: 100%;
                    max-height: 100%;
                }
            </style>
        </head>
        <body>
            \(svgString)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

extension Color {
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb: Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
        return String(format: "#%06x", rgb)
    }
}

