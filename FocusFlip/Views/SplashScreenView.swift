import SwiftUI
import UIKit

#if canImport(RiveRuntime)
import RiveRuntime
#endif

struct SplashScreenView: View {
    @State private var isAnimating = false
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Metal shader gradient background (fixed Lavender theme)
            MetalGradientBackground(
                page: 3,
                customColors: MetalGradientBackground.customColorsForTheme(ThemeManager.defaultColor)
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Priority: Rive -> Video -> Fallback text
                Group {
                    #if canImport(RiveRuntime)
                    if Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv") != nil {
                        // Same logo instance as SessionResultView header — not `hero animation`,
                        // which is the daily milestone badge / shooting-star scene.
                        RiveViewWrapperNewAPI(
                            fileName: "flipphone_logo",
                            autoPlay: true,
                            stateName: "hero",
                            animationName: nil,
                            uniqueId: "splash-view",
                            artboardName: nil,
                            instanceValue: 3.0,
                            colorInputs: [
                                "themeColor": ThemeManager.defaultColor
                            ],
                            artboardInputs: nil,
                            triggerInputs: nil
                        )
                        .frame(width: 200, height: 200)
                        .opacity(isAnimating ? 1 : 0)
                        .scaleEffect(isAnimating ? 1 : 0.8)
                    } else if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                        VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                            .frame(width: 200, height: 200)
                            .opacity(isAnimating ? 1 : 0)
                            .scaleEffect(isAnimating ? 1 : 0.8)
                    } else {
                        fallbackContent
                    }
                    #else
                    if Bundle.main.url(forResource: "logo", withExtension: "mp4") != nil {
                        VideoPlayerView(videoName: "logo", videoExtension: "mp4")
                            .frame(width: 200, height: 200)
                            .opacity(isAnimating ? 1 : 0)
                            .scaleEffect(isAnimating ? 1 : 0.8)
                    } else {
                        fallbackContent
                    }
                    #endif
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                isAnimating = true
            }
            
            // Auto-dismiss after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isAnimating = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPresented = false
                }
            }
        }
    }
    
    private var fallbackContent: some View {
        VStack(spacing: 16) {
            Text("FLIP\nPHONE")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            ProgressView()
                .tint(.white)
        }
        .opacity(isAnimating ? 1 : 0)
        .scaleEffect(isAnimating ? 1 : 0.8)
    }
}


