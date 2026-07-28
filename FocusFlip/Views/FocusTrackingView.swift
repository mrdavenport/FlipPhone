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

/// Single sheet for session result: history vs just-completed (post-flip) flows share one presentation path.
private enum SessionSheetContext: Identifiable {
    case browsing(FocusSession)
    case completing(FocusSession)

    var id: UUID {
        switch self {
        case .browsing(let s), .completing(let s): return s.id
        }
    }

    var session: FocusSession {
        switch self {
        case .browsing(let s), .completing(let s): return s
        }
    }
}

struct FocusTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FocusSession.endTime, order: .reverse) private var sessions: [FocusSession]
    @Query private var users: [User]

    @Namespace private var badgeNamespace
    @Namespace private var timeframeSelectorNamespace
    
    @StateObject private var orientationManager = OrientationManager()
    @State private var selectedTimeframe: Timeframe = .today
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var sessionSheetContext: SessionSheetContext?
    /// Calendar day (start-of-day) shown in the bottom sheet for the **D** timeframe and driven by the day pager / full calendar.
    @State private var focusedCalendarDay: Date = Calendar.current.startOfDay(for: Date())
    /// Shared pager state so top strip and bottom sheet day carousel stay in lockstep.
    @State private var sharedDayPagerSelectionID: String = FocusTrackingView.calendarDayID(for: Calendar.current.startOfDay(for: Date()))
    /// Day chart carousel direction: +1 = newer day, -1 = older day.
    @State private var dayTimelineCarouselDirection: CGFloat = 1
    @State private var isBottomSheetExpanded = false // Starts collapsed
    /// Strip center handoff: 0 = handoff Rive only, 1 = SVG only (`svg = mix`, `rive = 1 - mix` so fades stay locked). Collapsed idle uses 1 so the badge stays SVG-forward between sessions.
    @State private var stripHandoffCrossfadeMix: Double = 1
    /// When false, hero and strip omit `matchedGeometryEffect` so collapse does not interpolate the hero’s frame from the strip cell (40×40 → full aspect).
    @State private var isDailyBadgeMatchedGeometryActive = true
    /// Rive `instance` for strip handoff only (0 vs 4); hero uses stable `heroCumulativeBadgeInstanceValue` to avoid collapsed-size jumps.
    @State private var stripDailyBadgeRiveInstanceAnimated: Double = 0
    /// Cancels delayed instance updates when direction changes mid-transition.
    @State private var badgeInstanceTransitionToken: Int = 0
    @State private var chartEmptyStateOpacity: Double = 0.3
    @State private var showStreakStats = false
    @State private var showMilestones = false
    @State private var showSettings = false
    @State private var showFullCalendar = false
    @State private var fullCalendarInitialDay: Date?
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
#if DEBUG
    /// Temporary toggle for isolating the old hero collapse sizing bug.
    @AppStorage("debugDisableBadgeMatchOnCollapse") private var debugDisableBadgeMatchOnCollapse = false
#endif
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
    /// Dedicated cumulative value for hero Rive during post-session animation.
    /// Keep this decoupled from `displayedTotalSeconds` because SwiftUI sets destination state
    /// immediately even when animated, which can make Rive read the final total too early.
    /// IMPORTANT: Do not drive hero Rive `cumulativeSeconds` from `displayedTotalSeconds` while
    /// `isAnimatingPostSession` is true; use this step-anchored value instead.
    @State private var heroRiveCumulativeSeconds: Double = 0
    /// Prior cumulative seconds captured in `completeSession` before the new session is inserted. On dismiss, step building uses this so it matches the frozen hero state (`todayTotalTime - session.duration` can drift from rounding or @Query timing).
    @State private var postSessionFrozenPriorTotal: Double? = nil
    /// Bumped when starting or skipping post-session milestone animation so pending `asyncAfter` work exits early.
    @State private var postSessionAnimationToken: UInt = 0
    @State private var skipPostSessionButtonVisible: Bool = false
    /// After a real background transition, the next `.active` phase should refire the hero Rive once.
    /// Cold launch also reaches `.active`; without this gate, that paired with other idle bumps and fired
    /// `showCumulativeBadge` too aggressively (`triggerReloadNonce`), which jittered the toolbar area for new users.
    @State private var shouldRefireHeroBadgeAfterNextActivePhase = false

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let screenHeight = proxy.size.height
            
            mainContentView(topInset: topInset, screenHeight: screenHeight, proxy: proxy)
        }
        .ignoresSafeArea()
        // Do not collapse the home bottom sheet here — only completing sessions do (see unified session sheet).
        .sheet(isPresented: $showStreakStats) {
            StreakStatsView(user: currentUser, sessions: sessions)
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showMilestones) {
            MilestonesView(user: currentUser, sessions: sessions)
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddSession) {
            AddSessionView { session in
                saveManualSession(session)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showFullCalendar, onDismiss: {
            fullCalendarInitialDay = nil
        }) {
            FullCalendarView(
                sessions: sessions,
                user: currentUser,
                initialDay: fullCalendarInitialDay,
                onPickDay: { dayStart in
                    let pickedDayID = Self.calendarDayID(for: dayStart)
                    focusedCalendarDay = dayStart
                    if let direction = dayTimelineDirection(from: sharedDayPagerSelectionID, to: pickedDayID) {
                        dayTimelineCarouselDirection = direction
                    }
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.2)) {
                        sharedDayPagerSelectionID = pickedDayID
                    }
                    showFullCalendar = false
                    fullCalendarInitialDay = nil
                    setDailyBadgeMatchedGeometryActive(true)
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                        isBottomSheetExpanded = true
                    }
                }
            )
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
                ),
                disableBadgeMatchOnCollapse: $debugDisableBadgeMatchOnCollapse,
                onSeedRandomSessions: { seedDebugRandomSessions() }
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
                heroRiveCumulativeSeconds = priorTime
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
                prepareForBottomSheetCollapseForDebug()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    isBottomSheetExpanded = false
                }
                showDebugAdmin = false
                postSessionAnimationToken += 1
                let sequenceToken = postSessionAnimationToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard sequenceToken == postSessionAnimationToken else { return }
                    runMilestoneAnimation(steps: steps, index: 0, sequenceToken: sequenceToken)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        #endif
        .onAppear {
            AnalyticsService.shared.logScreenView("FocusTracking")
            sharedDayPagerSelectionID = Self.calendarDayID(for: focusedCalendarDay)
            // Load hero Rive immediately (no delay)
            heroRiveLoaded = true
            // Check for day change to reset stars
            checkForDayChange()
            // Sync all display state instantly on first appear (no animation)
            progressBarDisplayValue = dayProgressToNextMilestone
            displayedTotalSeconds = totalTimeInSeconds
            displayedDailyMilestone = todayDailyMilestone
            heroPostSessionCumulativeFloor = 0
            heroRiveCumulativeSeconds = 0
            stripDailyBadgeRiveInstanceAnimated = heroCumulativeBadgeInstanceValue
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
        .onChange(of: focusedCalendarDay) { _, newDay in
            let id = Self.calendarDayID(for: Calendar.current.startOfDay(for: newDay))
            if sharedDayPagerSelectionID != id {
                if let direction = dayTimelineDirection(from: sharedDayPagerSelectionID, to: id) {
                    dayTimelineCarouselDirection = direction
                }
                sharedDayPagerSelectionID = id
            }
        }
        .onChange(of: sharedDayPagerSelectionID) { _, newID in
            if let day = Self.date(fromCalendarDayID: newID) {
                let dayStart = Calendar.current.startOfDay(for: day)
                if !Calendar.current.isDate(dayStart, inSameDayAs: focusedCalendarDay) {
                    focusedCalendarDay = dayStart
                }
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
        .onChange(of: heroCumulativeBadgeInstanceValue) { _, newValue in
            guard !isBottomSheetExpanded else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                stripDailyBadgeRiveInstanceAnimated = newValue
            }
        }
        .onDisappear {
            orientationManager.stopMonitoring()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
            if newPhase == .background {
                shouldRefireHeroBadgeAfterNextActivePhase = true
            }
            if newPhase == .active, shouldRefireHeroBadgeAfterNextActivePhase {
                shouldRefireHeroBadgeAfterNextActivePhase = false
                if !orientationManager.isFaceDown {
                    bumpHeroCumulativeBadgeTriggerIfIdle()
                }
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
        .sheet(item: $sessionSheetContext, onDismiss: {
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
                heroRiveCumulativeSeconds = priorTime
                justCompletedSession = nil

                // Brief pause so the sheet dismiss animation clears before the sequence begins
                postSessionAnimationToken += 1
                let sequenceToken = postSessionAnimationToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard sequenceToken == postSessionAnimationToken else { return }
                    runMilestoneAnimation(steps: steps, index: 0, sequenceToken: sequenceToken)
                }
            }
        }) { context in
            SessionResultView(session: context.session, user: currentUser) {
                switch context {
                case .browsing:
                    sessionSheetContext = nil
                case .completing:
                    justCompletedSession = context.session
                    sessionSheetContext = nil
                }
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
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                ZStack {
                    heroAndSubheaderView

                    // Badge positioned at hero center, outside the blur container.
                    heroBadgeLayer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom sheet with data
                BottomSheetView(
                    isExpanded: bottomSheetExpandedBinding,
                    screenHeight: screenHeight
                ) {
                    bottomSheetContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .ignoresSafeArea(edges: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)

            toolbar(topInset: topInset)
                .zIndex(100)

            if showToast, let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, topInset + 80)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
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
            if isAnimating && !wasAnimating {
                skipPostSessionButtonVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard isAnimatingPostSession else { return }
                    withAnimation(.easeIn(duration: 0.35)) {
                        skipPostSessionButtonVisible = true
                    }
                }
            }
            if wasAnimating && !isAnimating {
                skipPostSessionButtonVisible = false
                bumpHeroCumulativeBadgeTriggerIfIdle()
            }
        }
        .onChange(of: isBottomSheetExpanded) { wasExpanded, isExpanded in
            if wasExpanded && !isExpanded {
                // Collapsed sheet should mirror cumulative hero (day / all / unfiltered totals).
                selectedTimeframe = .today
                focusedCalendarDay = Calendar.current.startOfDay(for: Date())
                selectedCategoryFilter = nil
                sessionsDisplayLimit = 10
                if !isAnimatingPostSession {
                    displayedTotalSeconds = totalTimeInSeconds
                }
                bumpHeroCumulativeBadgeTriggerIfIdle()
                stripHandoffCrossfadeMix = 1
                badgeInstanceTransitionToken += 1
                let token = badgeInstanceTransitionToken
                // Swipe-down: wait until roughly mid-transition before returning to the collapsed instance (often 0 in your case).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    guard token == badgeInstanceTransitionToken else { return }
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                        stripDailyBadgeRiveInstanceAnimated = heroCumulativeBadgeInstanceValue
                    }
                }
            }
            if !wasExpanded && isExpanded {
                let liveInstance = heroCumulativeBadgeInstanceValue
                badgeInstanceTransitionToken += 1
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) {
                    stripDailyBadgeRiveInstanceAnimated = liveInstance
                }
                withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                    stripDailyBadgeRiveInstanceAnimated = 0
                }
                stripHandoffCrossfadeMix = 0
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        stripHandoffCrossfadeMix = 1
                    }
                }
            }
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
        .animation(.easeInOut(duration: 0.32), value: isBottomSheetExpanded)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if isBottomSheetExpanded {
                prepareForBottomSheetCollapseForDebug()
                withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                    isBottomSheetExpanded = false
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            #if DEBUG
            // If a DEBUG tier animation simulation is active, this long-press is the "acknowledge/reset" moment.
            if debugLevelUpSimulationActive {
                postSessionAnimationToken += 1
                debugLevelUpSimulationActive = false
                isAnimatingPostSession = false
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                heroRiveCumulativeSeconds = 0
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
    
    // MARK: - Hero Badge Layer (outside blur container)

    private var heroBadgeLayer: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 148)
            ZStack {
                heroBadgeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                // Animate a stable square container so collapse/expand stays 1:1 with the square strip badge.
                .frame(maxWidth: 300)
                .aspectRatio(1, contentMode: .fit)
                .dailyBadgeMatchedGeometryIfNeeded(
                    isDailyBadgeMatchedGeometryActive,
                    namespace: badgeNamespace,
                    isSource: !isBottomSheetExpanded
                )
                .opacity(isBottomSheetExpanded ? 0 : 1)
                .animation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12), value: isBottomSheetExpanded)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isBottomSheetExpanded else { return }
                    #if DEBUG
                    // QA sequence: tap at end of sequence ends the preview and returns to actual values
                    if debugLevelUpSimulationActive {
                        postSessionAnimationToken += 1
                        debugLevelUpSimulationActive = false
                        isAnimatingPostSession = false
                        heroBadgeBurstTriggers = nil
                        heroBadgeUseLevelUpNumbers = false
                        heroLevelUpFromMilestone = nil
                        heroPostSessionCumulativeFloor = 0
                        heroRiveCumulativeSeconds = 0
                        displayedDailyMilestone = todayDailyMilestone
                        displayedTotalSeconds = totalTimeInSeconds
                        return
                    }
                    #endif
                    fullCalendarInitialDay = nil
                    showFullCalendar = true
                    AnalyticsService.shared.logButtonTap("hero_calendar")
                }
            heroBadgeProgressIndicator
                .padding(.top, 12)
                .opacity(isBottomSheetExpanded || (displayedNextMilestone == nil && !isAnimatingPostSession) ? 0 : 1)
                .animation(.easeInOut(duration: 0.28), value: isBottomSheetExpanded)
                .allowsHitTesting(false)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Spacers have no contentShape so they pass taps through to heroAndSubheaderView.
        // Only the badge content area above captures taps.
        .overlay(alignment: .topTrailing) {
            if skipPostSessionButtonVisible {
                Button(action: skipPostSessionMilestoneAnimation) {
                    Text("Skip")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 160)
                .padding(.trailing, 20)
            }
        }
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
        if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil && heroRiveLoaded {
            RiveViewWrapperNewAPI(
                fileName: "flipphone_logo",
                autoPlay: true,
                stateName: "milestoneResults",
                animationName: nil,
                uniqueId: "hero-daily",
                artboardName: nil,
                instanceValue: heroCumulativeBadgeInstanceValue,
                colorInputs: [
                    "themeColor": todayMilestoneColor
                ],
                numberInputs: heroDailyBadgeNumberInputs(),
                artboardInputs: nil,
                triggerInputs: heroBadgeTriggerInputsForRive,
                triggerReloadNonce: heroCumulativeBadgeTriggerNonce
            )
            .id("hero-daily")
        } else {
            heroBadgeFallback
        }
        #else
        heroBadgeFallback
        #endif
    }

    /// Second `flipphone_logo` instance in the week strip: same inputs as the hero for a smooth `matchedGeometryEffect`, then crossfades to the strip SVG.
    @ViewBuilder
    private var stripToolbarHandoffRive: some View {
        #if canImport(RiveRuntime)
        if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil && heroRiveLoaded {
            RiveViewWrapperNewAPI(
                fileName: "flipphone_logo",
                autoPlay: true,
                stateName: "milestoneResults",
                animationName: nil,
                uniqueId: "strip-daily-handoff",
                artboardName: nil,
                instanceValue: stripDailyBadgeRiveInstanceAnimated,
                colorInputs: [
                    "themeColor": todayMilestoneColor
                ],
                numberInputs: heroDailyBadgeNumberInputs(),
                artboardInputs: nil,
                triggerInputs: nil,
                triggerReloadNonce: nil
            )
            .id("strip-daily-handoff")
        } else {
            Color.clear
        }
        #else
        Color.clear
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

    /// Same cumulative anchor as `cumulativeSeconds` in `heroNumberInputs` (idle: today’s total; post-session: stepped max). Used for thresholds like orbit halo vs logo-only.
    private var heroCumulativeSecondsForRiveThresholds: Double {
        if isAnimatingPostSession {
            return max(heroRiveCumulativeSeconds, heroPostSessionCumulativeFloor)
        }
        return todayTotalTime
    }

    /// Cumulative hero instance selector:
    /// - 0: below 10m (no cumulative halo variant)
    /// - 4: 10m and above (cumulative halo variant)
    private var heroCumulativeBadgeInstanceValue: Double {
        heroCumulativeSecondsForRiveThresholds < 600 ? 0.0 : 4.0
    }

    /// Hero Rive numbers: cumulative + tier bounds for **this** `milestone` + optional session length for testing.
    private func heroNumberInputs(for milestone: Milestone) -> [String: Double] {
        let cumulative: Double
        if isAnimatingPostSession {
            cumulative = max(heroRiveCumulativeSeconds, heroPostSessionCumulativeFloor)
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
        let cumulative = max(heroRiveCumulativeSeconds, heroPostSessionCumulativeFloor)
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
                if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil && heroRiveLoaded {
                    RiveViewWrapperNewAPI(
                        fileName: "flipphone_logo",
                        autoPlay: true,
                        stateName: "hero-stars",  // State for hero/home screen with shooting stars
                        animationName: nil,
                        uniqueId: "hero-view",
                        artboardName: "hero animation",  // Artboard with ViewModel and data bindings
                        instanceValue: 0.0,
                        colorInputs: [
                            "themeColor": ThemeManager.defaultColor,
                            "logoColor1": todayMilestoneColor
                        ],
                        numberInputs: buildHeroFlipphoneNumberInputs(),
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
            
            bottomSheetExpandedScroll(pagerAnchorDay: selectedTimeframe == .today ? focusedCalendarDay : nil)
        }
        .gesture(todayDaySwipeGesture)
        .padding(.horizontal, 20) // Add back 20px padding on both sides
    }

    private var todayDaySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard selectedTimeframe == .today else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 36 else { return }
                shiftFocusedDay(by: horizontal < 0 ? 1 : -1)
            }
    }

    private func shiftFocusedDay(by dayOffset: Int) {
        guard dayOffset != 0 else { return }
        let ids = calendarPagerDayIDStrings
        guard let currentIndex = ids.firstIndex(of: sharedDayPagerSelectionID) else { return }
        let newIndex = max(0, min(ids.count - 1, currentIndex + dayOffset))
        guard newIndex != currentIndex else { return }
        let newID = ids[newIndex]
        dayTimelineCarouselDirection = dayOffset > 0 ? 1 : -1
        // Ensure direction is committed before the page-ID transition starts.
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.2)) {
                sharedDayPagerSelectionID = newID
            }
        }
    }

    private func dayTimelineDirection(from oldID: String, to newID: String) -> CGFloat? {
        guard oldID != newID else { return nil }
        let ids = calendarPagerDayIDStrings
        guard
            let oldIndex = ids.firstIndex(of: oldID),
            let newIndex = ids.firstIndex(of: newID),
            oldIndex != newIndex
        else { return nil }
        return newIndex > oldIndex ? 1 : -1
    }
    
    /// Scrollable stats + sessions; `pagerAnchorDay` is the calendar day for **D** pages; `nil` for W/M/Y aggregates.
    @ViewBuilder
    private func bottomSheetExpandedScroll(pagerAnchorDay: Date?) -> some View {
        let chartDay: Date = {
            guard pagerAnchorDay != nil else { return Calendar.current.startOfDay(for: Date()) }
            if let fromPager = Self.date(fromCalendarDayID: sharedDayPagerSelectionID) {
                return Calendar.current.startOfDay(for: fromPager)
            }
            return Calendar.current.startOfDay(for: focusedCalendarDay)
        }()
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        weeklyActivityChart(dayStart: chartDay)
                            .id("bottomSheetScrollTop")
                        
                        categoryFilterSection(dayStart: chartDay)
                        
                        statCardsGrid(pagerAnchorDay: pagerAnchorDay)
                        
                        topSessionsSection(pagerAnchorDay: pagerAnchorDay)
                        
                        sessionsSection(pagerAnchorDay: pagerAnchorDay)
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
                .onChange(of: sharedDayPagerSelectionID) { _, _ in
                    // Day (strip, sheet swipe, or calendar): snap sheet scroll back to the chart/header.
                    guard pagerAnchorDay != nil, isBottomSheetExpanded else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("bottomSheetScrollTop", anchor: .top)
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
    
    @ViewBuilder
    private func weeklyActivityChart(dayStart: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
            if selectedTimeframe == .today {
                dayTimelineChart(dayStart: dayStart)
            } else {
                let chartData = getChartData()
                let allSessionsChartData = getChartData(includeAllSessions: true)
                let hasData = chartData.contains { $0.minutes > 0 }
                
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
                        .chartXAxis {
                            if selectedTimeframe == .month {
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
            }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .frame(height: 200)
            .padding(.top, 20) // Add top padding to prevent label clipping
        }
    }
    
    private func dayTimelineChart(dayStart: Date) -> some View {
        let primarySegments = getDayTimelineSegments(includeAllSessions: false, dayStart: dayStart)
        let allSegments = getDayTimelineSegments(includeAllSessions: true, dayStart: dayStart)
        let hasData = !allSegments.isEmpty
        let highlightedSegmentIDs = Set(primarySegments.map(\.id))
        // Filtered mode should be a zoomed view of the same timeline.
        let domainSegments: [DayTimelineSegment] = {
            if selectedCategoryFilter != nil, !primarySegments.isEmpty {
                return primarySegments
            }
            return allSegments
        }()
        let xDomain = dayTimelineDomain(for: domainSegments)
        let axisTicks = dayTimelineTicks(for: xDomain)
        
        return Group {
            if hasData {
                GeometryReader { geometry in
                    let axisLabelHeight: CGFloat = 16
                    let axisSpacing: CGFloat = 6
                    let laneHeight = max(72, geometry.size.height - axisLabelHeight - axisSpacing)
                    let segmentBarHeight = min(124, max(72, laneHeight * 0.72))
                    let isZoomedOut = selectedCategoryFilter == nil
                    let renderSegments = dayTimelineRenderSegments(
                        from: allSegments,
                        zoomedOut: isZoomedOut,
                        domain: xDomain,
                        width: geometry.size.width
                    )
                    
                    VStack(alignment: .leading, spacing: axisSpacing) {
                        ZStack(alignment: .topLeading) {
                            ForEach(axisTicks, id: \.self) { tickSeconds in
                                let fraction = dayTimelineFraction(
                                    forSeconds: tickSeconds,
                                    domainStart: xDomain.startSeconds,
                                    domainEnd: xDomain.endSeconds
                                )
                                Rectangle()
                                    .fill(Color.white.opacity(0.16))
                                    .frame(width: 1, height: laneHeight)
                                    .offset(x: geometry.size.width * CGFloat(fraction))
                            }
                            
                            dayTimelineCarouselSegmentsLayer(
                                renderSegments: renderSegments,
                                highlightedSegmentIDs: highlightedSegmentIDs,
                                width: geometry.size.width,
                                laneHeight: laneHeight,
                                segmentBarHeight: segmentBarHeight,
                                domain: xDomain,
                                dayStart: dayStart,
                                transitionDistance: geometry.size.width + 40
                            )
                        }
                        .animation(.easeInOut(duration: 0.28), value: selectedCategoryFilter)
                        .frame(height: laneHeight)
                        
                        HStack(spacing: 0) {
                            ForEach(Array(axisTicks.enumerated()), id: \.offset) { index, tickSeconds in
                                Text(dayTimelineLabel(forSeconds: tickSeconds, dayStart: dayStart))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: index == 0 ? .leading : (index == axisTicks.count - 1 ? .trailing : .center)
                                    )
                            }
                        }
                        .frame(height: axisLabelHeight)
                    }
                }
            } else {
                Text("flip your phone to start a focus session…")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(chartEmptyStateOpacity)
                    .animation(
                        Animation.easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true),
                        value: chartEmptyStateOpacity
                    )
                    .onAppear {
                        chartEmptyStateOpacity = 0.5
                    }
                    .onDisappear {
                        chartEmptyStateOpacity = 0.3
                    }
            }
        }
    }

    @ViewBuilder
    private func dayTimelineCarouselSegmentsLayer(
        renderSegments: [DayTimelineRenderSegment],
        highlightedSegmentIDs: Set<String>,
        width: CGFloat,
        laneHeight: CGFloat,
        segmentBarHeight: CGFloat,
        domain: DayTimelineDomain,
        dayStart: Date,
        transitionDistance: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(renderSegments) { segment in
                dayTimelineSegmentView(
                    for: segment,
                    in: width,
                    tint: segment.color,
                    laneHeight: laneHeight,
                    segmentBarHeight: segmentBarHeight,
                    domainStart: domain.startSeconds,
                    domainEnd: domain.endSeconds
                )
                .opacity(
                    selectedCategoryFilter == nil || highlightedSegmentIDs.contains(segment.id)
                        ? 1.0
                        : 0.22
                )
            }
        }
        .id(Self.calendarDayID(for: Calendar.current.startOfDay(for: dayStart)))
        .transition(
            .asymmetric(
                insertion: .offset(x: dayTimelineCarouselDirection * transitionDistance).combined(with: .opacity),
                removal: .offset(x: -dayTimelineCarouselDirection * transitionDistance).combined(with: .opacity)
            )
        )
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.2), value: sharedDayPagerSelectionID)
    }
    
    @ViewBuilder
    private func dayTimelineSegmentView(
        for segment: DayTimelineRenderSegment,
        in width: CGFloat,
        tint: Color,
        laneHeight: CGFloat,
        segmentBarHeight: CGFloat,
        domainStart: TimeInterval,
        domainEnd: TimeInterval
    ) -> some View {
        let visibleStart = max(segment.startSeconds, domainStart)
        let visibleEnd = min(segment.endSeconds, domainEnd)
        
        if visibleEnd > visibleStart {
            let startFraction = dayTimelineFraction(
                forSeconds: visibleStart,
                domainStart: domainStart,
                domainEnd: domainEnd
            )
            let endFraction = dayTimelineFraction(
                forSeconds: visibleEnd,
                domainStart: domainStart,
                domainEnd: domainEnd
            )
            let segmentWidth = width * CGFloat(endFraction - startFraction)
            let xOffset = width * CGFloat(startFraction)
            
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: segmentWidth, height: segmentBarHeight)
                .offset(x: xOffset, y: (laneHeight - segmentBarHeight) / 2)
        }
    }
    
    private func dayTimelineLabel(forSeconds secondsFromDayStart: TimeInterval, dayStart: Date) -> String {
        let labelDate = dayStart.addingTimeInterval(secondsFromDayStart)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: labelDate).lowercased()
    }
    
    private func dayTimelineFraction(
        forSeconds seconds: TimeInterval,
        domainStart: TimeInterval,
        domainEnd: TimeInterval
    ) -> Double {
        let clamped = min(max(seconds, domainStart), domainEnd)
        let span = max(1, domainEnd - domainStart)
        return (clamped - domainStart) / span
    }
    
    private func dayTimelineDomain(for segments: [DayTimelineSegment]) -> DayTimelineDomain {
        let fullDay: TimeInterval = 24 * 60 * 60
        guard
            let minStart = segments.map(\.startSeconds).min(),
            let maxEnd = segments.map(\.endSeconds).max()
        else {
            return DayTimelineDomain(startSeconds: 0, endSeconds: fullDay)
        }
        
        // Add breathing room around activity so bars are not flush with edges.
        let padding: TimeInterval = 20 * 60
        var start = max(0, minStart - padding)
        var end = min(fullDay, maxEnd + padding)
        
        // Keep at least 90 minutes span to avoid over-zooming into tiny sessions.
        let minimumSpan: TimeInterval = 90 * 60
        if end - start < minimumSpan {
            let center = (start + end) / 2
            start = max(0, center - minimumSpan / 2)
            end = min(fullDay, center + minimumSpan / 2)
            if end - start < minimumSpan {
                if start == 0 {
                    end = min(fullDay, minimumSpan)
                } else if end == fullDay {
                    start = max(0, fullDay - minimumSpan)
                }
            }
        }
        
        return DayTimelineDomain(startSeconds: start, endSeconds: end)
    }
    
    private func dayTimelineTicks(for domain: DayTimelineDomain) -> [TimeInterval] {
        let steps = 4
        let span = domain.endSeconds - domain.startSeconds
        guard span > 0 else { return [domain.startSeconds] }
        let interval = span / Double(steps)
        
        return (0...steps).map { domain.startSeconds + Double($0) * interval }
    }
    
    private func getDayTimelineSegments(includeAllSessions: Bool, dayStart: Date) -> [DayTimelineSegment] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: dayStart)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let dayDuration = dayEnd.timeIntervalSince(dayStart)
        
        let sessionsForTimeline: [FocusSession] = {
            let sessionsToday = sessions.filter { session in
                session.endTime > dayStart && session.startTime < dayEnd
            }
            return includeAllSessions ? sessionsToday : filterSessionsByCategory(sessionsToday)
        }()
        
        let segments = sessionsForTimeline.compactMap { session -> DayTimelineRawSegment? in
            let clampedStart = max(session.startTime.timeIntervalSince(dayStart), 0)
            let clampedEnd = min(session.endTime.timeIntervalSince(dayStart), dayDuration)
            guard clampedEnd > clampedStart else { return nil }
            
            return DayTimelineRawSegment(
                sessionId: session.id,
                startSeconds: clampedStart,
                endSeconds: clampedEnd,
                color: session.category.color,
                category: session.category
            )
        }
        .sorted { $0.startSeconds < $1.startSeconds }
        
        return segments.map { segment in
            DayTimelineSegment(
                id: segment.sessionId.uuidString,
                startSeconds: segment.startSeconds,
                endSeconds: segment.endSeconds,
                color: segment.color,
                category: segment.category
            )
        }
    }
    
    /// Render-time timeline shaping for the "All" state:
    /// 1) merge nearby same-category sessions into one rounded block;
    /// 2) enforce a minimum 1 px gap between adjacent different-category blocks.
    private func dayTimelineRenderSegments(
        from segments: [DayTimelineSegment],
        zoomedOut: Bool,
        domain: DayTimelineDomain,
        width: CGFloat
    ) -> [DayTimelineRenderSegment] {
        let sorted = segments.sorted { $0.startSeconds < $1.startSeconds }
        var shaped: [DayTimelineRenderSegment]
        if zoomedOut {
            let mergeGapThreshold: TimeInterval = 8 * 60
            var merged: [DayTimelineRenderSegment] = []
            for segment in sorted {
                if let last = merged.last,
                   last.category == segment.category,
                   segment.startSeconds - last.endSeconds <= mergeGapThreshold {
                    merged[merged.count - 1].endSeconds = max(last.endSeconds, segment.endSeconds)
                } else {
                    merged.append(
                        DayTimelineRenderSegment(
                            id: segment.id,
                            startSeconds: segment.startSeconds,
                            endSeconds: segment.endSeconds,
                            color: segment.color,
                            category: segment.category
                        )
                    )
                }
            }
            shaped = merged
        } else {
            shaped = sorted.map {
                DayTimelineRenderSegment(
                    id: $0.id,
                    startSeconds: $0.startSeconds,
                    endSeconds: $0.endSeconds,
                    color: $0.color,
                    category: $0.category
                )
            }
        }
        
        let secondsPerPoint = (domain.endSeconds - domain.startSeconds) / max(1, TimeInterval(width))
        let minGapSeconds = secondsPerPoint * 1.0
        let minBarWidthSeconds = secondsPerPoint * 1.5
        
        if shaped.count < 2 { return shaped }
        
        for index in 0..<(shaped.count - 1) {
            let shouldEnforceGap: Bool = zoomedOut
                ? (shaped[index].category != shaped[index + 1].category)
                : true
            guard shouldEnforceGap else { continue }
            let currentEnd = shaped[index].endSeconds
            let nextStart = shaped[index + 1].startSeconds
            let currentGap = nextStart - currentEnd
            guard currentGap < minGapSeconds else { continue }
            
            let needed = minGapSeconds - currentGap
            let currentShrinkCapacity = max(0, (shaped[index].endSeconds - shaped[index].startSeconds) - minBarWidthSeconds)
            let nextShrinkCapacity = max(0, (shaped[index + 1].endSeconds - shaped[index + 1].startSeconds) - minBarWidthSeconds)
            
            var shrinkCurrent = min(needed / 2, currentShrinkCapacity)
            var shrinkNext = min(needed / 2, nextShrinkCapacity)
            let remaining = needed - (shrinkCurrent + shrinkNext)
            if remaining > 0 {
                let extraCurrent = min(remaining, currentShrinkCapacity - shrinkCurrent)
                shrinkCurrent += extraCurrent
                let extraNext = min(remaining - extraCurrent, nextShrinkCapacity - shrinkNext)
                shrinkNext += extraNext
            }
            
            shaped[index].endSeconds -= shrinkCurrent
            shaped[index + 1].startSeconds += shrinkNext
        }
        
        return shaped
    }
    
    private struct DayTimelineSegment: Identifiable {
        let id: String
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
        let color: Color
        let category: SessionCategory
    }
    
    private struct DayTimelineRenderSegment: Identifiable {
        let id: String
        var startSeconds: TimeInterval
        var endSeconds: TimeInterval
        let color: Color
        let category: SessionCategory
    }
    
    private struct DayTimelineDomain {
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
    }
    
    private struct DayTimelineRawSegment {
        let sessionId: UUID
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
        let color: Color
        let category: SessionCategory
    }
    
    private func categoryFilterSection(dayStart: Date) -> some View {
        // Get sessions for the current timeframe (per calendar day when on **D**)
        let timeframeSessions: [FocusSession] = {
            if selectedTimeframe == .today {
                return sessions(onCalendarDay: Calendar.current.startOfDay(for: dayStart))
            }
            return getSessionsForTimeframe(selectedTimeframe)
        }()
        
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
        
        // Keep filter chip positions stable while day values animate.
        let sortedCategories = SessionCategory.allCases
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" button
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
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
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedCategoryFilter = (selectedCategoryFilter == category) ? nil : category
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
            bottomSheetTotalTimeLabel
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
            return formatter.string(from: focusedCalendarDay)
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
    
    private var bottomSheetTotalTimeLabel: some View {
        let muted = Color.white.opacity(0.6)
        let labelFont = Font.system(size: 13, design: .rounded)
        let composed: Text = {
            if let category = selectedCategoryFilter {
                if category == .other {
                    return Text("total ").foregroundStyle(muted)
                        + Text("focus").foregroundStyle(category.color)
                        + Text(" time").foregroundStyle(muted)
                }
                let name = category.displayName.lowercased()
                return Text("total ").foregroundStyle(muted)
                    + Text(name).foregroundStyle(category.color)
                    + Text(" time").foregroundStyle(muted)
            }
            return Text("total ").foregroundStyle(muted)
                + Text("flip").foregroundStyle(muted)
                + Text(" time").foregroundStyle(muted)
        }()
        return composed.font(labelFont)
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

    private var isViewingNonTodayDay: Bool {
        selectedTimeframe == .today && !Calendar.current.isDate(focusedCalendarDay, inSameDayAs: Date())
    }
    
    private var timeframeSelector: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = isViewingNonTodayDay ? 0 : 8
            let totalSpacing = spacing * 3
            let availableWidth = max(0, proxy.size.width - totalSpacing)
            let collapsedWeight: CGFloat = 0
            let dWeight: CGFloat = isViewingNonTodayDay ? 1 : 0.25
            let otherWeight: CGFloat = isViewingNonTodayDay ? collapsedWeight : 0.25

            HStack(spacing: spacing) {
                ForEach(Timeframe.allCases) { timeframe in
                    let isSelected = timeframe == selectedTimeframe
                    let isDay = timeframe == .today
                    let slotWeight = isDay ? dWeight : otherWeight
                    let slotWidth = availableWidth * slotWeight

                    Button {
                        if isViewingNonTodayDay && isDay {
                            let todayStart = Calendar.current.startOfDay(for: Date())
                            let todayID = Self.calendarDayID(for: todayStart)
                            if !isBottomSheetExpanded {
                                setDailyBadgeMatchedGeometryActive(true)
                            }
                            withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                                focusedCalendarDay = todayStart
                                if let direction = dayTimelineDirection(from: sharedDayPagerSelectionID, to: todayID) {
                                    dayTimelineCarouselDirection = direction
                                }
                                sharedDayPagerSelectionID = todayID
                                selectedTimeframe = .today
                                sessionsDisplayLimit = 10
                                if !isBottomSheetExpanded {
                                    isBottomSheetExpanded = true
                                }
                            }
                            AnalyticsService.shared.logButtonTap("back_to_today_cta")
                            return
                        }

                        if !isBottomSheetExpanded {
                            setDailyBadgeMatchedGeometryActive(true)
                        }
                        withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                            selectedTimeframe = timeframe
                            sessionsDisplayLimit = 10
                            if !isBottomSheetExpanded {
                                isBottomSheetExpanded = true
                            }
                        }
                        AnalyticsService.shared.logTimeframeChanged(timeframe.title)
                    } label: {
                        Group {
                            if isDay && isViewingNonTodayDay {
                                HStack(spacing: 6) {
                                    Text("Back to today")
                                    Text("→")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(14)
                                .matchedGeometryEffect(
                                    id: "todayTabToCTA",
                                    in: timeframeSelectorNamespace,
                                    properties: .frame,
                                    isSource: true
                                )
                            } else if isDay && isSelected {
                                Text(timeframe.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(14)
                                    .matchedGeometryEffect(
                                        id: "todayTabToCTA",
                                        in: timeframeSelectorNamespace,
                                        properties: .frame,
                                        isSource: !isViewingNonTodayDay
                                    )
                            } else {
                                Text(timeframe.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .gray.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                                    .cornerRadius(14)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: slotWidth)
                    .opacity(isDay ? 1 : (isViewingNonTodayDay ? 0 : 1))
                    .clipped()
                    .allowsHitTesting(isDay || !isViewingNonTodayDay)
                }
            }
        }
        .frame(height: 44)
        .animation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.14), value: isViewingNonTodayDay)
    }
    
    private func statCardsGrid(pagerAnchorDay: Date?) -> some View {
        HStack(spacing: 16) {
            // Focus sessions count
            Button {
                // Scroll to sessions section
                scrollToSessions()
            } label: {
                VStack(alignment: .center, spacing: 6) {
                    AnimatingNumberText(
                        value: Double(statCardSessionCount(pagerAnchorDay: pagerAnchorDay)),
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
                if let longestSession = longestSession(pagerAnchorDay: pagerAnchorDay) {
                    sessionSheetContext = .browsing(longestSession)
                }
            } label: {
                VStack(alignment: .center, spacing: 6) {
                    AnimatingNumberText(
                        value: statCardLongestDuration(pagerAnchorDay: pagerAnchorDay),
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
    
    private func timeframeSessionsForList(pagerAnchorDay: Date?) -> [FocusSession] {
        switch selectedTimeframe {
        case .today:
            let day = pagerAnchorDay.map { Calendar.current.startOfDay(for: $0) } ?? Calendar.current.startOfDay(for: focusedCalendarDay)
            return sessions(onCalendarDay: day)
        default:
            return sessions(for: selectedTimeframe)
        }
    }

    // Find the longest session
    private func longestSession(pagerAnchorDay: Date?) -> FocusSession? {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay))
        return filtered.max(by: { $0.duration < $1.duration })
    }

    // MARK: - Top Sessions

    private func topSessions(pagerAnchorDay: Date?) -> [FocusSession] {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay))
        return Array(filtered.sorted(by: { $0.duration > $1.duration }).prefix(3))
    }

    @ViewBuilder
    private func topSessionsSection(pagerAnchorDay: Date?) -> some View {
        let top = topSessions(pagerAnchorDay: pagerAnchorDay)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Sessions")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, session in
                        Button {
                            sessionSheetContext = .browsing(session)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    topSessionMilestoneBadge(session: session, large: true)
                                        .padding(2)
                                        .frame(height: 104)
                                        .frame(maxWidth: .infinity)

                                    VStack {
                                        HStack(alignment: .top) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .padding(4)
                                                .background(Color.black.opacity(0.4))
                                                .clipShape(Circle())

                                            Spacer(minLength: 0)

                                            if session.isPersonalRecord {
                                                Image("personal-best_icn")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 22, height: 22)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(6)
                                }

                                Text(session.formattedDuration)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .multilineTextAlignment(.center)

                                Text(sessionShortDate(session))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
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

    /// Milestone tier artwork for a session (same SVG + cache path as milestones / calendar).
    @ViewBuilder
    private func topSessionMilestoneBadge(session: FocusSession, large: Bool = false) -> some View {
        let tint = session.category.color
        let iconSize: CGFloat = large ? 44 : 24
        let categoryIconSize: CGFloat = large ? 40 : 22
        if let milestone = Milestone.milestoneForDuration(session.duration) {
            let primary = "badge-\(milestone.label)"
            let sanitized = "badge-\(milestone.label.replacingOccurrences(of: "+", with: "plus"))"
            let resolvedName: String? = SVGCache.shared.rawSVG(named: primary) != nil ? primary
                : SVGCache.shared.rawSVG(named: sanitized) != nil ? sanitized
                : nil

            if let name = resolvedName {
                AsyncBadgeImageView(badgeName: name, color: tint)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Image(systemName: milestone.icon)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Image(systemName: session.category.icon)
                .font(.system(size: categoryIconSize, weight: .medium, design: .rounded))
                .foregroundStyle(tint.opacity(0.85))
                .frame(maxWidth: .infinity)
        }
    }

    // Scroll to sessions section
    private func scrollToSessions() {
        // Expand bottom sheet if collapsed
        if !isBottomSheetExpanded {
            setDailyBadgeMatchedGeometryActive(true)
            withAnimation(.spring(response: 0.58, dampingFraction: 0.88, blendDuration: 0.12)) {
                isBottomSheetExpanded = true
            }
            // Set flag to scroll after expansion
            shouldScrollToSessions = true
        } else {
            // Already expanded, scroll immediately
            shouldScrollToSessions = true
        }
    }
    
    private func sessionsSection(pagerAnchorDay: Date?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if groupedSessions(pagerAnchorDay: pagerAnchorDay).isEmpty {
                Text("No sessions yet for this timeframe")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .glassEffect()
            } else {
                VStack(spacing: 16) {
                    ForEach(groupedSessions(pagerAnchorDay: pagerAnchorDay)) { group in
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
                                    sessionSheetContext = .browsing(session)
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
            // Strip first (back): collapsed toolbar stays visually on top.
            WeekCalendarStripView(
                sessions: sessions,
                user: currentUser,
                isBottomSheetExpanded: isBottomSheetExpanded,
                dailyBadgeMatchedGeometryActive: isDailyBadgeMatchedGeometryActive,
                badgeNamespace: badgeNamespace,
                stripHandoffCrossfadeMix: stripHandoffCrossfadeMix,
                stripCenterHandoffRive: { AnyView(stripToolbarHandoffRive) },
                focusedDay: focusedCalendarDay,
                pageSelectionID: $sharedDayPagerSelectionID,
                onCalendarTap: {
                    fullCalendarInitialDay = nil
                    showFullCalendar = true
                    AnalyticsService.shared.logButtonTap("full_calendar")
                },
                onBadgeDayTap: { day in
                    let cal = Calendar.current
                    let dayStart = cal.startOfDay(for: day)
                    let newID = Self.calendarDayID(for: dayStart)
                    focusedCalendarDay = dayStart
                    if let direction = dayTimelineDirection(from: sharedDayPagerSelectionID, to: newID) {
                        dayTimelineCarouselDirection = direction
                    }
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.2)) {
                        sharedDayPagerSelectionID = newID
                    }
                    selectedTimeframe = .today
                    AnalyticsService.shared.logButtonTap("calendar_strip_day_select")
                }
            )
            .opacity(isBottomSheetExpanded ? 1 : 0)
            .animation(.easeInOut(duration: 0.28), value: isBottomSheetExpanded)
            .allowsHitTesting(isBottomSheetExpanded)

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
            .animation(.easeInOut(duration: 0.28), value: isBottomSheetExpanded)
            .allowsHitTesting(!isBottomSheetExpanded)
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
    /// Temporary switch to isolate the legacy collapse-size jump.
    @Binding var disableBadgeMatchOnCollapse: Bool
    let onSeedRandomSessions: () -> Void
    /// Second parameter: `true` = QA preview with today's cumulative **starting at 0** (final total = first parameter only).
    let onPlay: (Double, Bool) -> Void

    @State private var selectedSeconds: Double = 3600
    @State private var seedRandomHistoryToggle = false

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

                Toggle(isOn: $disableBadgeMatchOnCollapse) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disable badge match on collapse")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Debug-only: breaks hero-strip matched geometry during collapse. The app now delays hero fade-in on collapse to hide the short-box phase while keeping the morph.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .tint(.yellow)

                Toggle(isOn: $seedRandomHistoryToggle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add random session history")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Inserts ~55 sessions across the last 90 days, then turns off.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .tint(.yellow)
                .onChange(of: seedRandomHistoryToggle) { _, newValue in
                    guard newValue else { return }
                    onSeedRandomSessions()
                    seedRandomHistoryToggle = false
                }

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

    static func calendarDayID(for date: Date) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: date)
        let m = c.component(.month, from: date)
        let d = c.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func date(fromCalendarDayID id: String) -> Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let d = Calendar.current.date(from: comps) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    /// Every calendar day from earliest session through today (cap length for pager).
    var calendarPagerDayIDStrings: [String] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let earliestSessionDay = sessions.map { cal.startOfDay(for: $0.endTime) }.min() ?? todayStart
        let start = min(earliestSessionDay, todayStart)
        var ids: [String] = []
        var cursor = start
        while cursor <= todayStart {
            ids.append(Self.calendarDayID(for: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if ids.count > 800 { break }
        }
        return ids.isEmpty ? [Self.calendarDayID(for: todayStart)] : ids
    }

    func sessions(onCalendarDay dayStart: Date) -> [FocusSession] {
        let cal = Calendar.current
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return sessions.filter { $0.endTime >= dayStart && $0.endTime < dayEnd }
    }

    /// True when a sheet or full-screen flow covers the hero (calendar, session result, settings, etc.).
    var heroSurfaceCoverPresented: Bool {
        var covered = showStreakStats || showMilestones || showSettings || showAddSession || showFullCalendar || showHowToStart
            || sessionSheetContext != nil
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
        prepareForBottomSheetCollapseForDebug()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isBottomSheetExpanded = false
        }
    }

    private func setDailyBadgeMatchedGeometryActive(_ active: Bool) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            isDailyBadgeMatchedGeometryActive = active
        }
    }

    private var bottomSheetExpandedBinding: Binding<Bool> {
        Binding(
            get: { isBottomSheetExpanded },
            set: { newValue in
                guard newValue != isBottomSheetExpanded else { return }
                if newValue {
                    setDailyBadgeMatchedGeometryActive(true)
                } else {
                    prepareForBottomSheetCollapseForDebug()
                }
                isBottomSheetExpanded = newValue
            }
        )
    }

    private var shouldDisableBadgeMatchOnCollapse: Bool {
#if DEBUG
        debugDisableBadgeMatchOnCollapse
#else
        false
#endif
    }

    private func prepareForBottomSheetCollapseForDebug() {
        guard shouldDisableBadgeMatchOnCollapse else { return }
        setDailyBadgeMatchedGeometryActive(false)
    }
    
    var currentUser: User? {
        users.first
    }
    
    var statCardData: [StatCardData] {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: nil))
        let totalPoints = filtered.reduce(0) { $0 + $1.points }
        let longestDuration = filtered.map { $0.duration }.max() ?? 0
        
        return [
            StatCardData(label: "focus sessions", value: "\(filtered.count)"),
            StatCardData(label: "focus\npoints", value: "\(totalPoints)"),
            StatCardData(label: "longest session", value: longestDuration > 0 ? formatDuration(longestDuration) : "—")
        ]
    }
    
    // Numeric values for stat card animations
    private func statCardSessionCount(pagerAnchorDay: Date?) -> Int {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay))
        return filtered.count
    }
    
    private func statCardPoints(pagerAnchorDay: Date?) -> Int {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay))
        return filtered.reduce(0) { $0 + $1.points }
    }
    
    private func statCardLongestDuration(pagerAnchorDay: Date?) -> TimeInterval {
        let filtered = filterSessionsByCategory(timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay))
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

    /// Snaps hero + progress UI to live daily totals (same end state as normal post-session completion).
    private func finalizeLiveHeroAfterPostSessionAnimation() {
        skipPostSessionButtonVisible = false
        isAnimatingPostSession = false
        #if DEBUG
        debugLevelUpSimulationActive = false
        #endif
        displayedDailyMilestone = todayDailyMilestone
        displayedTotalSeconds = totalTimeInSeconds
        heroBadgeBurstTriggers = nil
        heroBadgeUseLevelUpNumbers = false
        heroLevelUpFromMilestone = nil
        heroPostSessionCumulativeFloor = 0
        heroRiveCumulativeSeconds = 0
        progressBarDisplayValue = dayProgressToNextMilestone
        postSessionFrozenPriorTotal = nil
    }

    private func skipPostSessionMilestoneAnimation() {
        postSessionAnimationToken += 1
        finalizeLiveHeroAfterPostSessionAnimation()
    }

    /// Executes the milestone animation sequence step-by-step.
    /// Text animates once from session start to end over the full sequence duration so it finishes with the final bar.
    /// Tier cuts update one Rive instance: level-up number inputs + `levelUp` trigger (no stacked views / reloads).
    private func runMilestoneAnimation(steps: [MilestoneAnimationStep], index: Int, sequenceToken: UInt) {
        guard isAnimatingPostSession else { return }
        guard sequenceToken == postSessionAnimationToken else { return }
        guard index < steps.count else {
            // DEBUG: keep the simulated cumulativeSeconds/badge until user taps the Rive to end preview.
            // Do NOT overwrite displayedTotalSeconds/displayedDailyMilestone here — that would swap
            // env data back to current values and mess up the sequence. Swap only on tap.
            if debugLevelUpSimulationActive {
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                heroRiveCumulativeSeconds = 0
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
                heroRiveCumulativeSeconds = 0
                isAnimatingPostSession = false
                return
            }

            // After a real tier cross, hold the new badge briefly before returning to live idle triggers.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard sequenceToken == postSessionAnimationToken else { return }
                guard isAnimatingPostSession else { return }
                displayedDailyMilestone = todayDailyMilestone
                displayedTotalSeconds = totalTimeInSeconds
                heroBadgeBurstTriggers = nil
                heroBadgeUseLevelUpNumbers = false
                heroLevelUpFromMilestone = nil
                heroPostSessionCumulativeFloor = 0
                heroRiveCumulativeSeconds = 0
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
                guard sequenceToken == postSessionAnimationToken else { return }
                heroBadgeBurstTriggers = nil
            }
        }

        // Snap bar to this step's start; text is driven by the single animation below when index == 0
        progressBarDisplayValue = step.barStart
        heroRiveCumulativeSeconds = step.totalAtStart
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
            guard sequenceToken == postSessionAnimationToken else { return }
            guard isAnimatingPostSession else { return }
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
                guard sequenceToken == postSessionAnimationToken else { return }
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
                    heroRiveCumulativeSeconds = step.totalAtEnd

                    // First daily tier (5m) doubles as streak gate — fire Rive `streakExtended` with the tier cut.
                    var burst = fromMilestone != nil ? ["levelUp"] : ["showCumulativeBadge"]
                    if step.milestone.seconds == 300 {
                        burst.append("streakExtended")
                    }
                    heroBadgeBurstTriggers = burst
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        guard sequenceToken == postSessionAnimationToken else { return }
                        heroBadgeBurstTriggers = nil
                    }

                    AudioService.shared.playEndChime()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + animStepPauseDuration) {
                        guard sequenceToken == postSessionAnimationToken else { return }
                        guard isAnimatingPostSession else { return }
                        heroBadgeUseLevelUpNumbers = false
                        heroLevelUpFromMilestone = nil
                        runMilestoneAnimation(steps: steps, index: index + 1, sequenceToken: sequenceToken)
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
                    heroRiveCumulativeSeconds = step.totalAtEnd
                    // Still run past the end to trigger the 2s hold then swap back
                    runMilestoneAnimation(steps: steps, index: steps.count, sequenceToken: sequenceToken)
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

    /// `flipphone_logo` / `hero-stars` (large hero) needs shooting-star inputs plus the same cumulative tier payload as the daily badge.
    private func buildHeroFlipphoneNumberInputs() -> [String: Double] {
        var inputs = buildStarNumberInputs()
        for (key, value) in heroDailyBadgeNumberInputs() {
            inputs[key] = value
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
    private func groupedSessions(pagerAnchorDay: Date?) -> [SessionGroup] {
        let timeframeSessions = timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay)
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
    
    // Displayed sessions with pagination (uses focused day when timeframe is **D**)
    private func displayedSessions(pagerAnchorDay: Date?) -> [FocusSession] {
        let timeframeSessions = timeframeSessionsForList(pagerAnchorDay: pagerAnchorDay)
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
            let day = calendar.startOfDay(for: focusedCalendarDay)
            filtered = sessions(onCalendarDay: day)
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

        // Route manual-add QA through the same "completion card -> dismiss -> hero sequence" flow.
        // Freeze pre-insert cumulative state exactly as we do for real completed sessions.
        isAnimatingPostSession = true
        let priorBeforeInsert = todayTotalTime
        displayedTotalSeconds = priorBeforeInsert
        displayedDailyMilestone = Milestone.dayMilestoneForTotalTime(priorBeforeInsert)
        heroPostSessionCumulativeFloor = priorBeforeInsert
        heroRiveCumulativeSeconds = priorBeforeInsert
        postSessionFrozenPriorTotal = priorBeforeInsert

        modelContext.insert(session)
        try? modelContext.save()

        // Present SessionResultView for this newly created session.
        sessionSheetContext = .completing(session)
        
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
        heroRiveCumulativeSeconds = priorBeforeInsert
        postSessionFrozenPriorTotal = priorBeforeInsert

        modelContext.insert(session)
        try? modelContext.save()
        
        // Show UI immediately for better responsiveness
        sessionSheetContext = .completing(session)
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
                    // Avoid tearing down a brand-new session: foreground + one-shot check often
                    // mis-reads orientation for a moment right after the session UI appears.
                    if orientationManager.shouldIgnoreFaceUpFromScenePhaseCheck() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.orientationManager.resumeNormalMonitoring()
                        }
                        break
                    }
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
    
    func getChartData(includeAllSessions: Bool = false, dayAnchor: Date? = nil) -> [ActivityData] {
        switch selectedTimeframe {
        case .today:
            let anchor = dayAnchor.map { Calendar.current.startOfDay(for: $0) } ?? Calendar.current.startOfDay(for: focusedCalendarDay)
            return getHourlyData(includeAllSessions: includeAllSessions, dayStart: anchor)
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
        let timeframeSessions = timeframeSessionsForList(pagerAnchorDay: nil)
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
            let dayStart = calendar.startOfDay(for: focusedCalendarDay)
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
    
    func getHourlyData(includeAllSessions: Bool = false, dayStart: Date) -> [ActivityData] {
        let calendar = Calendar.current
        let dayAnchor = calendar.startOfDay(for: dayStart)
        var data: [ActivityData] = []
        
        for hour in 0..<24 {
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayAnchor) else { continue }
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

extension View {
    /// Applies the shared daily-badge `matchedGeometryEffect` when active.
    @ViewBuilder
    func dailyBadgeMatchedGeometryIfNeeded(
        _ active: Bool,
        namespace: Namespace.ID,
        isSource: Bool
    ) -> some View {
        if active {
            self.matchedGeometryEffect(id: "dailyBadge", in: namespace, properties: .frame, isSource: isSource)
        } else {
            self
        }
    }

}

#if DEBUG
private extension FocusTrackingView {
    /// Seeds SwiftData with random past sessions for exercising history, charts, and calendars.
    func seedDebugRandomSessions(count: Int = 55) {
        ensureUserExists()
        guard let user = currentUser else { return }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var rng = SystemRandomNumberGenerator()

        let existing = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        var runningLongest = max(user.longestSession, existing.map(\.duration).max() ?? 0)

        struct Draft {
            var start: Date
            var end: Date
            var duration: TimeInterval
            var category: SessionCategory
            var pause: Int
            var points: Int = 0
            var isPersonalRecord: Bool = false
        }

        var drafts: [Draft] = []
        drafts.reserveCapacity(count)

        for _ in 0..<count {
            let dayOffset = Int.random(in: 0..<90, using: &rng)
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }

            let hour = Int.random(in: 6..<24, using: &rng)
            let minute = Int.random(in: 0..<60, using: &rng)
            var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
            comps.hour = hour
            comps.minute = minute
            guard var start = calendar.date(from: comps) else { continue }
            if start > now {
                start = now.addingTimeInterval(-600)
            }

            let roll = Int.random(in: 0..<100, using: &rng)
            let targetDuration: TimeInterval
            if roll < 70 {
                targetDuration = TimeInterval(Int.random(in: 300...5_400, using: &rng))
            } else if roll < 90 {
                targetDuration = TimeInterval(Int.random(in: 5_400...10_800, using: &rng))
            } else {
                targetDuration = TimeInterval(Int.random(in: 10_800...18_000, using: &rng))
            }

            var end = start.addingTimeInterval(targetDuration)
            if end > now {
                end = now
            }
            var actualDuration = end.timeIntervalSince(start)
            if actualDuration < 60 {
                start = end.addingTimeInterval(-120)
                actualDuration = end.timeIntervalSince(start)
            }
            guard actualDuration >= 60 else { continue }

            let category = SessionCategory.allCases.randomElement(using: &rng) ?? .other
            let pause = Int.random(in: 0...4, using: &rng)
            drafts.append(Draft(start: start, end: end, duration: actualDuration, category: category, pause: pause))
        }

        drafts.sort { $0.end < $1.end }

        var achieved = user.achievedMilestones ?? []
        for i in drafts.indices {
            var points = drafts[i].duration >= 60 ? Int(drafts[i].duration / 60) : 1
            if let newMilestone = Milestone.newMilestoneAchieved(
                duration: drafts[i].duration,
                achievedMilestones: achieved
            ) {
                points += newMilestone.pointBonus
                if !achieved.contains(newMilestone.seconds) {
                    achieved.append(newMilestone.seconds)
                }
            }
            let isPR = drafts[i].duration > runningLongest
            runningLongest = max(runningLongest, drafts[i].duration)
            drafts[i].points = points
            drafts[i].isPersonalRecord = isPR
        }

        user.achievedMilestones = achieved
        try? modelContext.save()

        var inserted: [FocusSession] = []
        inserted.reserveCapacity(drafts.count)
        for d in drafts {
            let session = FocusSession(
                startTime: d.start,
                endTime: d.end,
                duration: d.duration,
                note: "",
                points: d.points,
                isPersonalRecord: d.isPersonalRecord,
                category: d.category,
                pauseCount: d.pause
            )
            modelContext.insert(session)
            inserted.append(session)
        }
        try? modelContext.save()

        let allSessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        for session in inserted.sorted(by: { $0.endTime < $1.endTime }) {
            user.updateStats(with: session, allSessions: allSessions)
            checkDayMilestones(for: session, allSessions: allSessions, user: user, context: modelContext)
        }
        try? modelContext.save()

        showToast(with: "Added \(inserted.count) random sessions")
    }
}
#endif



