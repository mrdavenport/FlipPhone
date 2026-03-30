import SwiftUI
import SwiftData
import Charts
import UIKit

#if canImport(RiveRuntime)
import RiveRuntime
#endif

private enum Timeframe: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case month
    case year
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .today: return "D"
        case .thisWeek: return "W"
        case .month: return "M"
        case .year: return "Y"
        }
    }
}

#if DEBUG
/// Set `sendLastSessionDurationWhenAnimating` to `true` to A/B-test hero `sessionSeconds` during post-session animation; default keeps hero `sessionSeconds` at 0.
private enum HeroRiveSessionSecondsAB {
    static var sendLastSessionDurationWhenAnimating: Bool = false
}
#endif

/// Spacing between hero Rive `showCumulativeBadge` / first layout and the start of `displayedTotalSeconds` + progress-bar count-up (bottom sheet mirrors that value).
private enum PostSessionPresentationTiming {
    static let countUpLeadAfterBadgeTrigger: TimeInterval = 0.28
}

struct FocusTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FocusSession.endTime, order: .reverse) private var sessions: [FocusSession]
    @Query private var users: [User]
    
    @Namespace private var badgeNamespace

    @StateObject private var orientationManager = OrientationManager()
    @State private var selectedTimeframe: Timeframe = .today
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var activeSession: FocusSession?
    @State private var selectedSessionForDetail: FocusSession?
    @State private var isBottomSheetExpanded = false // Starts collapsed
    @State private var chartEmptyStateOpacity: Double = 0.3
    @State private var showStreakStats = false
    @State private var showMilestones = false
    @State private var showSettings = false
    @State private var showFullCalendar = false
    @State private var selectedCategoryFilter: SessionCategory? = nil // nil = "All"
    @State private var sessionsDisplayLimit: Int = 10 // Initial number of sessions to display
    @State private var shouldScrollToSessions = false
    @State private var hasCheckedRecoveredSession = false
    @State private var showAddSession = false
    @State private var showFAB = false // Hidden by default, toggled by long press
    @State private var heroRiveLoaded = false // Lazy load heavy Rive file
    @State private var lastDisplayedDay: Date? = nil // Track day for star reset
    @State private var showHowToStart = false
    @AppStorage("hasSeenHowToStart") private var hasSeenHowToStart = false
    @State private var progressBarDisplayValue: Double = 0
    @State private var justCompletedSession: FocusSession?
    @State private var displayedTotalSeconds: Double = 0
    @State private var displayedDailyMilestone: Milestone? = nil
    @State private var isAnimatingPostSession: Bool = false
    /// During post-session animation, one-shot triggers for the single hero Rive instance (nil = do not fire on number updates).
    @State private var heroBadgeBurstTriggers: [String]? = nil
    /// Bumped when the hero surface is shown again so `showCumulativeBadge` refires even if Rive inputs are unchanged.
    @State private var heroCumulativeBadgeTriggerNonce: Int = 0
    /// When true, hero badge number inputs use from→to tier bounds for one frame (paired with `levelUp`).
    @State private var heroBadgeUseLevelUpNumbers: Bool = false
    /// Outgoing tier for a level-up frame (set before `displayedDailyMilestone` advances).
    @State private var heroLevelUpFromMilestone: Milestone? = nil
    // Tunable via the debug admin panel; persist through the session for tweaking
    @State private var animStepBaseDuration: Double = 2.1
    @State private var animStepPauseDuration: Double = 0
    @State private var showDebugAdmin = false
    // When true, the DEBUG tier animation keeps the simulated badge / cumulativeSeconds on-screen.
    // We only reset back to the live state on a hero long-press (not automatically at the end of the sequence).
    @State private var debugLevelUpSimulationActive: Bool = false
    /// Cumulative seconds already "locked in" at each post-session tier completion. Do **not** use
    /// `displayedDailyMilestone?.seconds` as a floor — it can match `todayDailyMilestone` (final tier) and pin the hero badge to e.g. 7hr for the whole sequence.
    @State private var heroPostSessionCumulativeFloor: Double = 0
    /// Prior cumulative seconds captured in `completeSession` before the new session is inserted. On dismiss, step building uses this so it matches the frozen hero state (`todayTotalTime - session.duration` can drift from rounding or @Query timing).
    @State private var postSessionFrozenPriorTotal: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let screenHeight = proxy.size.height
            
            mainContentView(topInset: topInset, screenHeight: screenHeight, proxy: proxy)
        }
        .ignoresSafeArea()
        .sheet(item: $selectedSessionForDetail, onDismiss: {
            collapseBottomSheetForHomeReturn()
        }) { session in
            SessionResultView(session: session, user: currentUser) {
                selectedSessionForDetail = nil
            }
        }
        .sheet(isPresented: $showStreakStats) {
            StreakStatsView(user: currentUser, sessions: sessions)
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showMilestones) {
            NavigationView {
                MilestonesView(user: currentUser, sessions: sessions)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showAddSession) {
            AddSessionView { session in
                saveManualSession(session)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showFullCalendar) {
            FullCalendarView(sessions: sessions, user: currentUser)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showHowToStart, onDismiss: {
            hasSeenHowToStart = true
        }) {
            HowToStartView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.secondarySystemBackground))
        }
        #if DEBUG
        .sheet(isPresented: $showDebugAdmin) {
            DebugAdminView(
                stepDuration: $animStepBaseDuration,
                pauseDuration: $animStepPauseDuration,
                sendHeroSessionSecondsWhenAnimating: Binding(
                    get: { HeroRiveSessionSecondsAB.sendLastSessionDurationWhenAnimating },
                    set: { HeroRiveSessionSecondsAB.sendLastSessionDurationWhenAnimating = $0 }
                )
            ) { testSeconds, fromZeroToday in
                let priorTime = fromZeroToday ? 0 : todayTotalTime
                let finalTime = fromZeroToday ? testSeconds : priorTime + testSeconds
                // Set animation state before clearing the debug sheet so `heroSurfaceCoverPresented`
                // onChange cannot run `bumpHeroCumulativeBadgeTriggerIfIdle()` while still idle — that
                // would replace nil `displayedDailyMilestone` with `todayDailyMilestone` and skip the pre-5m flipphone_logo branch.
                isAnimatingPostSession   = true
                debugLevelUpSimulationActive = true
                displayedDailyMilestone = Milestone.dayMilestoneForTotalTime(priorTime)
                displayedTotalSeconds = priorTime
                heroPostSessionCumulativeFloor = priorTime
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                if fromZeroToday && priorTime == 0 {
                    heroBadgeBurstTriggers = ["showCumulativeBadge"]
                    heroCumulativeBadgeTriggerNonce += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        heroBadgeBurstTriggers = nil
                    }
                } else {
                    heroBadgeBurstTriggers = nil
                }
                let steps = buildMilestoneSteps(priorTime: priorTime, finalTime: finalTime)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    isBottomSheetExpanded = false
                }
                showDebugAdmin = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    runMilestoneAnimation(steps: steps, index: 0)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        #endif
        .onAppear {
            AnalyticsService.shared.logScreenView("FocusTracking")
            // Load hero Rive immediately (no delay)
            heroRiveLoaded = true
            // Check for day change to reset stars
            checkForDayChange()
            // Sync all display state instantly on first appear (no animation)
            progressBarDisplayValue = dayProgressToNextMilestone
            displayedTotalSeconds = totalTimeInSeconds
            displayedDailyMilestone = todayDailyMilestone
            heroPostSessionCumulativeFloor = 0
            // Auto-present how-to sheet for first-time users
            if !hasSeenHowToStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showHowToStart = true
                }
            }
        }
        .onAppear {
            orientationManager.startMonitoring()
            ensureUserExists()
            // Ensure idle timer is enabled so screen can sleep
            UIApplication.shared.isIdleTimerDisabled = false
            
            // Check for recovered session on app launch
            if !hasCheckedRecoveredSession {
                checkForRecoveredSession()
                hasCheckedRecoveredSession = true
            }
        }
        .onChange(of: sessions.count) { oldCount, newCount in
            // When sessions change, check for day change
            checkForDayChange()
        }
        .onChange(of: totalTimeInSeconds) { _, newValue in
            if !isAnimatingPostSession {
                displayedTotalSeconds = newValue
            }
        }
        .onChange(of: selectedTimeframe) { _, _ in
            if !isAnimatingPostSession {
                displayedTotalSeconds = totalTimeInSeconds
            }
        }
        .onChange(of: todayDailyMilestone?.id) { _, _ in
            if !isAnimatingPostSession {
                displayedDailyMilestone = todayDailyMilestone
            }
        }
        .onDisappear {
            orientationManager.stopMonitoring()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
            if newPhase == .active, !orientationManager.isFaceDown {
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        .onChange(of: orientationManager.isFaceDown) { oldValue, newValue in
            if oldValue && !newValue {
                // Phone flipped back up - handle session end
                guard let startTime = orientationManager.sessionStartTime else {
                    // No active session, just reset
                    orientationManager.resetSession()
                    return
                }
                
                // Calculate duration using sessionDuration which accounts for paused time
                let duration = orientationManager.sessionDuration
                
                // IMPORTANT: Stop timer immediately to prevent it from continuing
                orientationManager.invalidateTimer()
                
                // End the session (this will trigger haptic and clear sessionStartTime)
                orientationManager.endSession()
                
                // Complete session if duration is at least 5 seconds
                if duration >= 5 {
                    completeSession(startTime: startTime, duration: duration)
                } else {
                    // Session canceled (picked up before 5 seconds) - play cancel sound
                    AudioService.shared.playCancelChime()
                    orientationManager.resetSession()
                }
            }
        }
        .sheet(item: $activeSession, onDismiss: {
            collapseBottomSheetForHomeReturn()

            let frozenPrior = postSessionFrozenPriorTotal
            postSessionFrozenPriorTotal = nil

            if let completedSession = justCompletedSession {
                let priorTime = frozenPrior ?? max(0, todayTotalTime - completedSession.duration)
                let finalTime = todayTotalTime
                let steps = buildMilestoneSteps(priorTime: priorTime, finalTime: finalTime)
                // Re-sync to pre-session tier (not `todayDailyMilestone`, which is already the final tier after save).
                displayedDailyMilestone = Milestone.dayMilestoneForTotalTime(priorTime)
                heroPostSessionCumulativeFloor = priorTime
                justCompletedSession = nil

                // Brief pause so the sheet dismiss animation clears before the sequence begins
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    runMilestoneAnimation(steps: steps, index: 0)
                }
            }
        }) { session in
            SessionResultView(session: session, user: currentUser) {
                justCompletedSession = session
                activeSession = nil
            }
        }
    }
    
    @ViewBuilder
    private func mainContentView(topInset: CGFloat, screenHeight: CGFloat, proxy: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            // Metal shader gradient background for session start screen - dark gray regardless of theme
            if !orientationManager.isFaceDown {
                MetalGradientBackground(
                    page: 0, // Use page 0 (red/orange) but we'll override with custom dark gray colors
                    customColors: [
                        Color(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0), // Dark gray base #1E1E1E
                        Color(red: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2A/255.0), // Slightly lighter #2A2A2A
                        Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0), // Darker #1A1A1A
                        Color(red: 0x15/255.0, green: 0x15/255.0, blue: 0x15/255.0), // Darkest #151515
                        Color(red: 0x25/255.0, green: 0x25/255.0, blue: 0x25/255.0)  // Medium dark #252525
                    ]
                )
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // Show active session view when face down
            if orientationManager.isFaceDown {
                ActiveSessionView()
                    .environmentObject(orientationManager)
                    .transition(.opacity)
                    .zIndex(10)
                    .id("activeSession")
                    .onAppear {
                        // Ensure idle timer is enabled so phone can sleep after 5 seconds
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
            } else {
                homeContentView(screenHeight: screenHeight, proxy: proxy, topInset: topInset)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    
    @ViewBuilder
    private func homeContentView(screenHeight: CGFloat, proxy: GeometryProxy, topInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            heroAndSubheaderView

            // Badge positioned at hero center, outside the blur container so it
            // can animate cleanly via matchedGeometryEffect to the toolbar.
            heroBadgeLayer

            // Bottom sheet with data
            BottomSheetView(
                isExpanded: $isBottomSheetExpanded,
                screenHeight: screenHeight
            ) {
                bottomSheetContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .ignoresSafeArea(edges: .bottom)

        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .onAppear {
            bumpHeroCumulativeBadgeTriggerIfIdle()
        }
        .onChange(of: orientationManager.isFaceDown) { wasFaceDown, isFaceDown in
            if wasFaceDown && !isFaceDown {
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        .onChange(of: heroSurfaceCoverPresented) { wasCovered, isCovered in
            if wasCovered && !isCovered {
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        .onChange(of: isAnimatingPostSession) { wasAnimating, isAnimating in
            if wasAnimating && !isAnimating {
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        .onChange(of: isBottomSheetExpanded) { wasExpanded, isExpanded in
            if wasExpanded && !isExpanded {
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        
        toolbar(topInset: topInset)
            .zIndex(100) // Ensure toolbar is on top
        
        if showToast, let toastMessage {
            ToastView(message: toastMessage)
                .padding(.top, topInset + 80)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    
    private var heroAndSubheaderView: some View {
        VStack(spacing: 0) {
            // Spacer to position hero 148px from top
            Spacer()
                .frame(height: 148)

            // Transparent placeholder — actual badge lives in heroBadgeLayer (outside blur)
            Color.clear
                .frame(height: 200)

            // Spacing between hero and subheader
            Spacer()
                .frame(height: 146.62)

            // Subheader text
            Text(orientationManager.isFaceDown ? "Focus session in progress…" : "flip your phone to start a focus session…")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            
            // Spacer to push content up (remaining space before bottom sheet)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blur(radius: isBottomSheetExpanded ? 10 : 0)
        .opacity(isBottomSheetExpanded ? 0.3 : 1.0)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if isBottomSheetExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isBottomSheetExpanded = false
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            #if DEBUG
            // If a DEBUG tier animation simulation is active, this long-press is the "acknowledge/reset" moment.
            if debugLevelUpSimulationActive {
                debugLevelUpSimulationActive = false
                isAnimatingPostSession = false
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                displayedDailyMilestone = todayDailyMilestone
                displayedTotalSeconds = totalTimeInSeconds
            }
            showDebugAdmin = true
            #endif
        }
        .overlay(
            // Dark overlay when settings or streak stats sheets are active
            Group {
                if showStreakStats || showMilestones || showSettings {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        )
    }
    
    // MARK: - Hero Badge Layer (outside blur container for clean matchedGeometryEffect)

    private var heroBadgeLayer: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 148)
            heroBadgeContent
                .frame(maxWidth: 300)
                .aspectRatio(393.0 / 280.0, contentMode: .fit)
                // Opacity animates independently via the explicit spring below.
                // matchedGeometryEffect sits outside that scope so its position
                // transition is driven solely by the withAnimation context from
                // BottomSheetView — preventing a double-spring y-jump on collapse.
                .opacity(isBottomSheetExpanded ? 0 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isBottomSheetExpanded)
                .matchedGeometryEffect(
                    id: "dailyBadge",
                    in: badgeNamespace,
                    isSource: !isBottomSheetExpanded
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isBottomSheetExpanded else { return }
                    #if DEBUG
                    // QA sequence: tap at end of sequence ends the preview and returns to actual values
                    if debugLevelUpSimulationActive {
                        debugLevelUpSimulationActive = false
                        isAnimatingPostSession = false
                        heroBadgeBurstTriggers = nil
                        heroBadgeUseLevelUpNumbers = false
                        heroLevelUpFromMilestone = nil
                        heroPostSessionCumulativeFloor = 0
                        displayedDailyMilestone = todayDailyMilestone
                        displayedTotalSeconds = totalTimeInSeconds
                        return
                    }
                    #endif
                    showFullCalendar = true
                    AnalyticsService.shared.logButtonTap("hero_calendar")
                }
            heroBadgeProgressIndicator
                .padding(.top, 12)
                .opacity(isBottomSheetExpanded || (displayedNextMilestone == nil && !isAnimatingPostSession) ? 0 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isBottomSheetExpanded)
                .allowsHitTesting(false)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Spacers have no contentShape so they pass taps through to heroAndSubheaderView.
        // Only the badge content area above captures taps.
    }

    @ViewBuilder
    private var heroBadgeContent: some View {
        #if canImport(RiveRuntime)
        heroDailyBadgeRiveView
        #else
        heroBadgeFallback
        #endif
    }

    /// Single hero-daily Rive instance (stable identity) so post-session level-ups do not reload the file per tier cut.
    @ViewBuilder
    private var heroDailyBadgeRiveView: some View {
        #if canImport(RiveRuntime)
        if (displayedDailyMilestone != nil || isAnimatingPostSession),
           Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil && heroRiveLoaded {
            RiveViewWrapperNewAPI(
                fileName: "flipphone_logo",
                autoPlay: true,
                stateName: "milestoneResults",
                animationName: nil,
                uniqueId: "hero-daily",
                artboardName: nil,
                instanceValue: 4.0,
                colorInputs: [
                    "themeColor": todayMilestoneColor
                ],
                numberInputs: heroDailyBadgeNumberInputs(),
                artboardInputs: nil,
                triggerInputs: heroBadgeTriggerInputsForRive,
                triggerReloadNonce: heroCumulativeBadgeTriggerNonce
            )
            .id("hero-daily")
        } else if Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv") != nil && heroRiveLoaded {
            RiveViewWrapperNewAPI(
                fileName: "flipphone_hero",
                autoPlay: true,
                stateName: "hero-stars",
                animationName: nil,
                uniqueId: "hero-badge",
                artboardName: "hero animation",
                instanceValue: 0.0,
                colorInputs: [
                    "themeColor": ThemeManager.defaultColor,
                    "badgeColor": todayMilestoneColor
                ],
                numberInputs: buildStarNumberInputs(),
                artboardInputs: nil
            )
        } else {
            heroBadgeFallback
        }
        #else
        heroBadgeFallback
        #endif
    }

    @ViewBuilder
    private var heroBadgeFallback: some View {
        if let image = UIImage(named: "AppLogo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text("FLIP\nPHONE")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    /// Subtle progress bar with tier start/end labels above each end
    private var heroBadgeProgressIndicator: some View {
        VStack(spacing: 4) {
            // Tier labels above bar ends — left is hidden on the first step (no milestone yet)
            HStack {
                if let left = currentMilestoneShortLabel {
                    Text(left)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                if let right = nextMilestoneShortLabel {
                    Text(right)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(width: 180)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 180, height: 3)
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: max(6, 180 * progressBarDisplayValue), height: 3)
            }
        }
    }

    /// Short display label for the current milestone threshold (nil when no milestone yet).
    /// Tracks `displayedDailyMilestone` so labels update in step with the animation sequence.
    private var currentMilestoneShortLabel: String? {
        guard let m = displayedDailyMilestone else { return nil }
        return milestoneShortLabel(m)
    }

    /// Short display label for the next milestone threshold.
    /// Tracks `displayedNextMilestone` so labels update in step with the animation sequence.
    private var nextMilestoneShortLabel: String? {
        guard let m = displayedNextMilestone else { return nil }
        return milestoneShortLabel(m)
    }

    private func milestoneShortLabel(_ milestone: Milestone) -> String {
        milestone.metaTag == "hr"
            ? "\(milestone.milestoneTime)h"
            : "\(milestone.milestoneTime)m"
    }

    /// Next daily milestone threshold strictly after `milestone` (for per-badge tier span on hero / level-up stack).
    private func nextMilestoneAfter(_ milestone: Milestone) -> Milestone? {
        Milestone.nextInSequence(after: milestone)
    }

    /// `sessionSeconds` on hero: 0 in Release; DEBUG can enable last-session duration while post-session animation runs (see `HeroRiveSessionSecondsAB`).
    private func heroSessionSecondsForRive() -> Double {
        #if DEBUG
        if HeroRiveSessionSecondsAB.sendLastSessionDurationWhenAnimating,
           isAnimatingPostSession,
           let session = justCompletedSession {
            return session.duration
        }
        #endif
        return 0
    }

    /// Hero Rive numbers: cumulative + tier bounds for **this** `milestone` + optional session length for testing.
    private func heroNumberInputs(for milestone: Milestone) -> [String: Double] {
        let cumulative: Double
        if isAnimatingPostSession {
            cumulative = max(displayedTotalSeconds, heroPostSessionCumulativeFloor)
        } else {
            cumulative = todayTotalTime
        }
        let fromTier = Double(milestone.seconds)
        let toTier = Double(nextMilestoneAfter(milestone)?.seconds ?? milestone.seconds)
        return [
            "cumulativeSeconds": cumulative,
            "cumulativeFromTierSeconds": fromTier,
            "cumulativeToTierSeconds": toTier,
            "sessionSeconds": heroSessionSecondsForRive()
        ]
    }

    /// Tier-cut frame: `from` and `to` are daily milestone thresholds (seconds). Uses canonical next-in-sequence
    /// so badges never jump out of order (e.g. 13h → 15h → 14h).
    ///
    /// **Do not** pass `displayedTotalSeconds` as `cumulativeSeconds` here — it still tracks the bar animation
    /// and can sit *below* the outgoing tier (e.g. 6h total while FT/TT are 7h/8h), so Rive shows CS out of
    /// sync with FT/TT. We send tier-boundary seconds only; Rive should bind the outgoing label to
    /// `cumulativeFromTierSeconds`, incoming to `cumulativeToTierSeconds`, and use `cumulativeSeconds`
    /// as the post-crossing total anchor (matches TT / new tier lower bound).
    private func heroNumberInputsForLevelUp(from fromMilestone: Milestone, to toMilestoneFromStep: Milestone) -> [String: Double] {
        let toMilestone = Milestone.nextInSequence(after: fromMilestone) ?? toMilestoneFromStep
        let fromS = Double(fromMilestone.seconds)
        let toS = Double(toMilestone.seconds)
        return [
            "cumulativeSeconds": toS,
            "cumulativeFromTierSeconds": fromS,
            "cumulativeToTierSeconds": toS,
            "sessionSeconds": heroSessionSecondsForRive()
        ]
    }

    /// Before the first daily milestone (0 → first threshold): tier span 0 → first milestone seconds.
    private func heroNumberInputsPreFirstDailyMilestone() -> [String: Double] {
        let firstTh = Double(Milestone.allMilestones.first?.seconds ?? 0)
        let cumulative = max(displayedTotalSeconds, heroPostSessionCumulativeFloor)
        return [
            "cumulativeSeconds": cumulative,
            "cumulativeFromTierSeconds": 0,
            "cumulativeToTierSeconds": firstTh,
            "sessionSeconds": heroSessionSecondsForRive()
        ]
    }

    /// Triggers for the single hero-daily Rive: idle always shows cumulative; during post-session, only when `heroBadgeBurstTriggers` is set (avoids firing on every `cumulativeSeconds` keyframe).
    private var heroBadgeTriggerInputsForRive: [String]? {
        if isAnimatingPostSession {
            return heroBadgeBurstTriggers
        }
        return ["showCumulativeBadge"]
    }

    private func heroDailyBadgeNumberInputs() -> [String: Double] {
        if heroBadgeUseLevelUpNumbers, let from = heroLevelUpFromMilestone, let to = displayedDailyMilestone {
            return heroNumberInputsForLevelUp(from: from, to: to)
        }
        if let m = displayedDailyMilestone {
            return heroNumberInputs(for: m)
        }
        return heroNumberInputsPreFirstDailyMilestone()
    }

    @ViewBuilder
    private func heroLogoView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Priority: Rive -> Video -> Static Image -> Fallback
            Group {
                #if canImport(RiveRuntime)
                // Lazy-load the heavy Rive file to avoid blocking UI
                if Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv") != nil && heroRiveLoaded {
                    RiveViewWrapperNewAPI(
                        fileName: "flipphone_hero",
                        autoPlay: true,
                        stateName: "hero-stars",  // State for hero/home screen with shooting stars
                        animationName: nil,
                        uniqueId: "hero-view",
                        artboardName: "hero animation",  // Artboard with ViewModel and data bindings
                        instanceValue: 0.0,
                        colorInputs: [
                            "themeColor": ThemeManager.defaultColor,
                            "badgeColor": todayMilestoneColor
                        ],
                        numberInputs: buildStarNumberInputs(),
                        artboardInputs: nil
                    )
                    .frame(width: min(geometry.size.width, 500) * 0.8, height: min(geometry.size.width, 500) * 0.8)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
                } else if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                    VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                        .frame(width: 180, height: 180)
                } else if UIImage(named: "AppLogo") != nil {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(orientationManager.isFaceDown ? 0 : 30))
                        .scaleEffect(orientationManager.isFaceDown ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: orientationManager.isFaceDown)
                } else {
                    // Fallback: simple text logo
                    Text("FLIP\nPHONE")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 180, height: 180)
                }
                #else
                if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                    VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                        .frame(width: 180, height: 180)
                } else if UIImage(named: "AppLogo") != nil {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(orientationManager.isFaceDown ? 0 : 30))
                        .scaleEffect(orientationManager.isFaceDown ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: orientationManager.isFaceDown)
                } else {
                    // Fallback: simple text logo
                    Text("FLIP\nPHONE")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 180, height: 180)
                }
                #endif
            }
        }
    }
    
    private var bottomSheetContent: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            bottomSheetHeader
            
            // Tabs (always visible)
            timeframeSelector
                .padding(.top, 16) // Reduced spacing to fit in collapsed state
                .padding(.bottom, 20) // Reduced from 24 to fit
            
            // Expanded content (preloaded but hidden when collapsed)
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            weeklyActivityChart
                            
                            categoryFilterSection
                            
                            statCardsGrid
                            
                            topSessionsSection
                            
                            sessionsSection
                                .id("sessionsSection")
                        }
                        .padding(.horizontal, 0) // Chart has its own padding
                        .padding(.top, 24)
                        .padding(.bottom, 100) // Extra padding for FAB
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: isBottomSheetExpanded ? nil : 0)
                    .opacity(isBottomSheetExpanded ? 1 : 0)
                    .contentShape(Rectangle()) // Make entire scroll view tappable
                    .onLongPressGesture(minimumDuration: 0.5) {
                        // Toggle FAB visibility on long press
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showFAB.toggle()
                        }
                        AnalyticsService.shared.logButtonTap("toggle_fab")
                    }
                    .onChange(of: isBottomSheetExpanded) { oldValue, newValue in
                        // When sheet expands and we need to scroll, do it here
                        if newValue && shouldScrollToSessions {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    proxy.scrollTo("sessionsSection", anchor: .top)
                                }
                                shouldScrollToSessions = false
                            }
                        }
                    }
                    .onChange(of: shouldScrollToSessions) { oldValue, newValue in
                        // Scroll when flag is set and sheet is already expanded
                        if newValue && isBottomSheetExpanded {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    proxy.scrollTo("sessionsSection", anchor: .top)
                                }
                                shouldScrollToSessions = false
                            }
                        }
                    }
                }
                
                // FAB button for adding sessions (hidden by default, revealed by long press)
                if isBottomSheetExpanded && showFAB {
                    Button {
                        showAddSession = true
                        AnalyticsService.shared.logButtonTap("add_session")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showFAB)
                }
            }
        }
        .padding(.horizontal, 20) // Add back 20px padding on both sides
    }
    
    private var weeklyActivityChart: some View {
        VStack(alignment: .leading, spacing: 20) {
            let chartData = getChartData()
            let allSessionsChartData = getChartData(includeAllSessions: true)
            let hasData = chartData.contains { $0.minutes > 0 }
            let keyLabels = getKeyLabelsForTimeframe(selectedTimeframe)
            
            // Calculate average and max value (excluding zeros)
            // Use all sessions for max to ensure proper scaling when showing faded bars
            let maxMinutes = max(
                chartData.map { $0.minutes }.max() ?? 0,
                allSessionsChartData.map { $0.minutes }.max() ?? 0
            )
            
            let averageMinutes: Double = {
                let nonZeroData = chartData.filter { $0.minutes > 0 }
                guard !nonZeroData.isEmpty else { return 0 }
                let total = nonZeroData.reduce(0.0) { $0 + $1.minutes }
                return total / Double(nonZeroData.count)
            }()
            
            // Get category color for selected filter
            let categoryColor = selectedCategoryFilter?.color ?? ThemeManager.defaultColor
            
            ZStack {
                if hasData {
                    Chart {
                        // Show all sessions (faded) when a category is selected - render first (bottom layer, static)
                        if selectedCategoryFilter != nil {
                            ForEach(allSessionsChartData, id: \.id) { data in
                                BarMark(
                                    x: .value("Period", data.label),
                                    y: .value("Minutes", data.minutes)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            ThemeManager.defaultColor.opacity(0.2),
                                            ThemeManager.defaultColor.opacity(0.1)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .cornerRadius(8)
                                .position(by: .value("Series", "All"))
                            }
                        }
                        
                        // Show filtered or all sessions (full color) - render second (top layer)
                        ForEach(chartData, id: \.id) { data in
                            BarMark(
                                x: .value("Period", data.label),
                                y: .value("Minutes", data.minutes)
                            )
                            .foregroundStyle(
                                selectedCategoryFilter != nil
                                    ? LinearGradient(
                                        colors: [
                                            categoryColor,
                                            categoryColor.opacity(0.7)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    : LinearGradient(
                                        colors: [
                                            ThemeManager.defaultColor,
                                            ThemeManager.defaultColor.opacity(0.7)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                            )
                            .cornerRadius(8)
                            .position(by: .value("Series", selectedCategoryFilter != nil ? "Selected" : "All"))
                        }
                        
                        // Average line (only show if different from max)
                        if averageMinutes > 0 && abs(averageMinutes - maxMinutes) > 0.01 {
                            RuleMark(y: .value("Average", averageMinutes))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Avg: \(formatMinutesWithDays(averageMinutes))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                        }
                        
                        // Top value line with label
                        if maxMinutes > 0 {
                            RuleMark(y: .value("Max", maxMinutes))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, alignment: .leading) {
                                    Text(formatMinutesWithDays(maxMinutes))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                        }
                        
                        // X-axis line
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    .chartYScale(domain: 0...(maxMinutes > 0 ? maxMinutes : 1))
                    .chartYAxis(.hidden) // Hide Y-axis completely to remove padding
                    .chartPlotStyle { plotArea in
                        plotArea
                            .padding(.leading, 0) // Remove left padding reserved for Y-axis
                            .padding(.trailing, 0) // Ensure no trailing padding
                    }
                    .frame(maxWidth: .infinity) // Ensure chart fills available width
                    .padding(.horizontal, 4) // Add small padding to prevent edge clipping
                    .chartXAxis {
                        if selectedTimeframe == .today {
                            // For today view, show labels every 6 hours (0, 6, 12, 18)
                            AxisMarks { value in
                                if let label = value.as(String.self) {
                                    // Find the index of this label in the chart data
                                    if let dataIndex = chartData.firstIndex(where: { $0.label == label }) {
                                        // Only show labels at hours 0, 6, 12, 18 (midnight, 6am, noon, 6pm)
                                        if [0, 6, 12, 18].contains(dataIndex) {
                                            AxisValueLabel {
                                                Text(label)
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .fixedSize(horizontal: true, vertical: false)
                                            }
                                        } else {
                                            AxisValueLabel()
                                                .foregroundStyle(.clear)
                                        }
                                    } else {
                                        AxisValueLabel()
                                            .foregroundStyle(.clear)
                                    }
                                } else {
                                    AxisValueLabel()
                                        .foregroundStyle(.clear)
                                }
                            }
                        } else if selectedTimeframe == .month {
                            // For month view, show labels every 5 days
                            AxisMarks { value in
                                if let label = value.as(String.self) {
                                    // Find the index of this label in the chart data
                                    if let dataIndex = chartData.firstIndex(where: { $0.label == label }) {
                                        // Only show labels every 5 days (0, 5, 10, 15, 20, 25, 29)
                                        if dataIndex % 5 == 0 || dataIndex == chartData.count - 1 {
                                            AxisValueLabel {
                                                Text(label)
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .fixedSize(horizontal: true, vertical: false)
                                            }
                                        } else {
                                            AxisValueLabel()
                                                .foregroundStyle(.clear)
                                        }
                                    } else {
                                        AxisValueLabel()
                                            .foregroundStyle(.clear)
                                    }
                                } else {
                                    AxisValueLabel()
                                        .foregroundStyle(.clear)
                                }
                            }
                        } else {
                            // For other timeframes, use default
                            AxisMarks { value in
                                AxisValueLabel()
                                    .foregroundStyle(.white.opacity(0.5))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                        }
                    }
                } else {
                    // Empty state
                    Text("flip your phone to start a focus session…")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .opacity(chartEmptyStateOpacity)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: chartEmptyStateOpacity
                        )
                        .onAppear {
                            // Start pulsing animation
                            chartEmptyStateOpacity = 0.5
                        }
                        .onDisappear {
                            // Reset when view disappears
                            chartEmptyStateOpacity = 0.3
                        }
                }
            }
            .frame(height: 200)
            .padding(.top, 20) // Add top padding to prevent label clipping
        }
    }
    
    private var categoryFilterSection: some View {
        // Get sessions for the current timeframe
        let timeframeSessions = getSessionsForTimeframe(selectedTimeframe)
        
        // Calculate category usage for ordering (based on current timeframe)
        let categoryUsage: [SessionCategory: Double] = {
            var usage: [SessionCategory: Double] = [:]
            for category in SessionCategory.allCases {
                let categorySessions = timeframeSessions.filter { $0.category == category }
                let totalDuration = categorySessions.reduce(0.0) { $0 + $1.duration }
                usage[category] = totalDuration
            }
            return usage
        }()
        
        // Sort categories by usage (most used first)
        let sortedCategories = SessionCategory.allCases.sorted { category1, category2 in
            let usage1 = categoryUsage[category1] ?? 0
            let usage2 = categoryUsage[category2] ?? 0
            return usage1 > usage2
        }
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" button
                Button {
                    withAnimation {
                        selectedCategoryFilter = nil
                        // Reset display limit when changing category filter
                        sessionsDisplayLimit = 10
                    }
                    AnalyticsService.shared.logButtonTap("category_filter_all")
                } label: {
                    Text("All")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(selectedCategoryFilter == nil ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedCategoryFilter == nil ? Color.white : Color.white.opacity(0.1))
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                
                // Category buttons (ordered by usage)
                ForEach(sortedCategories) { category in
                    let hasActivity = (categoryUsage[category] ?? 0) > 0
                    
                    Button {
                        withAnimation {
                            selectedCategoryFilter = category
                            // Reset display limit when changing category filter
                            sessionsDisplayLimit = 10
                        }
                        AnalyticsService.shared.logCategorySelected(category.displayName)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(selectedCategoryFilter == category ? category.color : Color.white.opacity(0.1))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: category.icon)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .opacity(hasActivity ? 1.0 : 0.3)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasActivity)
                }
            }
            .padding(.horizontal, 0)
        }
    }
    
    private var chartTitle: String {
        switch selectedTimeframe {
        case .today: return "Today's Activity"
        case .thisWeek: return "Weekly Activity"
        case .month: return "Monthly Activity"
        case .year: return "Yearly Activity"
        }
    }
    
    private func shouldShowXAxisLabel(value: AxisValue, in chartData: [ActivityData]) -> Bool {
        // Try to get the string value from the axis
        let label = value.as(String.self) ?? ""
        guard let dataPoint = chartData.first(where: { $0.label == label }) else {
            return false
        }
        
        switch selectedTimeframe {
        case .today:
            // Show only key hours: 12am (0), 6am (6), 12pm (12), 6pm (18)
            let keyHours = [0, 6, 12, 18]
            return keyHours.contains(dataPoint.index)
        case .thisWeek:
            // Show all day labels (only 7, so show all)
            return true
        case .month:
            // Show every 5th day or key days (1st, 15th, last day)
            return dataPoint.index % 5 == 0 || dataPoint.index == 0 || dataPoint.index == 14 || dataPoint.index == chartData.count - 1
        case .year:
            // Show every other month or the last month
            return dataPoint.index % 2 == 0 || dataPoint.index == chartData.count - 1
        }
    }
    
    private var bottomSheetHeader: some View {
        VStack(spacing: 0) {
            // Date (secondary) - center aligned
            Text(formattedDateForTimeframe)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            
            // Total time (primary, large) - center aligned with counting animation
            AnimatingNumberText(
                value: displayedTotalSeconds,
                formatter: formatTotalTime
            )
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 4)
            
            // Label - center aligned (dynamic based on category)
            Text(totalTimeLabel)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 8) // Reduced spacing to fit in 213px
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    
    private var formattedDateForTimeframe: String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        
        switch selectedTimeframe {
        case .today:
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: now)
        case .thisWeek:
            // Get today and 6 days prior (last 7 days)
            let today = calendar.startOfDay(for: now)
            guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
                return formatter.string(from: now)
            }
            let weekEnd = today
            
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)
            let endStr = formatter.string(from: weekEnd)
            return "\(startStr) - \(endStr)"
        case .month:
            // Show date range for last 30 days
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            guard let monthStart = calendar.date(byAdding: .day, value: -29, to: today) else {
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: now)
            }
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: monthStart)
            let endStr = formatter.string(from: today)
            return "\(startStr) - \(endStr)"
        case .year:
            // Show date range for last 12 months
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            guard let yearStart = calendar.date(byAdding: .month, value: -12, to: today) else {
                formatter.dateFormat = "yyyy"
                return formatter.string(from: now)
            }
            formatter.dateFormat = "MMM yyyy"
            let startStr = formatter.string(from: yearStart)
            let endStr = formatter.string(from: today)
            return "\(startStr) - \(endStr)"
        }
    }
    
    private var totalTimeForCurrentTimeframe: String {
        let filteredSessions = filterSessionsByCategory(getSessionsForTimeframe(selectedTimeframe))
        let totalSeconds = filteredSessions.reduce(0.0) { $0 + $1.duration }
        return formatTotalTime(totalSeconds)
    }
    
    // Numeric value for animation (in seconds)
    private var totalTimeInSeconds: Double {
        let filteredSessions = filterSessionsByCategory(getSessionsForTimeframe(selectedTimeframe))
        return filteredSessions.reduce(0.0) { $0 + $1.duration }
    }
    
    private var totalTimeLabel: String {
        guard let category = selectedCategoryFilter else {
            return "total flip time"
        }
        
        // Use "total focus time" for "Focus session" category
        if category == .other {
            return "total focus time"
        }
        
        // Otherwise use "total [category] time"
        return "total \(category.displayName.lowercased()) time"
    }
    
    private func formatTotalTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        
        var components: [String] = []
        
        if days > 0 {
            components.append("\(days)d")
        }
        if hours > 0 {
            components.append("\(hours)h")
            components.append("\(minutes)m")
        } else if minutes > 0 || components.isEmpty {
            components.append("\(minutes)m")
        }
        
        return components.joined(separator: " ")
    }
    
    private var timeframeSelector: some View {
        HStack(spacing: 8) {
            ForEach(Timeframe.allCases) { timeframe in
                let isSelected = timeframe == selectedTimeframe
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = timeframe
                        // Reset display limit when switching timeframes
                        sessionsDisplayLimit = 10
                    }
                    AnalyticsService.shared.logTimeframeChanged(timeframe.title)
                } label: {
                    Text(timeframe.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .gray.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassEffect()
    }
    
    private var statCardsGrid: some View {
        HStack(spacing: 16) {
            // Focus sessions count
            Button {
                // Scroll to sessions section
                scrollToSessions()
            } label: {
                VStack(alignment: .center, spacing: 6) {
                    AnimatingNumberText(
                        value: Double(statCardSessionCount),
                        formatter: { value in "\(Int(value))" }
                    )
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    Text("focus sessions")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .padding()
            }
            .buttonStyle(.plain)
            .glassEffect()
            
            // Longest session
            Button {
                // Open longest session detail
                if let longestSession = longestSession {
                    selectedSessionForDetail = longestSession
                }
            } label: {
                VStack(alignment: .center, spacing: 6) {
                    AnimatingNumberText(
                        value: statCardLongestDuration,
                        formatter: { duration in
                            duration > 0 ? formatDuration(duration) : "—"
                        }
                    )
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    Text("longest session")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .padding()
            }
            .buttonStyle(.plain)
            .glassEffect()
        }
    }
    
    // Find the longest session
    private var longestSession: FocusSession? {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        return filtered.max(by: { $0.duration < $1.duration })
    }

    // MARK: - Top Sessions

    private var topSessions: [FocusSession] {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        return Array(filtered.sorted(by: { $0.duration > $1.duration }).prefix(3))
    }

    @ViewBuilder
    private var topSessionsSection: some View {
        let top = topSessions
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Sessions")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, session in
                        Button {
                            selectedSessionForDetail = session
                        } label: {
                            HStack(spacing: 12) {
                                // Rank number
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .frame(width: 16)

                                // Category dot
                                Circle()
                                    .fill(session.category.color)
                                    .frame(width: 8, height: 8)

                                // Duration + optional note
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.formattedDuration)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    if !session.note.isEmpty {
                                        Text(session.note)
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // Category label + date
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(session.category.displayName)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(session.category.color)
                                    Text(sessionShortDate(session))
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.35))
                                }

                                // Personal best badge
                                if session.isPersonalRecord {
                                    Image("personal-best_icn")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sessionShortDate(_ session: FocusSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: session.endTime)
    }

    // Scroll to sessions section
    private func scrollToSessions() {
        // Expand bottom sheet if collapsed
        if !isBottomSheetExpanded {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isBottomSheetExpanded = true
            }
            // Set flag to scroll after expansion
            shouldScrollToSessions = true
        } else {
            // Already expanded, scroll immediately
            shouldScrollToSessions = true
        }
    }
    
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if groupedSessions.isEmpty {
                Text("No sessions yet for this timeframe")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .glassEffect()
            } else {
                VStack(spacing: 16) {
                    ForEach(groupedSessions) { group in
                        // Day header
                        HStack(alignment: .center, spacing: 12) {
                            // Day label
                            Text(group.dayLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Right-aligned: Total time and session count on one line
                            Text("\(formatTimeForHeader(group.totalTime)) · \(group.totalSessions) flip\(group.totalSessions == 1 ? "" : "s")")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        
                        // Sessions for this day
                        LazyVStack(spacing: 12) {
                            ForEach(group.sessions) { session in
                                // Session row
                                Button {
                                    selectedSessionForDetail = session
                                } label: {
                                    HStack {
                                        ZStack {
                                            Circle()
                                                .fill(session.category.color)
                                                .frame(width: 32, height: 32)
                                            
                                            Image(systemName: session.category.icon)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.formattedDuration)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                            Text(formatSessionTimeRange(session))
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.white.opacity(0.6))
                                            
                                            if !session.note.isEmpty {
                                                Text(session.note)
                                                    .font(.system(size: 12, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .lineLimit(2)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 8) {
                                            // Personal best icon
                                            if session.isPersonalRecord {
                                                Image("personal-best_icn")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 24, height: 24)
                                            }
                                            
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text("+\(session.points)")
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.white)
                                                Text("pts")
                                                    .font(.system(size: 11, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                        }
                                    }
                                    .padding()
                                    .glassEffect()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Load More button
                    if hasMoreSessions {
                        Button {
                            withAnimation {
                                sessionsDisplayLimit += 10
                            }
                        } label: {
                            Text("Load more")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func toolbar(topInset: CGFloat) -> some View {
        ZStack(alignment: .center) {
            // COLLAPSED state: streak + milestones on left, ? + settings on right
            HStack {
                HStack(spacing: 8) {
                    streakCounter
                    milestonesButton
                }
                Spacer()
                HStack(spacing: 8) {
                    toolbarButton(systemName: "questionmark.circle.fill") {
                        showHowToStart = true
                        AnalyticsService.shared.logButtonTap("how_to_start")
                    }
                    toolbarButton(systemName: "gearshape.fill") {
                        showSettings = true
                        AnalyticsService.shared.logButtonTap("settings")
                    }
                }
            }
            .opacity(isBottomSheetExpanded ? 0 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isBottomSheetExpanded)
            .allowsHitTesting(!isBottomSheetExpanded)

            // EXPANDED state: 7-day calendar strip (always in hierarchy for matchedGeometryEffect)
            WeekCalendarStripView(
                sessions: sessions,
                user: currentUser,
                namespace: badgeNamespace,
                isBottomSheetExpanded: isBottomSheetExpanded,
                onCalendarTap: {
                    showFullCalendar = true
                    AnalyticsService.shared.logButtonTap("full_calendar")
                }
            )
            .opacity(isBottomSheetExpanded ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isBottomSheetExpanded)
            .allowsHitTesting(isBottomSheetExpanded)
        }
        .padding(.horizontal, 16)
        .padding(.top, 68)
    }
    
    private var streakCounter: some View {
        let todayTotalTime = getTodayTotalTime()
        let minimumTime: TimeInterval = 300 // 5 minutes
        let progress = min(1.0, todayTotalTime / minimumTime)
        let hasCompletedToday = progress >= 1.0
        let flameColor = Color(red: 1.0, green: 0.5, blue: 0.0)
        let grayColor = Color.white.opacity(0.3)
        
        return Button(action: {
            showStreakStats = true
        }) {
            HStack(spacing: 6) {
                // Progress-filled flame icon
                ZStack {
                    // Gray background (always full)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(grayColor)
                    
                    // Orange fill based on progress
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(flameColor)
                        .mask(
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geometry.size.width * progress)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        )
                }
                .frame(width: 16, height: 16)
                
                Text("\(currentUser?.currentStreak ?? 0)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func getTodayTotalTime() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        
        return sessions
            .filter { $0.endTime >= today && $0.endTime < tomorrow }
            .reduce(0.0) { $0 + $1.duration }
    }
    
    private var milestonesButton: some View {
        toolbarButton(systemName: "trophy.fill") {
            showMilestones = true
            AnalyticsService.shared.logButtonTap("milestones")
        }
    }
    
    private var totalUnlockedBadges: Int {
        guard let user = currentUser else { return 0 }
        let achievedMilestones = user.achievedMilestones ?? []
        
        // Only count milestones that have SVG badge files available (matching MilestonesView logic)
        let availableMilestones = Milestone.allMilestones.filter { milestone in
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
        
        // Count only achieved milestones that have available badge files
        return availableMilestones.filter { milestone in
            achievedMilestones.contains(milestone.seconds)
        }.count
    }
    
    private func hasCompletedSessionToday() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return false
        }
        
        return sessions.contains { session in
            session.endTime >= today && session.endTime < tomorrow
        }
    }
    
    @ViewBuilder
    private var toolbarLogoView: some View {
        #if canImport(RiveRuntime)
        if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
            RiveViewWrapperNewAPI(
                fileName: "flipphone_logo",
                autoPlay: true,
                stateName: "hero",
                animationName: nil,
                uniqueId: "toolbar-logo",
                artboardName: "flipPhone_animations",
                instanceValue: 0.0
            )
            .frame(width: 44, height: 44)
        } else {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
        }
        #else
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 22)
        #endif
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
    
    private var heroView: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack {
                    // Priority: Rive -> Video -> Static Image -> Fallback
                    Group {
                    #if canImport(RiveRuntime)
                    if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                        RiveViewWrapperNewAPI(
                            fileName: "flipphone_logo",
                            autoPlay: true,
                            stateName: "hero",  // State for hero/home screen
                            animationName: nil,
                            uniqueId: "hero-view",
                            artboardName: "flipPhone_animations",
                            instanceValue: 0.0
                        )
                            .frame(width: min(geometry.size.width, 500), height: min(geometry.size.width, 500))
                            .frame(maxWidth: .infinity)
                        } else if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                            VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                                .frame(width: 180, height: 180)
                        } else if UIImage(named: "AppLogo") != nil {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .rotationEffect(.degrees(orientationManager.isFaceDown ? 0 : 30))
                                .scaleEffect(orientationManager.isFaceDown ? 1.05 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: orientationManager.isFaceDown)
                        } else {
                            fallbackHeroLogo
                        }
                        #else
                        if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                            VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                                .frame(width: 180, height: 180)
                        } else if UIImage(named: "AppLogo") != nil {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .rotationEffect(.degrees(orientationManager.isFaceDown ? 0 : 30))
                                .scaleEffect(orientationManager.isFaceDown ? 1.05 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: orientationManager.isFaceDown)
                        } else {
                            fallbackHeroLogo
                        }
                        #endif
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)
            
            Text(orientationManager.isFaceDown ? "Focus session in progress…" : "Flip your phone to start a focus session…")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private var fallbackHeroLogo: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            ThemeManager.defaultColor,
                            ThemeManager.defaultColor.opacity(0.7),
                            ThemeManager.defaultColor.opacity(0.5),
                            ThemeManager.defaultColor
                        ]),
                        center: .center
                    ),
                    lineWidth: 12
                )
                .frame(width: 180, height: 180)
                .opacity(0.9)
            
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .rotationEffect(.degrees(orientationManager.isFaceDown ? 0 : 30))
                .scaleEffect(orientationManager.isFaceDown ? 1.05 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: orientationManager.isFaceDown)
        }
    }
    
    private func showToast(with message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
    
    private func openGameCenterDashboard() {
        // Open Game Center dashboard using URL scheme
        if let url = URL(string: "gamecenter:") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback: try alternative URL
                if let gameCenterURL = URL(string: "gamecenter://") {
                    UIApplication.shared.open(gameCenterURL)
                }
            }
        }
    }
}

private struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .cornerRadius(16)
    }
}

#Preview {
    FocusTrackingView()
        .preferredColorScheme(.dark)
}

// MARK: - Debug Admin View

#if DEBUG
/// Sheet presented by long-pressing the home screen hero area.
/// Lets you tune animation timing and fire a simulated session.
struct DebugAdminView: View {
    @Binding var stepDuration: Double
    @Binding var pauseDuration: Double
    /// When on, hero Rive gets `sessionSeconds` = last session duration during post-session animation (A/B test).
    @Binding var sendHeroSessionSecondsWhenAnimating: Bool
    /// Second parameter: `true` = QA preview with today's cumulative **starting at 0** (final total = first parameter only).
    let onPlay: (Double, Bool) -> Void

    @State private var selectedSeconds: Double = 3600

    private let testOptions: [(label: String, seconds: Double)] = [
        ("＋5 min",   300),
        ("＋30 min",  1800),
        ("＋1 hr",    3600),
        ("＋3 hr",    10800),
        ("＋7 hr",    25200),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("Animation Debug")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 16)

            VStack(spacing: 20) {
                // Step duration slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Step duration")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(String(format: "%.1fs", stepDuration))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                    Slider(value: $stepDuration, in: 0.3...4.0, step: 0.1)
                        .tint(.yellow)
                }

                // Pause duration slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pause after ding")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(String(format: "%.2fs", pauseDuration))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                    Slider(value: $pauseDuration, in: 0...2.0, step: 0.05)
                        .tint(.yellow)
                }

                Toggle(isOn: $sendHeroSessionSecondsWhenAnimating) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hero sessionSeconds when animating")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Off = always 0 on hero. On = last session duration during tier animation.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .tint(.yellow)

                // Test session pickers
                VStack(alignment: .leading, spacing: 10) {
                    Text("Simulate session")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 8) {
                        ForEach(testOptions, id: \.label) { option in
                            Button {
                                selectedSeconds = option.seconds
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selectedSeconds == option.seconds ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedSeconds == option.seconds
                                            ? Color.yellow
                                            : Color.white.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Play: add simulated duration to today's real total (matches a real session).
                Button {
                    onPlay(selectedSeconds, false)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Play (add to today)")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                // QA: prior cumulative = 0, final = selected duration only (full tier ladder from scratch).
                Button {
                    onPlay(selectedSeconds, true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "0.circle.fill")
                        Text("QA: Play from 0")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()
        }
        .background(Color.black)
    }
}
#endif

// MARK: - Animating Number Text

struct AnimatingNumberText: View {
    let value: Double
    let formatter: (TimeInterval) -> String
    @State private var animatedValue: Double = 0
    
    var body: some View {
        Text(formatter(animatedValue))
            .contentTransition(.numericText())
            .onChange(of: value) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.6)) {
                    animatedValue = newValue
                }
            }
            .onAppear {
                animatedValue = value
            }
    }
}

// Animatable modifier for smooth number interpolation
struct AnimatableNumber: AnimatableModifier {
    var value: Double
    
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    
    func body(content: Content) -> some View {
        content
    }
}

// MARK: - Counting Text (frame-by-frame count-up, data-bound to animations)

/// A text view that conforms to `Animatable` so SwiftUI continuously interpolates
/// its value on every render frame during a `withAnimation` block — giving a true
/// count-up effect that stays locked to any co-animated easing curve (e.g. the bar fill).
struct CountingText: View, Animatable {
    var value: Double
    let formatter: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(formatter(value))
            .contentTransition(.numericText(value: value))
    }
}

// MARK: - Milestone Animation Step

/// One segment of the multi-milestone post-session sequence.
struct MilestoneAnimationStep {
    /// The milestone badge revealed when `completesFullTier` is true.
    let milestone: Milestone
    /// Bar fill fraction at the START of this step (0–1 within the tier).
    let barStart: Double
    /// Bar fill fraction at the END of this step (0–1 within the tier).
    let barEnd: Double
    /// Total focus seconds displayed when the bar starts.
    let totalAtStart: Double
    /// Total focus seconds displayed when the bar ends.
    let totalAtEnd: Double
    /// Whether this step fills the bar to 100 %, triggering a ding + badge swap.
    let completesFullTier: Bool
    /// Wall-clock duration of the fill animation for this step.
    let duration: Double
}

// MARK: - Data Helpers

private extension FocusTrackingView {
    struct StatCardData: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    /// True when a sheet or full-screen flow covers the hero (calendar, session result, settings, etc.).
    var heroSurfaceCoverPresented: Bool {
        var covered = showStreakStats || showMilestones || showSettings || showAddSession || showFullCalendar || showHowToStart
            || selectedSessionForDetail != nil
            || activeSession != nil
        #if DEBUG
        covered = covered || showDebugAdmin
        #endif
        return covered
    }

    func bumpHeroCumulativeBadgeTriggerIfIdle() {
        guard !isAnimatingPostSession else { return }
        // After navigation or sheets, @State can lag `todayDailyMilestone`; without a milestone the logo Rive branch is skipped entirely.
        if displayedDailyMilestone == nil, let live = todayDailyMilestone {
            displayedDailyMilestone = live
        }
        heroCumulativeBadgeTriggerNonce += 1
    }

    /// Collapse the home bottom sheet when session results close (Done or interactive dismiss).
    func collapseBottomSheetForHomeReturn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isBottomSheetExpanded = false
        }
    }
    
    var currentUser: User? {
        users.first
    }
    
    var statCardData: [StatCardData] {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        let totalPoints = filtered.reduce(0) { $0 + $1.points }
        let longestDuration = filtered.map { $0.duration }.max() ?? 0
        
        return [
            StatCardData(label: "focus sessions", value: "\(filtered.count)"),
            StatCardData(label: "focus\npoints", value: "\(totalPoints)"),
            StatCardData(label: "longest session", value: longestDuration > 0 ? formatDuration(longestDuration) : "—")
        ]
    }
    
    // Numeric values for stat card animations
    private var statCardSessionCount: Int {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        return filtered.count
    }
    
    private var statCardPoints: Int {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        return filtered.reduce(0) { $0 + $1.points }
    }
    
    private var statCardLongestDuration: TimeInterval {
        let filtered = filterSessionsByCategory(sessions(for: selectedTimeframe))
        return filtered.map { $0.duration }.max() ?? 0
    }
    
    // MARK: - Shooting Star Hero Animation Data
    
    /// Star data structure for shooting star animation
    struct StarData {
        let duration: TimeInterval
        let color: Color
        let size: Double  // Logarithmic scale based on duration
        let trailLength: Double  // Proportional to duration
        let orbitAngle: Double  // Starting angle for elliptical orbit (radians, randomized 0-360°)
    }
    
    /// Get today's sessions only
    private var todaySessions: [FocusSession] {
        let calendar = Calendar.current
        let now = Date()
        return sessions.filter { calendar.isDate($0.endTime, inSameDayAs: now) }
    }
    
    /// Get today's daily milestone badge
    private var todayDailyMilestone: Milestone? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalTime = todaySessions.reduce(0.0) { $0 + $1.duration }
        return Milestone.dayMilestoneForTotalTime(totalTime)
    }
    
    /// Total focus time accumulated today in seconds
    private var todayTotalTime: Double {
        todaySessions.reduce(0.0) { $0 + $1.duration }
    }
    
    /// The next daily milestone above today's total, or nil if all milestones achieved
    private var nextDayMilestone: Milestone? {
        let milestones = Milestone.allMilestones
        if let current = todayDailyMilestone,
           let idx = milestones.firstIndex(where: { $0.id == current.id }),
           idx + 1 < milestones.count {
            return milestones[idx + 1]
        } else if todayDailyMilestone == nil {
            return milestones.first
        }
        return nil
    }

    /// Next milestone relative to `displayedDailyMilestone` — used during the
    /// multi-step animation so progress-bar labels update in step with the sequence.
    private var displayedNextMilestone: Milestone? {
        let milestones = Milestone.allMilestones
        if let current = displayedDailyMilestone,
           let idx = milestones.firstIndex(where: { $0.id == current.id }),
           idx + 1 < milestones.count {
            return milestones[idx + 1]
        } else if displayedDailyMilestone == nil {
            return milestones.first
        }
        return nil
    }
    
    /// Progress from current milestone toward the next one, clamped 0–1
    private var dayProgressToNextMilestone: Double {
        progressInCurrentTier(forTotalTime: todayTotalTime)
    }

    /// Returns progress within the current tier for any given total focus time.
    /// Used to compute the pre-session start value for the fill animation.
    private func progressInCurrentTier(forTotalTime totalTime: Double) -> Double {
        guard let next = nextDayMilestone else { return 1.0 }
        let currentSeconds = Double(todayDailyMilestone?.seconds ?? 0)
        let nextSeconds = Double(next.seconds)
        guard nextSeconds > currentSeconds else { return 1.0 }
        return max(0, min(1, (totalTime - currentSeconds) / (nextSeconds - currentSeconds)))
    }

    // MARK: - Multi-milestone animation helpers

    /// Builds the ordered sequence of bar-fill steps that animate the user from
    /// `priorTime` (pre-session total) to `finalTime` (post-session total), crossing
    /// each milestone tier boundary along the way.
    private func buildMilestoneSteps(priorTime: Double, finalTime: Double) -> [MilestoneAnimationStep] {
        let stepBaseDuration = animStepBaseDuration
        let allMilestones = Milestone.allMilestones
        var steps: [MilestoneAnimationStep] = []

        let startMilestone = Milestone.dayMilestoneForTotalTime(priorTime)
        let endMilestone   = Milestone.dayMilestoneForTotalTime(finalTime)

        // First milestone threshold to cross
        let startTierNextMilestone: Milestone?
        if let start = startMilestone,
           let idx = allMilestones.firstIndex(where: { $0.id == start.id }),
           idx + 1 < allMilestones.count {
            startTierNextMilestone = allMilestones[idx + 1]
        } else if startMilestone == nil {
            startTierNextMilestone = allMilestones.first
        } else {
            startTierNextMilestone = nil
        }

        // Same tier: session didn't cross any milestone boundary
        if startMilestone?.id == endMilestone?.id {
            guard let firstNext = startTierNextMilestone else { return [] }
            let tierStart = Double(startMilestone?.seconds ?? 0)
            let tierEnd   = Double(firstNext.seconds)
            guard tierEnd > tierStart else { return [] }
            let bs = max(0, min(1, (priorTime - tierStart) / (tierEnd - tierStart)))
            let be = max(0, min(1, (finalTime - tierStart) / (tierEnd - tierStart)))
            let dur = max(0.35, stepBaseDuration * (be - bs))
            steps.append(MilestoneAnimationStep(
                milestone: firstNext,
                barStart: bs, barEnd: be,
                totalAtStart: priorTime, totalAtEnd: finalTime,
                completesFullTier: false,
                duration: dur
            ))
            return steps
        }

        guard let firstNext = startTierNextMilestone,
              let firstIdx  = allMilestones.firstIndex(where: { $0.id == firstNext.id }) else {
            return []
        }
        let endIdx = endMilestone.flatMap { m in allMilestones.firstIndex(where: { $0.id == m.id }) } ?? -1

        var currentTotal = priorTime

        // Walk every complete tier from firstNext up to (and including) endMilestone
        if endIdx >= firstIdx {
            for i in firstIdx...endIdx {
                let milestone = allMilestones[i]
                let tierStartSeconds = Double(i > 0 ? allMilestones[i - 1].seconds : 0)
                let tierEndSeconds   = Double(milestone.seconds)
                guard tierEndSeconds > tierStartSeconds else { continue }

                let bs: Double = (i == firstIdx)
                    ? max(0, (currentTotal - tierStartSeconds) / (tierEndSeconds - tierStartSeconds))
                    : 0.0
                let dur = max(0.35, stepBaseDuration * (1.0 - bs))

                steps.append(MilestoneAnimationStep(
                    milestone: milestone,
                    barStart: bs, barEnd: 1.0,
                    totalAtStart: currentTotal, totalAtEnd: tierEndSeconds,
                    completesFullTier: true,
                    duration: dur
                ))
                currentTotal = tierEndSeconds
            }
        }

        // Final partial step: position within the tier above endMilestone (if any)
        if let endMil = endMilestone {
            let nextAfterEnd: Milestone? = allMilestones.firstIndex(where: { $0.id == endMil.id })
                .flatMap { idx in idx + 1 < allMilestones.count ? allMilestones[idx + 1] : nil }
            let tierStart = Double(endMil.seconds)
            let tierEnd   = Double(nextAfterEnd?.seconds ?? Int.max)
            if tierEnd > tierStart, finalTime > tierStart, finalTime < tierEnd {
                let be = max(0, min(1, (finalTime - tierStart) / (tierEnd - tierStart)))
                if be > 0 {
                    let dur = max(0.35, stepBaseDuration * be)
                    steps.append(MilestoneAnimationStep(
                        milestone: endMil,
                        barStart: 0.0, barEnd: be,
                        totalAtStart: tierStart, totalAtEnd: finalTime,
                        completesFullTier: false,
                        duration: dur
                    ))
                }
            }
        }

        return steps
    }

    /// Total wall-clock duration of the full step sequence (bar fills + pauses after full tiers).
    private func totalSequenceDuration(steps: [MilestoneAnimationStep]) -> Double {
        let fillTime = steps.reduce(0.0) { $0 + $1.duration }
        let pauseCount = steps.filter { $0.completesFullTier }.count
        return fillTime + Double(pauseCount) * animStepPauseDuration
    }

    /// Executes the milestone animation sequence step-by-step.
    /// Text animates once from session start to end over the full sequence duration so it finishes with the final bar.
    /// Tier cuts update one Rive instance: level-up number inputs + `levelUp` trigger (no stacked views / reloads).
    private func runMilestoneAnimation(steps: [MilestoneAnimationStep], index: Int) {
        guard isAnimatingPostSession else { return }
        guard index < steps.count else {
            // DEBUG: keep the simulated cumulativeSeconds/badge until user taps the Rive to end preview.
            // Do NOT overwrite displayedTotalSeconds/displayedDailyMilestone here — that would swap
            // env data back to current values and mess up the sequence. Swap only on tap.
            if debugLevelUpSimulationActive {
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                return
            }

            // Same-tier / under-threshold sessions never run `levelUp`; keeping `isAnimatingPostSession`
            // true with `heroBadgeBurstTriggers == nil` suppresses idle `showCumulativeBadge` for seconds
            // (see `heroBadgeTriggerInputsForRive`). End immediately so the cumulative badge can fire.
            let celebratedTierCrossing = steps.contains { $0.completesFullTier }
            if !celebratedTierCrossing {
                displayedDailyMilestone = todayDailyMilestone
                displayedTotalSeconds = totalTimeInSeconds
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                isAnimatingPostSession = false
                return
            }

            // After a real tier cross, hold the new badge briefly before returning to live idle triggers.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                displayedDailyMilestone = todayDailyMilestone
                displayedTotalSeconds = totalTimeInSeconds
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                isAnimatingPostSession = false
            }
            return
        }

        let step = steps[index]
        let sequenceDuration = totalSequenceDuration(steps: steps)
        let finalTime = steps.last!.totalAtEnd

        if index == 0 {
            heroBadgeBurstTriggers = ["showCumulativeBadge"]
            heroBadgeUseLevelUpNumbers = false
            heroLevelUpFromMilestone = nil
            // Defer clearing so the first layout pass applies numbers + trigger before idle (nil) burst mode.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                heroBadgeBurstTriggers = nil
            }
        }

        // Snap bar to this step's start; text is driven by the single animation below when index == 0
        progressBarDisplayValue = step.barStart
        if index == 0 && !debugLevelUpSimulationActive {
            displayedTotalSeconds = step.totalAtStart
        }

        // `showCumulativeBadge` already fired above for index == 0. Hold the count-up (bottom sheet +
        // hero cumulative binding) briefly so the badge transition can read as leading the numbers.
        let countUpLead: TimeInterval = (index == 0 && !debugLevelUpSimulationActive)
            ? PostSessionPresentationTiming.countUpLeadAfterBadgeTrigger
            : 0

        // Small settle delay so the snap renders before the fill begins, then optional lead before count-up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + countUpLead) {
            if index == 0 && !debugLevelUpSimulationActive {
                // Single text animation from session start to end, completes when the final bar stops
                withAnimation(.easeOut(duration: sequenceDuration)) {
                    displayedTotalSeconds = finalTime
                }
            }

            withAnimation(.easeOut(duration: step.duration)) {
                progressBarDisplayValue = step.barEnd
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + step.duration) {
                guard isAnimatingPostSession else { return }

                if step.completesFullTier {
                    let fromMilestone = displayedDailyMilestone

                    // Set level-up number inputs (FT, TT) BEFORE firing levelUp so Rive's phase events
                    // have cumulativeFromTierSeconds and cumulativeToTierSeconds available when they fire.
                    if let fromMilestone {
                        heroLevelUpFromMilestone = fromMilestone
                        heroBadgeUseLevelUpNumbers = true
                    }
                    if debugLevelUpSimulationActive {
                        displayedTotalSeconds = step.totalAtEnd
                    }
                    displayedDailyMilestone = step.milestone
                    heroPostSessionCumulativeFloor = step.totalAtEnd

                    heroBadgeBurstTriggers = fromMilestone != nil ? ["levelUp"] : ["showCumulativeBadge"]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        heroBadgeBurstTriggers = nil
                    }

                    AudioService.shared.playEndChime()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + animStepPauseDuration) {
                        guard isAnimatingPostSession else { return }
                        heroBadgeUseLevelUpNumbers = false
                        heroLevelUpFromMilestone = nil
                        runMilestoneAnimation(steps: steps, index: index + 1)
                    }
                } else {
                    // Final partial fill: swap badge silently if it changed (no pulse)
                    if !debugLevelUpSimulationActive {
                        if displayedDailyMilestone?.id != todayDailyMilestone?.id {
                            displayedDailyMilestone = todayDailyMilestone
                        }
                    }
                    heroBadgeBurstTriggers = nil
                    heroBadgeUseLevelUpNumbers = false
                    heroLevelUpFromMilestone = nil
                    // Still run past the end to trigger the 2s hold then swap back
                    runMilestoneAnimation(steps: steps, index: steps.count)
                }
            }
        }
    }
    
    /// Formatted label like "20m to 30m" or "45m to 1hr" for the progress indicator
    private var timeRemainingLabel: String? {
        guard let next = nextDayMilestone else { return nil }
        let remaining = Double(next.seconds) - todayTotalTime
        guard remaining > 0 else { return nil }
        let formatted: String
        if remaining < 60 {
            formatted = "<1m"
        } else if remaining < 3600 {
            let mins = Int(ceil(remaining / 60.0))
            formatted = "\(mins)m"
        } else {
            let hours = Int(remaining / 3600)
            let mins = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            formatted = mins == 0 ? "\(hours)hr" : "\(hours)hr \(mins)m"
        }
        return "\(formatted) to \(next.label)"
    }
    
    /// Get badge color for today (from longest session's category)
    /// Most prominent topic/category color for today (longest session), or lavender when none.
    private var todayMilestoneColor: Color {
        if let topSession = todaySessions.sorted(by: { $0.duration > $1.duration }).first {
            return topSession.category.color
        }
        return ThemeManager.defaultColor  // Lavender default
    }
    
    /// Calculate star data for today's sessions
    /// Returns array of star configurations, one per session (limited to 20 stars)
    private var starDataForToday: [StarData] {
        let maxStars = 20
        let sessionsToUse = Array(todaySessions.prefix(maxStars))
        let totalStars = sessionsToUse.count
        
        guard totalStars > 0 else { return [] }
        
        return sessionsToUse.enumerated().map { index, session in
            let duration = session.duration
            let categoryColor = session.category.color
            
            // Logarithmic size calculation
            // Base size: 1.0, Max size: 5.0
            // Formula: size = 1.0 + 4.0 * log10(duration / 60.0) / log10(3600.0 / 60.0)
            let durationMinutes = max(duration / 60.0, 1.0) // Minimum 1 minute
            let logSize = 1.0 + 4.0 * log10(durationMinutes) / log10(60.0) // 60 minutes = max
            let size = min(max(logSize, 1.0), 5.0) // Clamp between 1.0 and 5.0
            
            // Trail length proportional to duration (max 30 units)
            let trailLength = min(duration / 60.0, 30.0)
            
            // Random starting angle 0-360° (converted to radians)
            let orbitAngle = Double.random(in: 0...360) * .pi / 180
            
            return StarData(
                duration: duration,
                color: categoryColor,
                size: size,
                trailLength: trailLength,
                orbitAngle: orbitAngle
            )
        }
    }
    
    /// Build number inputs dictionary for Rive shooting star animation
    private func buildStarNumberInputs() -> [String: Double] {
        var inputs: [String: Double] = [:]
        
        let starData = starDataForToday
        let starCount = starData.count
        
        // Set star count (hero stars artboard; daily badge uses flipphone_logo + session/cumulative inputs)
        inputs["starCount"] = Double(starCount)

        // Global orbit properties (fallbacks when ellipse is not data-bound in Rive)
        inputs["orbitRadius"] = 175.0
        inputs["orbitHeight"] = 0.8
        
        // Convert Color to RGB components (0.0 to 1.0)
        func colorComponents(_ color: Color) -> (r: Double, g: Double, b: Double) {
            let uiColor = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        
        // Add per-star properties (up to 20 stars)
        for (index, star) in starData.enumerated() {
            let prefix = "star\(index)_"
            let rgb = colorComponents(star.color)
            
            inputs["\(prefix)duration"] = star.duration
            inputs["\(prefix)size"] = star.size
            inputs["\(prefix)trailLength"] = star.trailLength
            inputs["\(prefix)orbitAngle"] = star.orbitAngle
            inputs["\(prefix)colorR"] = rgb.r
            inputs["\(prefix)colorG"] = rgb.g
            inputs["\(prefix)colorB"] = rgb.b
        }
        
        return inputs
    }
    
    // Structure for grouped sessions with day headers
    struct SessionGroup: Identifiable {
        let id = UUID()
        let day: Date
        let dayLabel: String
        let sessions: [FocusSession]
        let totalSessions: Int
        let totalTime: TimeInterval
    }
    
    // Group displayed sessions by day
    var groupedSessions: [SessionGroup] {
        let timeframeSessions = sessions(for: selectedTimeframe)
        let filteredSessions = filterSessionsByCategory(timeframeSessions)
        let limitedSessions = Array(filteredSessions.prefix(sessionsDisplayLimit))
        
        let calendar = Calendar.current
        
        // Group ALL sessions by day to calculate accurate totals
        let allGrouped = Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.endTime)
        }
        
        // Group only limited sessions for display
        let limitedGrouped = Dictionary(grouping: limitedSessions) { session in
            calendar.startOfDay(for: session.endTime)
        }
        
        // Create groups with accurate totals from all sessions, but only display limited sessions
        return limitedGrouped.map { (day, limitedDaySessions) in
            // Get all sessions for this day to calculate accurate totals
            let allDaySessions = allGrouped[day] ?? []
            let totalTime = allDaySessions.reduce(0.0) { $0 + $1.duration }
            
            return SessionGroup(
                day: day,
                dayLabel: formatDayLabel(for: day),
                sessions: limitedDaySessions.sorted { $0.endTime > $1.endTime },
                totalSessions: allDaySessions.count, // Use total count from all sessions
                totalTime: totalTime // Use total time from all sessions
            )
        }.sorted { $0.day > $1.day } // Most recent first
    }
    
    // Computed property for displayed sessions with pagination (for backward compatibility)
    private var displayedSessions: [FocusSession] {
        let timeframeSessions = sessions(for: selectedTimeframe)
        let filteredSessions = filterSessionsByCategory(timeframeSessions)
        return Array(filteredSessions.prefix(sessionsDisplayLimit))
    }
    
    // Format day label (Today, Yesterday, or formatted date)
    func formatDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        } else if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    // Format time for day header (e.g., "5:39:40" or "2h 15m")
    func formatTimeForHeader(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
    
    // Format session time range (e.g., "4:10 pm-4:25 pm")
    func formatSessionTimeRange(_ session: FocusSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: session.startTime).lowercased()
        let end = formatter.string(from: session.endTime).lowercased()
        return "\(start) - \(end)"
    }
    
    func sessions(for timeframe: Timeframe) -> [FocusSession] {
        let calendar = Calendar.current
        let now = Date()
        
        var filtered: [FocusSession]
        
        switch timeframe {
        case .today:
            filtered = sessions.filter { calendar.isDate($0.endTime, inSameDayAs: now) }
        case .thisWeek:
            // Last 7 days (today and 6 days prior)
            let today = calendar.startOfDay(for: now)
            guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
                filtered = sessions
                break
            }
            let weekEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            filtered = sessions.filter { $0.endTime >= weekStart && $0.endTime < weekEnd }
        case .month:
            // Last 30 days from today (rolling window)
            let today = calendar.startOfDay(for: now)
            guard let monthStart = calendar.date(byAdding: .day, value: -29, to: today) else {
                filtered = sessions
                break
            }
            let monthEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            filtered = sessions.filter { $0.endTime >= monthStart && $0.endTime < monthEnd }
        case .year:
            // Last 12 months from today (rolling window)
            let today = calendar.startOfDay(for: now)
            guard let yearStart = calendar.date(byAdding: .month, value: -12, to: today) else {
                filtered = sessions
                break
            }
            let yearEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            filtered = sessions.filter { $0.endTime >= yearStart && $0.endTime < yearEnd }
        }
        
        return filtered
    }
    
    func sessionDetailDescription(for session: FocusSession) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        if calendar.isDate(session.endTime, inSameDayAs: Date()) {
            let start = timeFormatter.string(from: session.startTime).lowercased()
            let end = timeFormatter.string(from: session.endTime).lowercased()
            return "\(start)-\(end)"
        } else if calendar.isDateInYesterday(session.endTime) {
            return "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: session.endTime)
        }
    }
    
    func ensureUserExists() {
        if users.isEmpty {
            let user = User(username: "You")
            modelContext.insert(user)
            try? modelContext.save()
        }
    }
    
    func deleteSession(_ session: FocusSession) {
        // Capture values before deletion
        let sessionId = session.id
        let points = session.points
        let duration = session.duration
        
        // Force-load lazy attributes to avoid SwiftData crash
        _ = session.category
        _ = session.note
        
        // Get all sessions before deletion to check milestones
        let allSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let remainingSessions = allSessions.filter { $0.id != sessionId }
        
        // Update user stats if needed
        if let user = currentUser {
            user.totalPoints = max(0, user.totalPoints - points)
            user.totalFocusTime = max(0, user.totalFocusTime - duration)
            user.sessionsCompleted = max(0, user.sessionsCompleted - 1)
            
            // Recalculate longest session from all remaining sessions
            user.longestSession = remainingSessions.map { $0.duration }.max() ?? 0
            
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
            
            // Recalculate day milestones after deletion
            recalculateDayMilestones(allSessions: remainingSessions, user: user)
        }
        
        // Delete the session
        modelContext.delete(session)
        try? modelContext.save()
    }
    
    func deleteSessionById(_ sessionId: UUID) {
        // Fetch the session fresh from the context
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == sessionId }
        )
        
        guard let sessionToDelete = try? modelContext.fetch(descriptor).first else {
            return
        }
        
        deleteSession(sessionToDelete)
    }
    
    func saveManualSession(_ sessionData: SessionData) {
        let duration = sessionData.duration
        guard duration > 0 else { return }
        
        var points = duration >= 60 ? Int(duration / 60) : 1
        let isPersonalRecord = (currentUser?.longestSession ?? 0) < duration
        
        // Add milestone bonus points if a new milestone is achieved
        if let user = currentUser {
            let achievedMilestones = user.achievedMilestones ?? []
            if let newMilestone = Milestone.newMilestoneAchieved(
                duration: duration,
                achievedMilestones: achievedMilestones
            ) {
                points += newMilestone.pointBonus
                // Track the milestone
                var updatedMilestones = achievedMilestones
                if !updatedMilestones.contains(newMilestone.seconds) {
                    updatedMilestones.append(newMilestone.seconds)
                    user.achievedMilestones = updatedMilestones
                }
            }
        }
        
        let session = FocusSession(
            startTime: sessionData.startTime,
            endTime: sessionData.endTime,
            duration: duration,
            note: sessionData.note,
            points: points,
            isPersonalRecord: isPersonalRecord,
            category: sessionData.category,
            pauseCount: 0 // Manual sessions have no pauses
        )
        
        modelContext.insert(session)
        try? modelContext.save()
        
        // Update stats asynchronously to ensure the newly inserted session is included
        if let user = currentUser {
            let context = modelContext
            DispatchQueue.main.async {
                // Fetch all sessions fresh from context to include the newly inserted session
                let allSessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
                
                // Update stats with fresh session list (includes the new session)
                user.updateStats(with: session, allSessions: allSessions)
                
                // Check for day milestones
                checkDayMilestones(for: session, allSessions: allSessions, user: user, context: context)
                
                // Save the updated stats
                try? context.save()
            }
        }
        
        // Show success toast
        toastMessage = "Session added"
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
        
        // Log session creation
        AnalyticsService.shared.logSessionComplete(duration: duration, points: points, category: sessionData.category.displayName)
    }
    
    func completeSession(startTime: Date, duration: TimeInterval) {
        let endTime = Date()
        var points = duration >= 60 ? Int(duration / 60) : 1
        let isPersonalRecord = (currentUser?.longestSession ?? 0) < duration
        
        // Add milestone bonus points if a new milestone is achieved
        if let user = currentUser {
            let achievedMilestones = user.achievedMilestones ?? []
            if let newMilestone = Milestone.newMilestoneAchieved(
                duration: duration,
                achievedMilestones: achievedMilestones
            ) {
                points += newMilestone.pointBonus
                // Track the milestone
                var updatedMilestones = achievedMilestones
                if !updatedMilestones.contains(newMilestone.seconds) {
                    updatedMilestones.append(newMilestone.seconds)
                    user.achievedMilestones = updatedMilestones
                }
            }
        }
        
        let session = FocusSession(
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            note: "",
            points: points,
            isPersonalRecord: isPersonalRecord,
            category: .other,
            pauseCount: orientationManager.pauseCount
        )
        
        // Freeze display state before the session is persisted so the count-up
        // and badge swap animations can start from the correct pre-session values.
        isAnimatingPostSession = true
        // Use full today total (matches daily milestones), not totalTimeInSeconds (respects chart category filter).
        let priorBeforeInsert = todayTotalTime
        displayedTotalSeconds = priorBeforeInsert
        displayedDailyMilestone = Milestone.dayMilestoneForTotalTime(priorBeforeInsert)
        heroPostSessionCumulativeFloor = priorBeforeInsert
        postSessionFrozenPriorTotal = priorBeforeInsert

        modelContext.insert(session)
        try? modelContext.save()
        
        // Show UI immediately for better responsiveness
        activeSession = session
        orientationManager.resetSession()
        
        // Update stats asynchronously after UI is shown to avoid blocking
        // This ensures the newly inserted session is included when fetching all sessions
        if let user = currentUser {
            let context = modelContext
            DispatchQueue.main.async {
                // Fetch all sessions fresh from context to include the newly inserted session
                let allSessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
                
                // Update stats with fresh session list (includes the new session)
                user.updateStats(with: session, allSessions: allSessions)
                
                // Check for day milestones
                checkDayMilestones(for: session, allSessions: allSessions, user: user, context: context)
                
                // Save the updated stats
                try? context.save()
            }
        }
        
        // Log session completion
        AnalyticsService.shared.logSessionComplete(duration: duration, points: points, category: session.category.displayName)
    }
    
    // MARK: - Session Recovery
    
    /// Check for a recovered session on app launch and handle it appropriately
    /// Check for day change and reset star data if needed
    private func checkForDayChange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if day has changed since last display
        if let lastDay = lastDisplayedDay {
            if !calendar.isDate(today, inSameDayAs: lastDay) {
                // Day has changed - stars will reset automatically via computed properties
                // Force view update by toggling heroRiveLoaded
                heroRiveLoaded = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    heroRiveLoaded = true
                }
            }
        }
        
        // Update last displayed day
        lastDisplayedDay = today
    }
    
    private func checkForRecoveredSession() {
        // Wait a moment for orientation manager to initialize and check current orientation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check if there's a persisted session
            guard let persistedStartTime = OrientationManager.getPersistedSessionStartTime() else {
                return
            }
            
            // Calculate duration from persisted start time
            let duration = Date().timeIntervalSince(persistedStartTime)
            
            // If duration is less than 5 seconds, just clear it (likely a false start)
            guard duration >= 5 else {
                orientationManager.clearPersistedSession()
                return
            }
            
            // Check current orientation
            if orientationManager.isFaceDown {
                // Phone is still face down - restore the session
                orientationManager.recoverSessionIfNeeded()
                orientationManager.persistSession()
            } else {
                // Phone is face up - complete the session
                // This means the app was terminated while face down, and user flipped it back
                // Complete the session with the persisted start time
                completeSession(startTime: persistedStartTime, duration: duration)
            }
        }
    }
    
    /// Handle scene phase changes (background/foreground)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // App is going to background - persist the session if active
            if orientationManager.hasActiveSession() {
                orientationManager.persistSession()
            }
        case .active:
            // App is becoming active - immediately check orientation and handle session
            // Use fast interval temporarily for quick detection
            orientationManager.startMonitoringWithFastInterval()
            
            // Immediately check current orientation
            let isFaceDown = orientationManager.checkCurrentOrientationImmediately()
            
            // Handle different scenarios based on session state and orientation
            if orientationManager.hasActiveSession() {
                // There's an active session
                if !isFaceDown {
                    // Phone was flipped up while app was in background - complete session now
                    guard let startTime = orientationManager.sessionStartTime else {
                        orientationManager.resetSession()
                        // Resume normal monitoring after quick check
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.orientationManager.resumeNormalMonitoring()
                        }
                        return
                    }
                    
                    let duration = orientationManager.sessionDuration
                    orientationManager.invalidateTimer()
                    orientationManager.endSession()
                    
                    if duration >= 5 {
                        completeSession(startTime: startTime, duration: duration)
                    } else {
                        AudioService.shared.playCancelChime()
                        orientationManager.resetSession()
                    }
                    
                    // Resume normal monitoring after handling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.orientationManager.resumeNormalMonitoring()
                    }
                } else {
                    // Session is active and phone is still face down - ensure it's persisted
                    orientationManager.persistSession()
                    // Resume normal monitoring after quick check
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.orientationManager.resumeNormalMonitoring()
                    }
                }
            } else {
                // No active session
                if isFaceDown {
                    // Phone is face down - start session immediately
                    // The handleOrientationChange will be called by checkCurrentOrientationImmediately
                    // but we should ensure the session starts right away
                    if !orientationManager.isFaceDown {
                        // Force orientation update to trigger session start
                        orientationManager.checkCurrentOrientationImmediately()
                    }
                }
                
                // Check for recovered session if not already checked
                if !hasCheckedRecoveredSession {
                    checkForRecoveredSession()
                    hasCheckedRecoveredSession = true
                }
                
                // Resume normal monitoring after quick check
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.orientationManager.resumeNormalMonitoring()
                }
            }
        case .inactive:
            // App is becoming inactive - persist session
            if orientationManager.hasActiveSession() {
                orientationManager.persistSession()
            }
        @unknown default:
            break
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
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
    
    func formatMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    func formatMinutesWithDays(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let mins = totalMinutes % 60
        
        var components: [String] = []
        
        if days > 0 {
            components.append("\(days)d")
        }
        if hours > 0 {
            components.append("\(hours)h")
        }
        if mins > 0 || components.isEmpty {
            components.append("\(mins)m")
        }
        
        return components.joined(separator: " ")
    }
    
    struct ActivityData: Identifiable {
        let id: String
        let label: String
        let minutes: Double
        let index: Int
    }
    
    func getChartData(includeAllSessions: Bool = false) -> [ActivityData] {
        switch selectedTimeframe {
        case .today:
            return getHourlyData(includeAllSessions: includeAllSessions)
        case .thisWeek:
            return getDailyData(includeAllSessions: includeAllSessions)
        case .month:
            return getMonthlyDataForCurrentMonth(includeAllSessions: includeAllSessions)
        case .year:
            return getMonthlyData(includeAllSessions: includeAllSessions) // Show last 12 months for year view
        }
    }
    
    // Helper function to filter sessions by category
    private func filterSessionsByCategory(_ sessions: [FocusSession]) -> [FocusSession] {
        guard let categoryFilter = selectedCategoryFilter else {
            return sessions
        }
        return sessions.filter { $0.category == categoryFilter }
    }
    
    // Check if there are more sessions to load
    private var hasMoreSessions: Bool {
        let timeframeSessions = sessions(for: selectedTimeframe)
        let filteredSessions = filterSessionsByCategory(timeframeSessions)
        return filteredSessions.count > sessionsDisplayLimit
    }
    
    // Helper function to get sessions for the selected timeframe
    private func getSessionsForTimeframe(_ timeframe: Timeframe) -> [FocusSession] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        switch timeframe {
        case .today:
            let dayStart = today
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            return sessions.filter { session in
                session.endTime >= dayStart && session.endTime < dayEnd
            }
        case .thisWeek:
            // Last 7 days
            guard let weekStart = calendar.date(byAdding: .day, value: -7, to: today) else {
                return []
            }
            return sessions.filter { session in
                session.endTime >= weekStart && session.endTime <= now
            }
        case .month:
            // Last 30 days
            guard let monthStart = calendar.date(byAdding: .day, value: -30, to: today) else {
                return []
            }
            return sessions.filter { session in
                session.endTime >= monthStart && session.endTime <= now
            }
        case .year:
            // Last 12 months
            guard let yearStart = calendar.date(byAdding: .month, value: -12, to: today) else {
                return []
            }
            return sessions.filter { session in
                session.endTime >= yearStart && session.endTime <= now
            }
        }
    }
    
    func getHourlyData(includeAllSessions: Bool = false) -> [ActivityData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [ActivityData] = []
        
        for hour in 0..<24 {
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: today) else { continue }
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
            
            var hourSessions = sessions.filter { session in
                session.endTime >= hourStart && session.endTime < hourEnd
            }
            if !includeAllSessions {
                hourSessions = filterSessionsByCategory(hourSessions)
            }
            
            let totalMinutes = hourSessions.reduce(0.0) { $0 + $1.duration } / 60.0
            
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            var hourLabel = formatter.string(from: hourStart).lowercased()
            // Remove space between number and am/pm: "12 am" -> "12am"
            hourLabel = hourLabel.replacingOccurrences(of: " ", with: "")
            
            data.append(ActivityData(
                id: "\(hour)",
                label: hourLabel,
                minutes: totalMinutes,
                index: hour
            ))
        }
        
        return data
    }
    
    func getDailyData(includeAllSessions: Bool = false) -> [ActivityData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [ActivityData] = []
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE"
        
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            var daySessions = sessions.filter { session in
                session.endTime >= dayStart && session.endTime < dayEnd
            }
            if !includeAllSessions {
                daySessions = filterSessionsByCategory(daySessions)
            }
            
            let totalMinutes = daySessions.reduce(0.0) { $0 + $1.duration } / 60.0
            let dayAbbrev = dateFormatter.string(from: date)
            
            data.append(ActivityData(
                id: dayAbbrev + "\(i)",
                label: dayAbbrev,
                minutes: totalMinutes,
                index: 6 - i // Reversed index for proper ordering
            ))
        }
        
        return data.reversed() // Show oldest to newest (left to right)
    }
    
    func getMonthlyDataForCurrentMonth(includeAllSessions: Bool = false) -> [ActivityData] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var data: [ActivityData] = []
        
        // Get last 30 days from today
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d"
        
        for i in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            var daySessions = sessions.filter { session in
                session.endTime >= dayStart && session.endTime < dayEnd
            }
            if !includeAllSessions {
                daySessions = filterSessionsByCategory(daySessions)
            }
            
            let totalMinutes = daySessions.reduce(0.0) { $0 + $1.duration } / 60.0
            let dayLabel = dateFormatter.string(from: date)
            
            data.append(ActivityData(
                id: "\(date.timeIntervalSince1970)",
                label: dayLabel,
                minutes: totalMinutes,
                index: 29 - i // Reversed index for proper ordering
            ))
        }
        
        return data.reversed() // Show oldest to newest (left to right)
    }
    
    func getMonthlyData(includeAllSessions: Bool = false) -> [ActivityData] {
        let calendar = Calendar.current
        let today = Date()
        var data: [ActivityData] = []
        
        // Get last 12 months
        for i in 0..<12 {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: today) else { continue }
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            
            var monthSessions = sessions.filter { session in
                session.endTime >= monthStart && session.endTime < monthEnd
            }
            if !includeAllSessions {
                monthSessions = filterSessionsByCategory(monthSessions)
            }
            
            let totalMinutes = monthSessions.reduce(0.0) { $0 + $1.duration } / 60.0
            
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            let monthLabel = formatter.string(from: monthDate)
            
            data.append(ActivityData(
                id: monthLabel + "\(i)",
                label: monthLabel,
                minutes: totalMinutes,
                index: 11 - i // Reversed index for proper ordering
            ))
        }
        
        return data.reversed() // Show oldest to newest (left to right)
    }
    
    func getKeyLabelsForTimeframe(_ timeframe: Timeframe) -> [String]? {
        switch timeframe {
        case .today:
            return ["12 am", "6 am", "12 pm", "6 pm"]
        case .month:
            // For month (last 30 days), show key days: 1st, 8th, 15th, 22nd, and 30th day
            return ["1", "8", "15", "22", "30"]
        default:
            return nil
        }
    }
    
    /// Check for day milestones after a session is completed
    func checkDayMilestones(for session: FocusSession, allSessions: [FocusSession], user: User, context: ModelContext) {
        let calendar = Calendar.current
        let sessionDay = calendar.startOfDay(for: session.endTime)
        
        // Filter sessions to the same day as the completed session
        let daySessions = allSessions.filter { session in
            calendar.isDate(session.endTime, inSameDayAs: sessionDay)
        }
        
        // Calculate total time for that day
        let dailyTotal = daySessions.reduce(0.0) { $0 + $1.duration }
        
        // Check for new day milestones
        let achievedDayMilestones = user.achievedDayMilestones ?? []
        if let newDayMilestone = Milestone.newDayMilestoneAchieved(
            totalTime: dailyTotal,
            achievedDayMilestones: achievedDayMilestones
        ) {
            // Add point bonus for day milestone
            user.totalPoints += newDayMilestone.pointBonus
            
            // Track the day milestone
            var updatedDayMilestones = achievedDayMilestones
            if !updatedDayMilestones.contains(newDayMilestone.seconds) {
                updatedDayMilestones.append(newDayMilestone.seconds)
                user.achievedDayMilestones = updatedDayMilestones
            }
        }
    }
    
    /// Recalculate day milestones after session deletion
    func recalculateDayMilestones(allSessions: [FocusSession], user: User) {
        let calendar = Calendar.current
        
        // Group sessions by day
        let sessionsByDay = Dictionary(grouping: allSessions) { session in
            calendar.startOfDay(for: session.endTime)
        }
        
        // Calculate which day milestones should be achieved
        var validDayMilestones: [Int] = []
        
        for (_, daySessions) in sessionsByDay {
            let dailyTotal = daySessions.reduce(0.0) { $0 + $1.duration }
            if let dayMilestone = Milestone.dayMilestoneForTotalTime(dailyTotal) {
                if !validDayMilestones.contains(dayMilestone.seconds) {
                    validDayMilestones.append(dayMilestone.seconds)
                }
            }
        }
        
        // Update user's achieved day milestones to only include valid ones
        let currentDayMilestones = user.achievedDayMilestones ?? []
        let updatedDayMilestones = currentDayMilestones.filter { validDayMilestones.contains($0) }
        user.achievedDayMilestones = updatedDayMilestones
    }
    
}



