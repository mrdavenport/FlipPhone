import SwiftUI
import SwiftData
import UIKit
import WebKit

#if canImport(RiveRuntime)
import RiveRuntime
#endif

struct SessionResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.duration, order: .reverse) private var allSessions: [FocusSession]
    @Bindable var session: FocusSession
    let user: User?
    let hideControlsForSharing: Bool // When true, hides edit button and Share/Done buttons for image capture
    
    @State private var note: String = ""
    @State private var selectedCategory: SessionCategory = .other
    @State private var showShareSheet = false
    @State private var showCategoryPicker = false
    @State private var showEditDetailsSheet = false
    @State private var showShareableGraphic = false
    @State private var displayedMilestone: Milestone? // Store milestone at initialization
    @State private var showDeletedToast = false
    @State private var wasSessionDeleted = false
    @State private var showConfetti = false
    
    // Force RiveViewWrapper recreation on every appearance so the Rive state machine
    // re-runs binding/trigger logic (color should not revert after close/reopen).
    @State private var milestoneResultsRiveRefreshToken = UUID()
    @State private var sessionResultsRiveRefreshToken = UUID()
    
    // Cache session data to prevent crashes after deletion
    @State private var cachedSessionData: CachedSessionData?
    
    // Helper struct to cache session data
    private struct CachedSessionData {
        let id: UUID
        let duration: Double
        let formattedDuration: String
        let points: Int
        let startTime: Date
        let endTime: Date
        let pauseCountValue: Int
        
        // Helper to format duration
        static func formatDuration(_ duration: TimeInterval) -> String {
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
    
    var onDismiss: (() -> Void)?
    
    // Default initializer - hideControlsForSharing defaults to false for normal use
    init(session: FocusSession, user: User?, hideControlsForSharing: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.user = user
        self.hideControlsForSharing = hideControlsForSharing
        self.onDismiss = onDismiss
    }
    
    // Safe access to session data (uses cache if session was deleted)
    private var safeSession: CachedSessionData {
        if let cached = cachedSessionData {
            return cached
        }
        // Create cache from current session (only if session still exists)
        // This should only happen if onAppear hasn't run yet, which is safe
        let cache = CachedSessionData(
            id: session.id,
            duration: session.duration,
            formattedDuration: CachedSessionData.formatDuration(session.duration),
            points: session.points,
            startTime: session.startTime,
            endTime: session.endTime,
            pauseCountValue: session.pauseCountValue
        )
        cachedSessionData = cache
        return cache
    }
    
    private var isPersonalBest: Bool {
        guard let longestSession = allSessions.first else { return false }
        let safe = safeSession
        return safe.id == longestSession.id || safe.duration >= longestSession.duration
    }
    
    private var sessionMilestone: Milestone? {
        // Use stored milestone if available, otherwise compute from session duration
        return displayedMilestone ?? Milestone.milestoneForDuration(safeSession.duration)
    }
    
    /// Badge Rive (`showSessionBadge`) and milestone layout only for sessions ≥ 10 min; shorter sessions use standard duration text (`sessionComplete`).
    private var sessionMilestoneForResultDisplay: Milestone? {
        guard safeSession.duration >= 600 else { return nil }
        return sessionMilestone
    }
    
    // Check if this session was the first time achieving this specific milestone
    private var isFirstTimeAchievingThisMilestone: Bool {
        guard let milestone = sessionMilestone else { return false }
        
        // Find the next milestone to determine the upper bound for this milestone's range
        let nextMilestone = Milestone.allMilestones.first { $0.seconds > milestone.seconds }
        let upperBound = nextMilestone?.seconds ?? Int.max
        
        // Check if there are any OTHER sessions (completed before this one) that achieved this milestone
        let earlierSessionsAchievingMilestone = allSessions.filter { otherSession in
            // Skip the current session
            guard otherSession.id != session.id else { return false }
            
            // Check if this other session was completed before the current session
            guard otherSession.endTime < safeSession.endTime else { return false }
            
            // Check if this other session achieved the same milestone
            let durationSeconds = Int(otherSession.duration)
            return durationSeconds >= milestone.seconds && durationSeconds < upperBound
        }
        
        // If no earlier sessions achieved this milestone, this is the first time
        return earlierSessionsAchievingMilestone.isEmpty
    }
    
    // Check if confetti should be shown for this milestone
    private var shouldShowConfetti: Bool {
        guard let milestone = sessionMilestone else { return false }
        
        // Show confetti if:
        // 1. It's a new milestone unlock (first time achieving this specific milestone)
        // 2. OR it's a milestone of 1 hour or above (always show for hour+ milestones)
        return isFirstTimeAchievingThisMilestone || milestone.seconds >= 3600
    }
    
    private var milestoneTitle: String {
        guard sessionMilestone != nil else {
            return "Focus session\ncomplete"
        }
        
        // Check if this is the first time achieving this specific milestone
        let isFirstTime = isFirstTimeAchievingThisMilestone
        
        if isFirstTime {
            return "New milestone achieved!"
        }
        
        // For repeat achievements, cycle through celebratory messages
        // Longer sessions get more celebratory messages
        let durationInMinutes = session.duration / 60
        let celebrationMessages: [String]
        
        if durationInMinutes >= 60 {
            // Hour+ sessions - most celebratory
            celebrationMessages = [
                "You're crushing it",
                "You're unstoppable",
                "Way to focus!",
                "Phenomenal flip!",
                "Flippin' awesome!",
                "You're on fire!"
            ]
        } else if durationInMinutes >= 30 {
            // 30+ minute sessions - very celebratory
            celebrationMessages = [
                "Nice one!",
                "Way to focus!",
                "Nice flip!",
                "Great job!",
                "That's how it's done!"
            ]
        } else {
            // Shorter sessions - celebratory but simpler
            celebrationMessages = [
                "Good job!",
                "Way to go!",
                "Nice work!",
                "Keep it up!",
                "Another flip in the books!"
            ]
        }
        
        // Use session ID or timestamp to consistently pick a message for this session
        // Hash the session ID to pick a message index
        let messageIndex = abs(safeSession.id.hashValue) % celebrationMessages.count
        return celebrationMessages[messageIndex]
    }
    
    var body: some View {
        GeometryReader { geometry in
            if hideControlsForSharing {
                // For sharing: just the card, no background gradient
                let cardHeight: CGFloat = 540
                let cardWidth: CGFloat = geometry.size.width - 40 // Subtract padding (20 on each side)
                HStack {
                    Spacer()
                    ZStack {
                        Color.black.opacity(0.9)
                    }
                    .overlay {
                        completionContent
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(selectedCategory.color, lineWidth: 8) // Use strokeBorder for inner stroke
                    )
                    Spacer()
                }
            } else {
                ZStack {
                    // Metal shader gradient background with session category color
                    MetalGradientBackground(
                        page: 0, // Use page 0 but override with custom colors from category
                        customColors: MetalGradientBackground.customColorsForTheme(selectedCategory.color),
                        backgroundColor: MetalGradientBackground.darkColor(selectedCategory.color)
                    )
                    .ignoresSafeArea()
                    
                    // 20% dark overlay
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    
                    // Confetti effect for milestones (only show for new unlocks or 1hr+ milestones)
                    if shouldShowConfetti {
                        ConfettiView(
                            colors: generateConfettiColors(from: selectedCategory.color),
                            intensity: 0.8,
                            style: .large,
                            shouldStart: showConfetti
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                    
                    VStack(spacing: 0) {
                        // Flip Phone logo at the top (outside the card)
                        if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                            #if canImport(RiveRuntime)
                            RiveViewWrapperNewAPI(
                                fileName: "flipphone_logo",
                                autoPlay: true,
                                stateName: "hero",
                                animationName: nil,
                                uniqueId: "session-result-logo",
                                artboardName: nil,
                                instanceValue: 3.0,
                                artboardInputs: nil
                            )
                            .frame(height: 40)
                            .padding(.top, 20)
                            #endif
                        }
                        
                        // Flexible spacer to push card to center
                        Spacer()
                        
                        // Dark overlay card - centered horizontally and vertically
                        // Default to 540, only use shorter on smallest device sizes
                        let screenHeight = geometry.size.height
                        let cardHeight: CGFloat = {
                            // Use 383 only on very small devices (iPhone SE, etc. - screen height < 700)
                            // Otherwise default to 540
                            if screenHeight < 700 {
                                return 383
                            } else {
                                return 540
                            }
                        }()
                        
                        // Content card - make it a button only if not hiding controls
                        // Interactive version with edit button
                        Button {
                            if !wasSessionDeleted {
                                showEditDetailsSheet = true
                                AnalyticsService.shared.logButtonTap("add_details")
                            }
                        } label: {
                            ZStack {
                                Color.black.opacity(0.9)
                            }
                            .overlay {
                                completionContent
                            }
                        .frame(height: cardHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 40, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                        
                        // Flexible spacer to push buttons to bottom
                        Spacer()
                        
                        // Bottom Share / Done buttons - bottom center
                        HStack(spacing: 16) {
                            Button(action: {
                                if !wasSessionDeleted {
                                    shareSession()
                                }
                            }) {
                                Text("Share")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                selectedCategory.color,
                                                selectedCategory.color.opacity(0.7)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(24)
                                    .animation(.easeInOut(duration: 0.4), value: selectedCategory.id)
                            }
                            
                            Button(action: handleDone) {
                                Text("Done")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(white: 0.9))
                                    .cornerRadius(24)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                    }
                }
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerView(selectedCategory: $selectedCategory)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [generateShareText()])
        }
        .sheet(isPresented: Binding(
            get: { showShareableGraphic && !wasSessionDeleted },
            set: { showShareableGraphic = $0 }
        )) {
            ShareableGraphicSheetContent(
                sessionId: safeSession.id,
                sessionMilestone: sessionMilestoneForResultDisplay,
                selectedCategory: selectedCategory,
                isFirstTimeAchievingMilestone: isFirstTimeAchievingThisMilestone,
                isPersonalBest: isPersonalBest,
                modelContext: modelContext
            )
        }
        .sheet(isPresented: Binding(
            get: { showEditDetailsSheet && !wasSessionDeleted },
            set: { showEditDetailsSheet = $0 }
        )) {
            EditDetailsSheetContent(
                sessionId: safeSession.id,
                note: $note,
                selectedCategory: $selectedCategory,
                onSave: {
                    saveDetails()
                },
                onDelete: {
                    wasSessionDeleted = true
                    showEditDetailsSheet = false
                    // Show toast after a brief delay to allow sheet to dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showDeletedToast = true
                        // Auto-dismiss toast after 4 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            showDeletedToast = false
                        }
                    }
                },
                modelContext: modelContext
            )
        }
        .overlay(alignment: .top) {
            if showDeletedToast {
                deletedToastView
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDeletedToast)
                    .padding(.top, 20)
                    .zIndex(1000)
            }
        }
        .onAppear {
            // Cache session data immediately to prevent crashes if session is deleted
            if cachedSessionData == nil {
                cachedSessionData = CachedSessionData(
                    id: session.id,
                    duration: session.duration,
                    formattedDuration: CachedSessionData.formatDuration(session.duration),
                    points: session.points,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    pauseCountValue: session.pauseCountValue
                )
            }
            
            note = session.note
            selectedCategory = session.category

            // Ensure the Rive views are recreated on every open.
            milestoneResultsRiveRefreshToken = UUID()
            sessionResultsRiveRefreshToken = UUID()
            
            #if DEBUG
            let uiColor = UIColor(selectedCategory.color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            print("QA [SessionResultView.onAppear] selectedCategory id=\(selectedCategory.id) displayName=\(selectedCategory.displayName) colorRGBA=(\(r),\(g),\(b),\(a))")
            #endif
            
            // Capture milestone at this moment
            displayedMilestone = Milestone.milestoneForDuration(safeSession.duration)
            
            // Start confetti only if it should be shown (new unlock or 1hr+ milestone)
            if shouldShowConfetti {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showConfetti = true
                }
            }
            
            #if DEBUG
            if let milestone = displayedMilestone {
                print("🎯 SessionResultView.onAppear: session duration=\(session.duration)s (\(Int(session.duration/60))m), milestone=\(milestone.label), seconds=\(milestone.seconds), milestoneTime=\(milestone.milestoneTime)")
            }
            #endif
            
            if isPersonalBest {
                AnalyticsService.shared.logPersonalBestAchieved(duration: session.duration)
            }
            
            // Play end chime (only if not hiding controls for sharing)
            if !hideControlsForSharing {
                AudioService.shared.playEndChime()
            }
            
            // Increment session count for review prompt tracking (only if session is > 1 minute)
            if safeSession.duration > 60 {
                ReviewPromptService.shared.incrementSessionCount()
            }
        }
        .onDisappear {
            // Check for review prompt eligibility when session result view is dismissed
            // This triggers when user taps "Done" or swipes away
            // Delay to ensure sheet animation completes and prompt appears over main view
            if safeSession.duration > 60 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let hasCustomized = !note.isEmpty || selectedCategory != .other
                    ReviewPromptService.shared.checkAndPromptIfEligible(
                        sessionDuration: safeSession.duration,
                        isPersonalBest: isPersonalBest,
                        hasCustomizedSession: hasCustomized,
                        currentStreak: user?.currentStreak ?? 0
                    )
                }
            }
        }
    }
    
    // MARK: - Main completion content
    
    private var completionContent: some View {
        GeometryReader { cardGeometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Date of session - center aligned above title (only for milestone badge layout)
                    if sessionMilestoneForResultDisplay != nil {
                        Text(formattedSessionDate)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 32)
                    }
                    
                    // Title - dynamic based on milestone achievement status
                    Text(milestoneTitle)
                        .font(.system(size: hideControlsForSharing ? 20 : 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, sessionMilestoneForResultDisplay != nil ? 8 : 32)
                    
                    // Flexible spacer - centers duration between header and metadata
                    Spacer(minLength: 16)
                    
                    // Rive animation with session duration - centered between logo and metadata
                    // When hideControlsForSharing is true, use static SVG badge instead (ImageRenderer can't capture Rive)
                    VStack(spacing: 0) { // Changed to 0 to control spacing manually
                        if hideControlsForSharing {
                            // For shareable graphic: use PNG badge image (ImageRenderer can capture native SwiftUI Images)
                            if let milestone = sessionMilestoneForResultDisplay {
                                milestoneBadgePNGView(for: milestone, categoryColor: selectedCategory.color)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(height: 200)
                                    .padding(.horizontal, 20)
                            } else {
                                // No milestone - show duration text with background template
                                ZStack {
                                    // Background template image, colored to match category
                                    if let templateImage = loadPNGBadge(badgeName: "non-milestone-template") {
                                        Image(uiImage: templateImage.withRenderingMode(.alwaysTemplate))
                                            .resizable()
                                            .renderingMode(.template)
                                            .foregroundColor(selectedCategory.color)
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(contentMode: .fit)
                                    }
                                    
                                    // Duration text on top
                                    Text(safeSession.formattedDuration)
                                        .font(.system(size: 52, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // Normal view: use Rive animation
                            if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                                #if canImport(RiveRuntime)
                                // Use milestone animation if milestone was achieved, otherwise use regular session results
                                if sessionMilestoneForResultDisplay != nil {
                                    RiveViewWrapperNewAPI(
                                        fileName: "flipphone_logo",
                                        autoPlay: true,
                                        stateName: "milestoneResults",
                                        animationName: nil,
                                        uniqueId: "milestoneResults-\(safeSession.id)-\(Int(safeSession.duration))-\(selectedCategory.id)",
                                        textInputs: nil,  // No text inputs needed - milestone label from converter
                                        artboardName: nil,
                                        instanceValue: 4.0,  // milestoneResults uses instance 4
                                        colorInputs: [
                                            "themeColor": selectedCategory.color
                                        ],
                                        numberInputs: [
                                            // Prefer `sessionSeconds`, but also mirror legacy `totalSessionSeconds`
                                            // for .riv files that haven't been fully migrated.
                                            "sessionSeconds": safeSession.duration,
                                            "totalSessionSeconds": safeSession.duration
                                        ],
                                        artboardInputs: nil,
                                        triggerInputs: ["showSessionBadge"]
                                    )
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(393/280, contentMode: .fit)
                                    .padding(.horizontal, 20)
                                    .animation(.easeInOut(duration: 0.4), value: selectedCategory.id)
                                    .animation(.easeInOut(duration: 0.4), value: safeSession.duration)
                                    .id(milestoneResultsRiveRefreshToken) // Force RiveViewWrapper recreation on every open
                                } else {
                                    RiveViewWrapperNewAPI(
                                        fileName: "flipphone_logo",  // Same file as logo
                                        autoPlay: true,
                                        stateName: "sessionResults",  // State machine state within the artboard
                                        animationName: nil,
                                        uniqueId: "sessionResults-\(safeSession.id)",
                                        textInputs: [
                                            "sessionDuration": safeSession.formattedDuration
                                        ],
                                        artboardName: nil,
                                        instanceValue: 1.0,
                                        colorInputs: [
                                            "themeColor": selectedCategory.color
                                        ],
                                        artboardInputs: nil,
                                        triggerInputs: ["sessionComplete"]
                                    )
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(393/280, contentMode: .fit)
                                    .padding(.horizontal, 20)
                                    .animation(.easeInOut(duration: 0.4), value: selectedCategory.id)
                                }
                                #endif
                            } else {
                                // Fallback to text if Rive file not found
                                Text(safeSession.formattedDuration)
                                    .font(.system(size: 52, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Session time counter - between rive and subhead (only for milestone badge layout)
                        if sessionMilestoneForResultDisplay != nil {
                            Text(safeSession.formattedDuration)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.top, 16)
                        }
                        
                        // Show note if exists, otherwise show "total focus time"
                        Text(!note.isEmpty ? note : "total focus time")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        // Badges - only show personal best (milestone banner removed)
                        if isPersonalBest {
                            personalBestBanner
                                .padding(.top, 8)
                        }
                    }
                    
                    // Flexible spacer - pushes metadata to bottom
                    Spacer()
                    
                    // Details card: Category icon, metadata, and edit button - pinned to bottom
                    detailsCard
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .frame(height: cardGeometry.size.height)
                .clipped() // Ensure content doesn't overflow
                
                // Logo floating in bottom right corner (only when sharing)
                // Position it relative to the card edge (accounting for the VStack's 20px padding)
                if hideControlsForSharing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            // Two-layer logo: full-color base + template overlay for category color
                            if let fullColorLogo = loadPNGBadge(badgeName: "logo"),
                               let templateLogo = loadPNGBadge(badgeName: "logo-template") {
                                ZStack {
                                    // Full-color base layer
                                    Image(uiImage: fullColorLogo)
                                        .resizable()
                                        .scaledToFit()
                                    
                                    // Template overlay layer with category color
                                    Image(uiImage: templateLogo.withRenderingMode(.alwaysTemplate))
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundColor(selectedCategory.color)
                                        .scaledToFit()
                                }
                                .frame(width: 48, height: 48)
                                .padding(.trailing, 20) // This matches the VStack's horizontal padding
                                .padding(.bottom, 20)   // This matches the detailsCard's bottom padding
                            } else if let logoImage = loadLogoImage() {
                                // Fallback to single logo if two-layer version not available
                                Image(uiImage: logoImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .padding(.trailing, 20)
                                    .padding(.bottom, 20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it spans the full card
                }
            }
        }
    }
    
    // MARK: - UI Pieces
    
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
                    selectedCategory.color,
                    selectedCategory.color.opacity(0.7)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.4), value: selectedCategory.id)
    }
    
    private func milestoneBanner(milestone: Milestone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: milestone.icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("\(milestone.label) achieved +\(milestone.pointBonus) points")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    selectedCategory.color,
                    selectedCategory.color.opacity(0.7)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.4), value: selectedCategory.id)
    }
    
    private var categoryBadge: some View {
        Button {
            showCategoryPicker = true
            AnalyticsService.shared.logButtonTap("category_picker")
        } label: {
            ZStack {
                Circle()
                    .fill(selectedCategory.color)
                    .frame(width: 64, height: 64)
                
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Circle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .offset(x: 20, y: 20)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
    
    private var detailsCard: some View {
        HStack(alignment: .center, spacing: hideControlsForSharing ? 8 : 16) {
            // Category icon - prominent and visible
            ZStack {
                Circle()
                    .fill(selectedCategory.color)
                    .frame(width: 48, height: 48)
                
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Metadata section
            VStack(alignment: .leading, spacing: 1) {
                // Time range (moved above category name)
                Text(formattedTimeRange)
                    .font(.system(size: hideControlsForSharing ? 11 : 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                
                // Category name
                Text(selectedCategory.displayName)
                    .font(.system(size: hideControlsForSharing ? 14 : 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                // Duration and points
                let pauseCount = safeSession.pauseCountValue
                if pauseCount > 0 {
                    Text("\(safeSession.formattedDuration) + \(safeSession.points) pts · \(pauseCount) pause\(pauseCount == 1 ? "" : "s")")
                        .font(.system(size: hideControlsForSharing ? 11 : 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("\(safeSession.formattedDuration) + \(safeSession.points) pts")
                        .font(.system(size: hideControlsForSharing ? 11 : 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Edit button - only show if not hiding controls for sharing
            if !hideControlsForSharing {
                Button {
                    if !wasSessionDeleted {
                        showEditDetailsSheet = true
                        AnalyticsService.shared.logButtonTap("add_details")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var addDetailsButton: some View {
        Button {
            showEditDetailsSheet = true
            AnalyticsService.shared.logButtonTap("add_details")
        } label: {
            Text("add details")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Confetti Helpers
    
    private func generateConfettiColors(from categoryColor: Color) -> [Color] {
        let uiColor = UIColor(categoryColor)
        var h: CGFloat = 0, s: CGFloat = 0, l: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &l, alpha: &a)
        
        // Generate 5-6 harmonious colors based on the category color
        return [
            // Original color
            categoryColor,
            // Lighter variant
            Color(hue: h, saturation: min(1.0, s * 0.9), brightness: min(1.0, l * 1.2), opacity: a),
            // Slightly different hue (complementary-ish)
            Color(hue: fmod(h + 0.1, 1.0), saturation: s, brightness: l, opacity: a),
            // Darker variant
            Color(hue: h, saturation: min(1.0, s * 1.1), brightness: max(0.3, l * 0.7), opacity: a),
            // Another hue variation
            Color(hue: fmod(h - 0.15, 1.0), saturation: min(1.0, s * 0.8), brightness: min(1.0, l * 1.1), opacity: a),
            // Bright accent
            Color(hue: h, saturation: min(1.0, s * 0.7), brightness: min(1.0, l * 1.3), opacity: a)
        ]
    }
    
    // MARK: - Formatting helpers
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: safeSession.startTime)
    }
    
    private var formattedSessionDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let dateString = formatter.string(from: safeSession.startTime)
        
        // Add ordinal suffix (st, nd, rd, th)
        let day = Calendar.current.component(.day, from: safeSession.startTime)
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
        let start = formatter.string(from: safeSession.startTime).lowercased()
        let end = formatter.string(from: safeSession.endTime).lowercased()
        return "\(start) - \(end)"
    }
    
    // MARK: - Actions
    
    private func saveDetails() {
        // Only save if session still exists
        if !wasSessionDeleted {
            // Try to find the session by ID
            let sessionId = safeSession.id
            let descriptor = FetchDescriptor<FocusSession>()
            if let sessions = try? modelContext.fetch(descriptor),
               let session = sessions.first(where: { $0.id == sessionId }) {
                session.note = note
                session.category = selectedCategory
                try? modelContext.save()
            }
        }
    }
    
    private func handleDone() {
        // If session was deleted, don't save changes - just dismiss
        if wasSessionDeleted {
            dismiss()
            onDismiss?()
            return
        }
        
        // Only save if session still exists
        let sessionId = safeSession.id
        let descriptor = FetchDescriptor<FocusSession>()
        if let sessions = try? modelContext.fetch(descriptor),
           let session = sessions.first(where: { $0.id == sessionId }) {
            session.note = note
            session.category = selectedCategory
            try? modelContext.save()
        }
        
        // Note: Review prompt check happens in onDisappear
        // so it appears over the main view after sheet dismissal
        
        dismiss()
        onDismiss?()
    }
    
    private var deletedToastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Session Deleted")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("Tap Done to close")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.9)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
    
    private func shareSession() {
        AnalyticsService.shared.logShareSession()
        showShareableGraphic = true
    }
    
    private func generateShareText() -> String {
        var text = "Focus Session Complete!\n\n"
        text += "Duration: \(safeSession.formattedDuration)\n"
        text += "Points: +\(safeSession.points)\n"

        if !note.isEmpty {
            text += "Note: \(note)\n"
        }
        text += "\nCan you stay away from your phone longer than me? Try at FlipPhone.co"
        return text
    }
    
    // MARK: - Dynamic gradient based on category (removed - using Metal shader instead)
    
    // Removed categoryGradient - now using MetalGradientBackground in body
    
    // MARK: - Static Badge PNG for Shareable Graphic
    
    // Load and display milestone badge PNG (for ImageRenderer compatibility)
    private func milestoneBadgePNGView(for milestone: Milestone, categoryColor: Color) -> some View {
        let badgeName = "badge-\(milestone.label)"
        
        // Try loading both full-color and template layers (two-layer approach)
        if let fullColorImage = loadPNGBadge(badgeName: badgeName),
           let templateImage = loadPNGBadge(badgeName: "\(badgeName)-template") {
            // Two-layer approach: full-color base + template overlay for dynamic tinting
            return AnyView(
                ZStack {
                    // Full-color base layer
                    Image(uiImage: fullColorImage)
                        .resizable()
                        .scaledToFit()
                    
                    // Template overlay layer with category color
                    Image(uiImage: templateImage.withRenderingMode(.alwaysTemplate))
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(categoryColor)
                        .scaledToFit()
                }
            )
        }
        
        // Alternative: try single full-color image with multiply blend mode
        if let fullColorImage = loadPNGBadge(badgeName: badgeName) {
            return AnyView(
                Image(uiImage: fullColorImage)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(categoryColor)
            )
        }
        
        // Fallback: try single template image (backward compatibility)
        if let templateImage = loadPNGBadge(badgeName: badgeName) {
            return AnyView(
                Image(uiImage: templateImage.withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(categoryColor)
                    .scaledToFit()
            )
        }
        
        // Handle 24hr+ case
        let sanitizedLabel = milestone.label.replacingOccurrences(of: "+", with: "plus")
        let sanitizedBadgeName = "badge-\(sanitizedLabel)"
        
        // Try two-layer approach for sanitized name
        if let fullColorImage = loadPNGBadge(badgeName: sanitizedBadgeName),
           let templateImage = loadPNGBadge(badgeName: "\(sanitizedBadgeName)-template") {
            return AnyView(
                ZStack {
                    Image(uiImage: fullColorImage)
                        .resizable()
                        .scaledToFit()
                    
                    Image(uiImage: templateImage.withRenderingMode(.alwaysTemplate))
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(categoryColor)
                        .scaledToFit()
                }
            )
        }
        
        // Try multiply for sanitized name
        if let fullColorImage = loadPNGBadge(badgeName: sanitizedBadgeName) {
            return AnyView(
                Image(uiImage: fullColorImage)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(categoryColor)
            )
        }
        
        // Final fallback: simple icon
        return AnyView(
            Image(systemName: milestone.icon)
                .font(.system(size: 80, weight: .semibold, design: .rounded))
                .foregroundColor(categoryColor)
        )
    }
    
    private func loadPNGBadge(badgeName: String) -> UIImage? {
        // Try loading from Badges folder first
        if let url = Bundle.main.url(forResource: badgeName, withExtension: "png", subdirectory: "Badges"),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            return image
        }
        
        // Try loading from main bundle
        if let url = Bundle.main.url(forResource: badgeName, withExtension: "png"),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            return image
        }
        
        // Try loading from Assets.xcassets
        if let image = UIImage(named: badgeName) {
            return image
        }
        
        return nil
    }
    
    private func loadLogoImage() -> UIImage? {
        // Try loading logo.png from Badges folder
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "Badges"),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            return image
        }
        
        // Try loading from main bundle
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            return image
        }
        
        // Try loading from Assets.xcassets
        if let image = UIImage(named: "logo") {
            return image
        }
        
        return nil
    }
}

// Helper view for rendering SVG badge (simplified version for sharing)
struct SVGWebViewForSharing: UIViewRepresentable {
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
                html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; display: flex; align-items: center; justify-content: center; }
                svg { width: 100%; height: 100%; display: block; max-width: 100%; max-height: 100%; }
            </style>
        </head>
        <body>\(svgString)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// Share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Edit Details Sheet
struct EditDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.endTime, order: .reverse) private var allSessions: [FocusSession]
    @Binding var note: String
    @Binding var selectedCategory: SessionCategory
    let onSave: () -> Void
    let session: FocusSession?
    var onDelete: (() -> Void)? // Callback when session is deleted
    
    init(note: Binding<String>, selectedCategory: Binding<SessionCategory>, onSave: @escaping () -> Void, session: FocusSession?, onDelete: (() -> Void)? = nil) {
        self._note = note
        self._selectedCategory = selectedCategory
        self.onSave = onSave
        self.session = session
        self.onDelete = onDelete
    }
    
    @State private var tempNote: String = ""
    @State private var tempCategory: SessionCategory = .other
    @State private var showDeleteConfirmation = false
    @State private var shouldSaveOnDismiss = true
    @FocusState private var isNoteFocused: Bool
    
    // Get ordered categories based on usage
    private var orderedCategories: [SessionCategory] {
        // Count category usage (most recent first, then by frequency)
        var categoryUsage: [SessionCategory: (count: Int, mostRecent: Date)] = [:]
        
        for session in allSessions {
            let category = session.category
            if let existing = categoryUsage[category] {
                categoryUsage[category] = (
                    count: existing.count + 1,
                    mostRecent: max(existing.mostRecent, session.endTime)
                )
            } else {
                categoryUsage[category] = (count: 1, mostRecent: session.endTime)
            }
        }
        
        // Sort: first by most recent use, then by frequency
        let sorted = SessionCategory.allCases.sorted { cat1, cat2 in
            let usage1 = categoryUsage[cat1] ?? (count: 0, mostRecent: Date.distantPast)
            let usage2 = categoryUsage[cat2] ?? (count: 0, mostRecent: Date.distantPast)
            
            // If one was used recently and the other wasn't, prioritize recent
            if usage1.mostRecent > Date().addingTimeInterval(-7 * 24 * 60 * 60) && 
               usage2.mostRecent <= Date().addingTimeInterval(-7 * 24 * 60 * 60) {
                return true
            }
            if usage2.mostRecent > Date().addingTimeInterval(-7 * 24 * 60 * 60) && 
               usage1.mostRecent <= Date().addingTimeInterval(-7 * 24 * 60 * 60) {
                return false
            }
            
            // Otherwise sort by frequency, then by most recent
            if usage1.count != usage2.count {
                return usage1.count > usage2.count
            }
            return usage1.mostRecent > usage2.mostRecent
        }
        
        return sorted
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Description input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How did you spend the time?")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $tempNote)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 100)
                                    .padding(16)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(16)
                                    .focused($isNoteFocused)
                                
                                // Placeholder overlay
                                if tempNote.isEmpty {
                                    VStack {
                                        HStack {
                                            Text("Tap to add a short description…")
                                                .font(.system(size: 16, design: .rounded))
                                                .foregroundColor(.white.opacity(0.5))
                                                .padding(.leading, 20)
                                                .padding(.top, 24)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                                .onChange(of: tempNote) { oldValue, newValue in
                                    if newValue.count > 140 {
                                        tempNote = String(newValue.prefix(140))
                                    }
                                }
                            
                            // Character count
                            HStack {
                                Spacer()
                                Text("\(tempNote.count)/140")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(tempNote.count > 140 ? .red.opacity(0.8) : .white.opacity(0.5))
                            }
                        }
                        .padding(.top, 8)
                        
                        // Category selection - inline grid (ordered by usage)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Category")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                ForEach(orderedCategories) { category in
                                    categoryButton(category: category, selectedCategory: $tempCategory)
                                }
                            }
                        }
                        
                        // Delete button at bottom
                        if session != nil {
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Text("Delete Session")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 100) // Extra padding for floating button
                }
                
                // Floating action button - bottom right
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            // Save and dismiss
                            shouldSaveOnDismiss = true
                            dismiss()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                tempCategory.color,
                                                tempCategory.color.opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                                    .animation(.easeInOut(duration: 0.4), value: tempCategory.id)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(tempNote.count > 140)
                        .opacity(tempNote.count > 140 ? 0.5 : 1.0)
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Add Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        shouldSaveOnDismiss = false
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .onAppear {
                tempNote = note
                tempCategory = selectedCategory
                shouldSaveOnDismiss = true
            }
            .onDisappear {
                // Save changes when dismissed (unless Cancel was pressed)
                if shouldSaveOnDismiss && tempNote.count <= 140 {
                    note = tempNote
                    selectedCategory = tempCategory
                    
                    // Mark that user has customized session (for review prompt)
                    if !tempNote.isEmpty || tempCategory != .other {
                        ReviewPromptService.shared.markSessionCustomized()
                    }
                    
                    onSave()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss keyboard when tapping outside the TextEditor
                if isNoteFocused {
                    isNoteFocused = false
                }
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
    
    private func categoryButton(category: SessionCategory, selectedCategory: Binding<SessionCategory>) -> some View {
        Button {
            selectedCategory.wrappedValue = category
            AnalyticsService.shared.logCategorySelected(category.displayName)
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
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedCategory.wrappedValue == category ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedCategory.wrappedValue == category ? category.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func deleteSession() {
        guard let session = session else { return }
        
        // Capture session ID before deletion
        let sessionId = session.id
        let points = session.points
        let duration = session.duration
        
        // Force-load lazy attributes to avoid SwiftData crash
        _ = session.category
        _ = session.note
        
        // Get all sessions before deletion to check milestones
        let allSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let remainingSessions = allSessions.filter { $0.id != sessionId }
        
        // Get user from query
        let userQuery = FetchDescriptor<User>()
        if let user = try? modelContext.fetch(userQuery).first {
            // Update user stats
            user.totalPoints = max(0, user.totalPoints - points)
            user.totalFocusTime = max(0, user.totalFocusTime - duration)
            user.sessionsCompleted = max(0, user.sessionsCompleted - 1)
            
            // Recalculate longest session from all remaining sessions
            user.longestSession = remainingSessions.map { $0.duration }.max() ?? 0
            
            // Recalculate streaks with remaining sessions
            user.updateStats(with: session, allSessions: remainingSessions)
            
            // Check if deleted session achieved a milestone
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
        
        // Prevent saving changes on dismiss
        shouldSaveOnDismiss = false
        
        // Call onDelete callback before dismissing
        onDelete?()
        
        // Dismiss the view
        dismiss()
    }
}

// Helper views to safely fetch sessions for sheets
private struct ShareableGraphicSheetContent: View {
    let sessionId: UUID
    let sessionMilestone: Milestone?
    let selectedCategory: SessionCategory
    let isFirstTimeAchievingMilestone: Bool
    let isPersonalBest: Bool
    let modelContext: ModelContext
    
    private var session: FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        return sessions.first(where: { $0.id == sessionId })
    }
    
    var body: some View {
        if let session = session {
            ShareableGraphicView(
                session: session,
                milestone: sessionMilestone,
                categoryColor: selectedCategory.color,
                isFirstTimeAchievingMilestone: isFirstTimeAchievingMilestone,
                isPersonalBest: isPersonalBest
            )
        }
    }
}

private struct EditDetailsSheetContent: View {
    let sessionId: UUID
    @Binding var note: String
    @Binding var selectedCategory: SessionCategory
    let onSave: () -> Void
    let onDelete: () -> Void
    let modelContext: ModelContext
    
    private var session: FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        return sessions.first(where: { $0.id == sessionId })
    }
    
    var body: some View {
        if let session = session {
            EditDetailsSheet(
                note: $note,
                selectedCategory: $selectedCategory,
                onSave: onSave,
                session: session,
                onDelete: onDelete
            )
        }
    }
}
