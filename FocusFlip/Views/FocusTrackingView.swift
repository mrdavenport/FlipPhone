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
    
    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let screenHeight = proxy.size.height
            
            mainContentView(topInset: topInset, screenHeight: screenHeight, proxy: proxy)
        }
        .ignoresSafeArea()
        .sheet(item: $selectedSessionForDetail) { session in
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
        .onAppear {
            AnalyticsService.shared.logScreenView("FocusTracking")
            // Load hero Rive immediately (no delay)
            heroRiveLoaded = true
            // Check for day change to reset stars
            checkForDayChange()
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
        .onDisappear {
            orientationManager.stopMonitoring()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
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
        .sheet(item: $activeSession) { session in
            SessionResultView(session: session, user: currentUser) {
                activeSession = nil
            }
        }
        .sheet(item: $selectedSessionForDetail) { session in
            SessionResultView(session: session, user: currentUser) {
                selectedSessionForDetail = nil
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
            } else if !orientationManager.isFaceDown {
                showHowToStart = true
            }
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
                .matchedGeometryEffect(
                    id: "dailyBadge",
                    in: badgeNamespace,
                    isSource: !isBottomSheetExpanded
                )
                .opacity(isBottomSheetExpanded ? 0 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isBottomSheetExpanded)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var heroBadgeContent: some View {
        #if canImport(RiveRuntime)
        if let milestone = todayDailyMilestone,
           Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil && heroRiveLoaded {
            // Day milestone achieved — show the milestone badge Rive (same as SessionResultView)
            RiveViewWrapper(
                fileName: "flipphone_logo",
                autoPlay: true,
                stateName: "milestoneResults",
                animationName: nil,
                uniqueId: "hero-daily-\(milestone.badgeShapeValue)",
                artboardName: nil,
                instanceValue: 4.0,
                colorInputs: [
                    "themeColor": todayMilestoneColor
                ],
                numberInputs: [
                    "badgeShapeValue": milestone.badgeShapeValue
                ],
                artboardInputs: nil
            )
            .id("hero-daily-\(milestone.badgeShapeValue)")
        } else if Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv") != nil && heroRiveLoaded {
            // No day milestone yet — show original hero-stars animation
            RiveViewWrapper(
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

    @ViewBuilder
    private func heroLogoView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Priority: Rive -> Video -> Static Image -> Fallback
            Group {
                #if canImport(RiveRuntime)
                // Lazy-load the heavy Rive file to avoid blocking UI
                if Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv") != nil && heroRiveLoaded {
                    RiveViewWrapper(
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
                value: totalTimeInSeconds,
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
        }
        if minutes > 0 || components.isEmpty {
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
            // COLLAPSED state: streak + milestones pills on left, settings on right
            HStack {
                HStack(spacing: 8) {
                    streakCounter
                    milestonesButton
                }
                Spacer()
                toolbarButton(systemName: "gearshape.fill") {
                    showSettings = true
                    AnalyticsService.shared.logButtonTap("settings")
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(20)
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
        Button(action: {
            showMilestones = true
            AnalyticsService.shared.logButtonTap("milestones")
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("\(totalUnlockedBadges)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
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
    
    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            print("🔵 Toolbar button '\(systemName)' tapped")
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle()) // Ensure entire circle is tappable
    }
    
    private var heroView: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack {
                    // Priority: Rive -> Video -> Static Image -> Fallback
                    Group {
                    #if canImport(RiveRuntime)
                    if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                        RiveViewWrapper(
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

// MARK: - Data Helpers

private extension FocusTrackingView {
    struct StatCardData: Identifiable {
        let id = UUID()
        let label: String
        let value: String
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
    
    /// Get badge color for today (from longest session's category)
    private var todayMilestoneColor: Color {
        if let topSession = todaySessions.sorted(by: { $0.duration > $1.duration }).first {
            return topSession.category.color
        }
        return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold fallback
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
        
        // Set star count and badge shape value
        inputs["starCount"] = Double(starCount)
        if let milestone = todayDailyMilestone {
            inputs["badgeShapeValue"] = milestone.badgeShapeValue
        } else {
            inputs["badgeShapeValue"] = 0.0
        }
        
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



