import SwiftUI
import SwiftData
import WebKit
import Photos
import MessageUI

struct ShareableGraphicView: View {
    let session: FocusSession
    let milestone: Milestone?
    let categoryColor: Color
    let isFirstTimeAchievingMilestone: Bool
    let isPersonalBest: Bool
    
    // Graphic dimensions - card aspect ratio (card width with 20px padding on each side)
    // Card height is 540, width is screen width minus 40 (20px padding each side)
    // For standard iPhone (375pt width), card is 335x540
    // Using 335:540 ratio for shareable graphic
    private let cardWidth: CGFloat = 335
    private let cardHeight: CGFloat = 540
    private let graphicSize: CGSize = CGSize(width: 335, height: 540)
    
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showMessageComposer = false
    
    var body: some View {
        ZStack {
            // Sheet background - theme color
            categoryColor.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Preview Section
                VStack(spacing: 16) {
                    Text("Preview")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Preview of the shareable graphic (scaled down, maintaining card aspect ratio)
                    HStack {
                        Spacer()
                        graphicContentView
                            .frame(width: 200, height: 322) // 335:540 ratio scaled down (200 * 540/335 ≈ 322)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        Spacer()
                    }
                }
                .padding(.top, 20)
                
                // Action Buttons
                actionButtons
                
                if showSuccessMessage {
                    Text(successMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, -8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage = shareImage {
                let shareText = "Think you can stay off your phone longer than me? Download FlipPhone.co and try!"
                ShareSheet(activityItems: [shareImage, shareText])
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            if let image = capturedImage {
                MessageComposeView(
                    image: image,
                    message: "Think you can stay off your phone longer than me? Download FlipPhone.co and try!"
                ) {
                    showMessageComposer = false
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // First row: Messages, Copy
            HStack(spacing: 12) {
                actionButton(
                    icon: "message.fill",
                    label: "Messages",
                    action: shareToMessages
                )
                
                actionButton(
                    icon: "doc.on.doc.fill",
                    label: "Copy",
                    action: copyGraphic
                )
            }
            
            // Second row: Download, More
            HStack(spacing: 12) {
                actionButton(
                    icon: "arrow.down.circle.fill",
                    label: "Download",
                    action: downloadGraphic
                )
                
                actionButton(
                    icon: "ellipsis.circle.fill",
                    label: "More",
                    action: shareMore
                )
            }
        }
    }
    
    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.2))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Graphic Content (full size for rendering)
    
    @State private var capturedImage: UIImage? = nil
    
    var graphicContentView: some View {
        Group {
            if let image = capturedImage {
                // Show captured image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Placeholder while capturing
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .onAppear {
            // Capture the SessionResultView when view appears
            captureSessionResultView()
        }
    }
    
    // Capture SessionResultView as UIImage using ImageRenderer
    private func captureSessionResultView() {
        // Create a SessionResultView with controls hidden
        // Note: We pass nil for user since ShareableGraphicView doesn't have access to it
        // The view should still render correctly for static image capture
        let renderView = SessionResultView(
            session: session,
            user: nil, // User data not needed for static image capture
            hideControlsForSharing: true
        )
        .frame(width: graphicSize.width, height: graphicSize.height)
        
        // Use ImageRenderer to capture the view
        // ImageRenderer will render the view with its current state
        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 2.0 // Retina quality (2x)
        
        // Generate the image asynchronously (give SwiftUI time to layout)
        // Note: ImageRenderer may not work perfectly with @Query/@Environment views
        // If this fails, we may need to provide a ModelContainer or use a different approach
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            if let uiImage = renderer.uiImage {
                self.capturedImage = uiImage
                #if DEBUG
                print("✅ Successfully captured SessionResultView, size: \(uiImage.size)")
                #endif
            } else {
                #if DEBUG
                print("⚠️ Failed to capture SessionResultView image - this may be due to @Query/@Environment dependencies")
                #endif
            }
        }
    }
    
    private var codeGeneratedGraphicView: some View {
        ZStack {
            // Background - black
            Color.black
            
            VStack(spacing: 0) {
                // Date of session - center aligned above title (only for milestone sessions)
                if milestone != nil {
                    Text(formattedSessionDate)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 32)
                }
                
                // Title - dynamic based on milestone achievement status
                Text(milestoneTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, milestone != nil ? 8 : 32)
                
                // Flexible spacer - centers duration between header and metadata
                Spacer(minLength: 16)
                
                // Badge or duration display
                if milestone != nil {
                    VStack(spacing: 16) {
                        // Badge image from SVG
                        if let milestone = milestone {
                            badgeImage(for: milestone)
                                .frame(width: 200, height: 200)
                                .aspectRatio(1, contentMode: .fit)
                        }
                        
                        // Session duration below badge
                        Text(session.formattedDuration)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                } else {
                    // For non-milestone sessions, show duration prominently
                    Text(session.formattedDuration)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                // Note or default text
                Text(!session.note.isEmpty ? session.note : "total focus time")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 16)
                
                // Personal best banner (if applicable)
                if isPersonalBest {
                    personalBestBanner
                        .padding(.top, 8)
                }
                
                // Flexible spacer - pushes metadata to bottom
                Spacer()
                
                // Category info at bottom
                categoryInfoCard
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 40)
            .frame(width: graphicSize.width, height: graphicSize.height)
        }
    }
    
    // MARK: - UI Components
    
    private func badgeImage(for milestone: Milestone) -> some View {
        let badgeName = "badge-\(milestone.label)"
        
        // Try loading SVG and replacing the specific color
        if let svgView = loadSVGWithColorReplacement(badgeName: badgeName, isCompleted: true, categoryColor: categoryColor) {
            return AnyView(svgView)
        }
        
        // Handle 24hr+ case - try with "plus" instead of "+"
        let sanitizedLabel = milestone.label.replacingOccurrences(of: "+", with: "plus")
        let sanitizedBadgeName = "badge-\(sanitizedLabel)"
        if let svgView = loadSVGWithColorReplacement(badgeName: sanitizedBadgeName, isCompleted: true, categoryColor: categoryColor) {
            return AnyView(svgView)
        }
        
        // Fallback: system icon
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 80, weight: .semibold, design: .rounded))
                .foregroundColor(categoryColor)
        )
    }
    
    private var personalBestBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("New Personal Best!")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    categoryColor,
                    categoryColor.opacity(0.7)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
    }
    
    private var categoryInfoCard: some View {
        HStack(spacing: 16) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 48, height: 48)
                
                Image(systemName: session.category.icon)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedTimeRange)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(session.category.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("\(session.formattedDuration) + \(session.points) pts")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Formatting Helpers
    
    private var formattedSessionDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let dateString = formatter.string(from: session.startTime)
        
        // Add ordinal suffix (st, nd, rd, th)
        let day = Calendar.current.component(.day, from: session.startTime)
        let suffix: String
        switch day {
        case 1, 21, 31:
            suffix = "st"
        case 2, 22:
            suffix = "nd"
        case 3, 23:
            suffix = "rd"
        default:
            suffix = "th"
        }
        
        return "\(dateString)\(suffix)"
    }
    
    private var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        let start = formatter.string(from: session.startTime).lowercased()
        let end = formatter.string(from: session.endTime).lowercased()
        return "\(start) - \(end)"
    }
    
    private var milestoneTitle: String {
        guard milestone != nil else {
            return "Focus session\ncomplete"
        }
        
        if isFirstTimeAchievingMilestone {
            return "New milestone achieved!"
        }
        
        // For repeat achievements, cycle through celebratory messages
        let durationInMinutes = session.duration / 60
        let celebrationMessages: [String]
        
        if durationInMinutes >= 60 {
            celebrationMessages = [
                "You're crushing it",
                "You're unstoppable",
                "Way to focus!",
                "Phenomenal flip!",
                "Flippin' awesome!",
                "You're on fire!"
            ]
        } else if durationInMinutes >= 30 {
            celebrationMessages = [
                "Nice one!",
                "Way to focus!",
                "Nice flip!",
                "Great job!",
                "That's how it's done!"
            ]
        } else {
            celebrationMessages = [
                "Good job!",
                "Way to go!",
                "Nice work!",
                "Keep it up!",
                "Awesome focus!"
            ]
        }
        
        // Cycle through messages based on session ID hash
        let index = abs(session.id.hashValue) % celebrationMessages.count
        return celebrationMessages[index]
    }
    
    // MARK: - Gradient
    
    private var categoryGradient: some View {
        let uiColor = UIColor(categoryColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Create gradient colors based on category color
        let topColor = Color(red: min(red + 0.2, 1.0), green: min(green + 0.2, 1.0), blue: min(blue + 0.2, 1.0))
        let midTopColor = Color(red: red, green: green, blue: blue)
        let midBottomColor = Color(red: max(red - 0.1, 0.0), green: max(green - 0.1, 0.0), blue: max(blue - 0.1, 0.0))
        let bottomColor = Color(red: max(red - 0.2, 0.0), green: max(green - 0.2, 0.0), blue: max(blue - 0.2, 0.0))
        
        return LinearGradient(
            colors: [topColor, midTopColor, midBottomColor, bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - SVG Loading (reused from MilestonesView)
    
    private func loadSVGWithColorReplacement(badgeName: String, isCompleted: Bool, categoryColor: Color) -> AnyView? {
        guard let svgString = SVGCache.shared.rawSVG(named: badgeName) else { return nil }
        return AnyView(SVGColorReplacementView(
            svgString: svgString,
            replacementColor: isCompleted ? categoryColor : Color.white,
            isCompleted: isCompleted
        ))
    }
    
    // MARK: - Action Handlers
    
    private func shareToMessages() {
        guard let image = capturedImage else {
            successMessage = "Image not ready yet"
            withAnimation { showSuccessMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSuccessMessage = false }
            }
            return
        }
        
        // Check if Messages is available
        guard MFMessageComposeViewController.canSendText() else {
            successMessage = "Messages not available"
            withAnimation { showSuccessMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSuccessMessage = false }
            }
            return
        }
        
        showMessageComposer = true
    }
    
    private func copyGraphic() {
        guard let image = capturedImage else {
            successMessage = "Image not ready yet"
            withAnimation { showSuccessMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSuccessMessage = false }
            }
            return
        }
        
        // Copy image and text to clipboard
        let shareText = "Think you can stay off your phone longer than me? Download FlipPhone.co and try!"
        UIPasteboard.general.image = image
        UIPasteboard.general.string = shareText
        successMessage = "Copied to clipboard!"
        withAnimation { showSuccessMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSuccessMessage = false }
        }
    }
    
    private func downloadGraphic() {
        guard let image = capturedImage else {
            successMessage = "Image not ready yet"
            withAnimation { showSuccessMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSuccessMessage = false }
            }
            return
        }
        
        // Save image to Photos
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        successMessage = "Saved to Photos!"
        withAnimation { showSuccessMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSuccessMessage = false }
        }
    }
    
    private func shareMore() {
        guard let image = capturedImage else {
            successMessage = "Image not ready yet"
            withAnimation { showSuccessMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSuccessMessage = false }
            }
            return
        }
        
        // Show share sheet with image and text
        shareImage = image
        showShareSheet = true
    }
    
    // MARK: - Image Generation (using ImageRenderer capture)
    
    private func generateGraphicImage() -> UIImage? {
        // Use the captured image if available
        return capturedImage
    }
    
    // Load SVG template from bundle
    private func loadSVGTemplate() -> String? {
        // Try loading from bundle - user will provide template file
        // Try multiple filename variations and locations
        let possibleNames = [
            "shareable-template_milestone3",  // User's test file
            "shareable-graphic-template"      // Default name
        ]
        
        let possibleLocations = [
            nil,                              // Root bundle
            "Templates",                      // Templates subdirectory
            "Assets",                         // Assets subdirectory
            "Badges"                          // Badges folder
        ]
        
        #if DEBUG
        print("🔍 Searching for SVG template...")
        if let resourcePath = Bundle.main.resourcePath {
            print("📦 Bundle resource path: \(resourcePath)")
            // List all SVG files in the bundle
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                let svgFiles = contents.filter { $0.hasSuffix(".svg") }
                print("📋 SVG files in bundle root: \(svgFiles)")
            }
        }
        #endif
        
        for name in possibleNames {
            for location in possibleLocations {
                var url: URL?
                let locationDesc = location ?? "root bundle"
                
                if let location = location {
                    url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: location)
                } else {
                    url = Bundle.main.url(forResource: name, withExtension: "svg")
                }
                
                #if DEBUG
                if let fileURL = url {
                    print("✅ Found potential match at: \(fileURL.path) (location: \(locationDesc))")
                } else {
                    print("❌ Not found: \(name).svg in \(locationDesc)")
                }
                #endif
                
                if let fileURL = url {
                    guard let svgString = try? String(contentsOf: fileURL) else {
                        #if DEBUG
                        print("⚠️ Could not read SVG template from: \(fileURL.path)")
                        #endif
                        continue
                    }
                    
                    #if DEBUG
                    print("✅ Successfully loaded SVG template from: \(fileURL.path)")
                    print("📄 Template size: \(svgString.count) characters")
                    #endif
                    
                    return svgString
                }
            }
        }
        
        #if DEBUG
        print("⚠️ SVG template file not found after searching all locations.")
        print("   Looking for: shareable-template_milestone3.svg or shareable-graphic-template.svg")
        print("   Tried locations: root bundle, Templates/, Assets/, Badges/")
        print("   💡 Make sure the file is added to your Xcode project target AND included in 'Copy Bundle Resources'")
        #endif
        
        return nil
    }
    
    // Replace template placeholders with actual session data
    private func replaceTemplatePlaceholders(template: String) -> String {
        var result = template
        
        // Replace milestone badge SVG placeholder FIRST (before other replacements)
        // This handles the case where {{MILESTONE_BADGE_SVG}} is used as an id attribute
        if let milestone = milestone {
            // Load badge SVG and inline it (with color replacement)
            if let badgeSVG = loadBadgeSVGForTemplate(for: milestone) {
                // Replace the entire <rect> element that has id="{{MILESTONE_BADGE_SVG}}"
                // Escape braces properly in regex pattern
                let placeholderPattern = #"<rect[^>]*id="\{\{MILESTONE_BADGE_SVG\}\}"[^>]*/>"#
                if let range = result.range(of: placeholderPattern, options: .regularExpression) {
                    result.replaceSubrange(range, with: badgeSVG)
                } else {
                    // Fallback: replace placeholder text directly anywhere in the SVG
                    result = result.replacingOccurrences(of: "{{MILESTONE_BADGE_SVG}}", with: badgeSVG)
                }
            } else {
                // Remove the placeholder rect element entirely if no badge
                let placeholderPattern = #"<rect[^>]*id="\{\{MILESTONE_BADGE_SVG\}\}"[^>]*/>"#
                result = result.replacingOccurrences(of: placeholderPattern, with: "", options: .regularExpression)
                result = result.replacingOccurrences(of: "{{MILESTONE_BADGE_SVG}}", with: "")
            }
        } else {
            // Remove badge placeholder if no milestone
            let placeholderPattern = #"<rect[^>]*id="\{\{MILESTONE_BADGE_SVG\}\}"[^>]*/>"#
            result = result.replacingOccurrences(of: placeholderPattern, with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: "{{MILESTONE_BADGE_SVG}}", with: "")
        }
        
        // Replace text placeholders (escape HTML entities for safety)
        let safeNote = (!session.note.isEmpty ? session.note : "total focus time")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        result = result.replacingOccurrences(of: "{{SESSION_DURATION}}", with: session.formattedDuration)
        result = result.replacingOccurrences(of: "{{CATEGORY_NAME}}", with: session.category.displayName)
        // Replace category color - remove the # from hex string since template already has # before placeholder
        let categoryColorHex = categoryColor.toHexString().replacingOccurrences(of: "#", with: "")
        result = result.replacingOccurrences(of: "{{CATEGORY_COLOR}}", with: categoryColorHex)
        result = result.replacingOccurrences(of: "{{NOTE}}", with: safeNote)
        result = result.replacingOccurrences(of: "{{DATE}}", with: formattedSessionDate)
        result = result.replacingOccurrences(of: "{{TIME_RANGE}}", with: formattedTimeRange)
        result = result.replacingOccurrences(of: "{{POINTS}}", with: "\(session.points)")
        
        // Replace milestone-specific placeholders if applicable
        if let milestone = milestone {
            result = result.replacingOccurrences(of: "{{MILESTONE_LABEL}}", with: milestone.label)
            result = result.replacingOccurrences(of: "{{MILESTONE_TITLE}}", with: milestoneTitle)
        }
        
        // Handle personal best
        if isPersonalBest {
            result = result.replacingOccurrences(of: "{{PERSONAL_BEST}}", with: "New Personal Best!")
        } else {
            result = result.replacingOccurrences(of: "{{PERSONAL_BEST}}", with: "")
        }
        
        // Handle category icon - for now, just remove placeholder (icon can be static in design)
        result = result.replacingOccurrences(of: "{{CATEGORY_ICON_SVG}}", with: "")
        
        // Keep the original SVG dimensions - don't change width/height attributes
        // The SVG should scale naturally using its viewBox
        // The original template is 236x354, and we'll let it scale to fit the container
        // This ensures proper aspect ratio preservation
        
        // Add preserveAspectRatio to ensure proper scaling
        if !result.contains("preserveAspectRatio=") {
            if let svgTagRange = result.range(of: #"<svg[^>]*>"#, options: .regularExpression) {
                let svgTag = String(result[svgTagRange])
                let newSvgTag = svgTag.replacingOccurrences(
                    of: #"(viewBox="[^"]*")"#,
                    with: #"$1 preserveAspectRatio="xMidYMid meet""#,
                    options: .regularExpression
                )
                if newSvgTag != svgTag {
                    result.replaceSubrange(svgTagRange, with: newSvgTag)
                } else {
                    // If no viewBox, add preserveAspectRatio anyway
                    let newSvgTag2 = svgTag.replacingOccurrences(
                        of: #">$"#,
                        with: #" preserveAspectRatio="xMidYMid meet">"#,
                        options: .regularExpression
                    )
                    result.replaceSubrange(svgTagRange, with: newSvgTag2)
                }
            }
        }
        
        // Inject CSS to apply SF Pro Rounded to all text elements
        // Insert a <style> tag right after the opening <svg> tag
        if let svgTagRange = result.range(of: #"<svg[^>]*>"#, options: .regularExpression) {
            let _ = String(result[svgTagRange]) // Check if SVG tag exists
            let afterSvgTag = result.index(svgTagRange.upperBound, offsetBy: 0)
            
            // Check if there's already a <style> tag
            if !result.contains("<style>") && !result.contains("<defs>") {
                let styleTag = """
                
                <style>
                    text {
                        font-family: -apple-system, "SF Pro Rounded", "SF Pro Text", system-ui, sans-serif;
                        -webkit-font-smoothing: antialiased;
                        -moz-osx-font-smoothing: grayscale;
                    }
                </style>
                """
                result.insert(contentsOf: styleTag, at: afterSvgTag)
            }
        }
        
        return result
    }
    
    // Load badge SVG and apply color replacement for template embedding
    private func loadBadgeSVGForTemplate(for milestone: Milestone) -> String? {
        let badgeName = "badge-\(milestone.label)"
        var url: URL?
        
        url = Bundle.main.url(forResource: badgeName, withExtension: "svg", subdirectory: "Badges")
        if url == nil {
            url = Bundle.main.url(forResource: badgeName, withExtension: "svg")
        }
        
        // Handle 24hr+ case
        if url == nil {
            let sanitizedLabel = milestone.label.replacingOccurrences(of: "+", with: "plus")
            let sanitizedBadgeName = "badge-\(sanitizedLabel)"
            url = Bundle.main.url(forResource: sanitizedBadgeName, withExtension: "svg", subdirectory: "Badges")
            if url == nil {
                url = Bundle.main.url(forResource: sanitizedBadgeName, withExtension: "svg")
            }
        }
        
        guard let fileURL = url,
              let svgString = try? String(contentsOf: fileURL) else {
            return nil
        }
        
        // Replace color in badge SVG
        let categoryColorHex = categoryColor.toHexString()
        let categoryColorHexNoHash = categoryColorHex.replacingOccurrences(of: "#", with: "")
        
        var badgeSVG = svgString
        badgeSVG = badgeSVG.replacingOccurrences(of: "#8A49F4", with: categoryColorHex, options: .caseInsensitive)
        badgeSVG = badgeSVG.replacingOccurrences(of: "8A49F4", with: categoryColorHexNoHash, options: .caseInsensitive)
        
        return badgeSVG
    }
    
    // Convert SVG string to UIImage using WKWebView snapshot
    private func svgStringToUIImage(svgString: String, size: CGSize) -> UIImage? {
        // TODO: Implement SVG to UIImage conversion
        // Options:
        // 1. Use WKWebView to render and capture snapshot (async, complex)
        // 2. Use SVGKit library (if added as dependency)
        // 3. Use Core Graphics with SVG rendering library
        
        // For now, return nil - will need async implementation
        return nil
    }
}

// MARK: - Message Compose View

struct MessageComposeView: UIViewControllerRepresentable {
    let image: UIImage
    let message: String
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        
        // Add image as attachment
        if let imageData = image.pngData() {
            composer.addAttachmentData(imageData, typeIdentifier: "public.png", filename: "flipPhone-share.png")
        }
        
        // Set message body
        composer.body = message
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.onDismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleSession = FocusSession(
        startTime: Date(),
        endTime: Date().addingTimeInterval(1800),
        duration: 1800,
        note: "Great focus session!",
        points: 60,
        isPersonalRecord: false,
        category: .work
    )
    
    ShareableGraphicView(
        session: sampleSession,
        milestone: Milestone.allMilestones.first { $0.seconds == 1800 },
        categoryColor: .blue,
        isFirstTimeAchievingMilestone: true,
        isPersonalBest: false
    )
}

