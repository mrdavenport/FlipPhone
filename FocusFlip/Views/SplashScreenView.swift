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
                    if Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv") != nil {
                        RiveViewWrapperNewAPI(
                            fileName: "flipphone_hero",
                            autoPlay: true,
                            stateName: "splash",  // State for splash screen
                            animationName: nil,
                            uniqueId: "splash-view",
                            artboardName: "hero animation",  // Artboard with ViewModel and data bindings
                            instanceValue: 2.0,
                            colorInputs: [
                                "themeColor": ThemeManager.defaultColor
                            ],
                            artboardInputs: nil,
                            triggerInputs: ["splashStart"]
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


