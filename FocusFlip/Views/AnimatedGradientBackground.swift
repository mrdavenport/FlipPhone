import SwiftUI

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    // Gradient colors - can be customized
    let colors: [Color]
    
    init(colors: [Color]? = nil) {
        self.colors = colors ?? [
            Color(red: 0.95, green: 0.7, blue: 0.9),  // Light pink
            Color(red: 0.8, green: 0.4, blue: 0.9),   // Magenta
            Color(red: 0.5, green: 0.3, blue: 0.8),   // Purple
            Color(red: 0.3, green: 0.2, blue: 0.6),   // Deep indigo
            Color(red: 0.2, green: 0.3, blue: 0.7),   // Blue
            Color(red: 0.4, green: 0.5, blue: 0.9)    // Light blue
        ]
    }
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 3.0)
                    .repeatForever(autoreverses: true)
            ) {
                animateGradient.toggle()
            }
        }
    }
}

// Alternative: Angular gradient animation (rotating gradient)
struct RotatingGradientBackground: View {
    @State private var rotation: Double = 0
    
    let colors: [Color]
    
    init(colors: [Color]? = nil) {
        self.colors = colors ?? [
            Color(red: 0.95, green: 0.7, blue: 0.9),
            Color(red: 0.8, green: 0.4, blue: 0.9),
            Color(red: 0.5, green: 0.3, blue: 0.8),
            Color(red: 0.3, green: 0.2, blue: 0.6)
        ]
    }
    
    var body: some View {
        AngularGradient(
            gradient: Gradient(colors: colors),
            center: .center,
            angle: .degrees(rotation)
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 5.0)
                    .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

// Mesh gradient style (multiple overlapping gradients)
struct MeshGradientBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Multiple overlapping gradients for depth
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.7, blue: 0.9).opacity(0.8),
                    Color(red: 0.8, green: 0.4, blue: 0.9).opacity(0.6)
                ],
                startPoint: animate ? .topLeading : .topTrailing,
                endPoint: animate ? .bottomTrailing : .bottomLeading
            )
            
            LinearGradient(
                colors: [
                    Color(red: 0.5, green: 0.3, blue: 0.8).opacity(0.6),
                    Color(red: 0.3, green: 0.2, blue: 0.6).opacity(0.8)
                ],
                startPoint: animate ? .topTrailing : .bottomLeading,
                endPoint: animate ? .bottomLeading : .topTrailing
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                Animation
                    .easeInOut(duration: 4.0)
                    .repeatForever(autoreverses: true)
            ) {
                animate.toggle()
            }
        }
    }
}
