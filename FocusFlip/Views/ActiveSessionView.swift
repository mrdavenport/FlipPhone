import SwiftUI
import UIKit
import Combine

#if canImport(RiveRuntime)
import RiveRuntime
#endif

struct ActiveSessionView: View {
    @EnvironmentObject var orientationManager: OrientationManager
    @State private var rotationAngle: Double = 0
    @State private var fadeToBlackOpacity: Double = 0.0
    @State private var animationTask: Task<Void, Never>?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerCancellable: AnyCancellable?
    
    var body: some View {
        ZStack {
            // Metal shader gradient background (fixed Lavender theme)
            MetalGradientBackground(
                page: 3,
                customColors: MetalGradientBackground.customColorsForTheme(ThemeManager.defaultColor)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false) // Prevent any touch events
            
            VStack(spacing: 40) {
                Spacer()
                
                // "Focus session in progress..." text
                Text("Focus session\nin progress...")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(0.9 * (1.0 - fadeToBlackOpacity))
                
                // Rive animation with live timer - Priority: Rive -> Video -> Fallback programmatic
                Group {
                    #if canImport(RiveRuntime)
                    if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                        RiveViewWrapperNewAPI(
                            fileName: "flipphone_logo",
                            autoPlay: true,
                            stateName: "sessionResults",  // Use session results state
                            animationName: nil,
                            uniqueId: "active-session-view",
                            textInputs: [
                                "sessionDuration": formatDuration(elapsedTime)
                            ],
                            artboardName: nil,
                            instanceValue: 1.0,
                            colorInputs: [
                                "themeColor": ThemeManager.defaultColor
                            ],
                            artboardInputs: nil
                        )
                        .frame(height: 120)
                        .opacity(1.0 - fadeToBlackOpacity)
                    } else if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                        VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                            .frame(width: 200, height: 200)
                            .opacity(1.0 - fadeToBlackOpacity)
                    } else {
                        logoView
                            .frame(height: 200)
                            .opacity(1.0 - fadeToBlackOpacity)
                    }
                    #else
                    if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                        VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                            .frame(width: 200, height: 200)
                            .opacity(1.0 - fadeToBlackOpacity)
                    } else {
                        logoView
                            .frame(height: 200)
                            .opacity(1.0 - fadeToBlackOpacity)
                    }
                    #endif
                }
                
                Spacer()
                
                // Bottom instruction text
                Text("if you're doing it right, you\nshouldn't be able to read this...")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 50)
                    .opacity((1.0 - fadeToBlackOpacity))
            }
            
            // Black overlay that fades in
            Color.black
                .ignoresSafeArea()
                .opacity(fadeToBlackOpacity)
        }
        .onAppear {
            // Ensure idle timer is enabled
            UIApplication.shared.isIdleTimerDisabled = false
            
            startAnimations()
            startTimer()
            
            // After 5 seconds, gradually fade to black
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                pauseAnimations()
                stopTimer()
                
                // Gradually fade to black over 1 second
                withAnimation(.easeOut(duration: 1.0)) {
                    fadeToBlackOpacity = 1.0
                }
                
                // Ensure idle timer is still enabled
                UIApplication.shared.isIdleTimerDisabled = false
                
                // After fade completes, mark screen as sleeping
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    orientationManager.setScreenSleeping(true)
                }
            }
        }
        .onDisappear {
            // Cancel animations when view disappears
            fadeToBlackOpacity = 0.0
            orientationManager.setScreenSleeping(false)
            animationTask?.cancel()
            animationTask = nil
            stopTimer()
        }
    }
    
    private var logoView: some View {
        ZStack {
            // FLIP text
            VStack(spacing: 0) {
                Text("FLIP")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                
                // Mirrored PHONE text
                Text("PHONE")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .scaleEffect(x: -1, y: 1) // Mirror horizontally
            }
            .rotationEffect(.degrees(fadeToBlackOpacity > 0.5 ? 0 : rotationAngle))
            
            // Arrow path
            ArrowShape()
                .stroke(Color(red: 0.2, green: 0.3, blue: 0.6), lineWidth: 8)
                .frame(width: 200, height: 120)
                .rotationEffect(.degrees(fadeToBlackOpacity > 0.5 ? 0 : rotationAngle))
        }
    }
    
    private func startAnimations() {
        guard fadeToBlackOpacity == 0.0 else { return }
        
        // Cancel any existing animation task
        animationTask?.cancel()
        
        // Use a Task instead of withAnimation to have better control
        animationTask = Task {
            // Subtle rotation animation for logo
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
    
    private func pauseAnimations() {
        // Cancel the animation task to stop all animations
        animationTask?.cancel()
        animationTask = nil
        
        // Ensure idle timer is enabled
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func startTimer() {
        // Calculate initial elapsed time
        if let startTime = orientationManager.sessionStartTime {
            elapsedTime = Date().timeIntervalSince(startTime)
        }
        
        // Use Combine Timer publisher to update elapsed time
        let om = orientationManager
        let timerPub = Timer.publish(every: 1.0, on: .main, in: .common)
        timerCancellable = timerPub
            .autoconnect()
            .sink { _ in
                if let startTime = om.sessionStartTime {
                    elapsedTime = Date().timeIntervalSince(startTime)
                }
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
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

// Custom arrow shape
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start from left side of PHONE
        let startX = rect.width * 0.1
        let startY = rect.height * 0.7
        
        // Curve up and over
        let control1X = rect.width * 0.3
        let control1Y = rect.height * 0.2
        let control2X = rect.width * 0.7
        let control2Y = rect.height * 0.1
        
        // End at right side of PHONE
        let endX = rect.width * 0.9
        let endY = rect.height * 0.7
        
        path.move(to: CGPoint(x: startX, y: startY))
        path.addCurve(
            to: CGPoint(x: endX, y: endY),
            control1: CGPoint(x: control1X, y: control1Y),
            control2: CGPoint(x: control2X, y: control2Y)
        )
        
        // Add arrowhead
        let arrowSize: CGFloat = 15
        let angle = atan2(endY - control2Y, endX - control2X)
        
        path.move(to: CGPoint(x: endX, y: endY))
        path.addLine(to: CGPoint(
            x: endX - arrowSize * cos(angle - .pi / 6),
            y: endY - arrowSize * sin(angle - .pi / 6)
        ))
        path.move(to: CGPoint(x: endX, y: endY))
        path.addLine(to: CGPoint(
            x: endX - arrowSize * cos(angle + .pi / 6),
            y: endY - arrowSize * sin(angle + .pi / 6)
        ))
        
        return path
    }
}

#Preview {
    ActiveSessionView()
}

