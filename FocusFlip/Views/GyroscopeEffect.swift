import SwiftUI
import CoreMotion

/// A view modifier that applies gyroscope-based 3D rotation effects with optional drag support
struct GyroscopeEffect: ViewModifier {
    @StateObject private var motionManager = GyroscopeMotionManager()
    let intensity: Double // Multiplier for rotation intensity (default: 15 degrees)
    let yAxisMultiplier: Double // Multiplier for Y-axis rotation (default: 2.0 for more pronounced effect)
    let enableDrag: Bool // Whether to enable drag gesture (default: true)
    
    // Drag state
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    init(intensity: Double = 15.0, yAxisMultiplier: Double = 2.0, enableDrag: Bool = true) {
        self.intensity = intensity
        self.yAxisMultiplier = yAxisMultiplier
        self.enableDrag = enableDrag
    }
    
    // Combined rotation values (gyroscope + drag)
    private var combinedYRotation: Double {
        let gyroRotation = motionManager.gravityX * intensity * yAxisMultiplier
        let dragRotation = enableDrag ? Double(dragOffset.width) * 0.5 : 0 // Scale drag for rotation
        return gyroRotation + dragRotation
    }
    
    private var combinedXRotation: Double {
        let gyroRotation = -motionManager.gravityY * intensity - (0.707 * intensity)
        let dragRotation = enableDrag ? Double(dragOffset.height) * 0.5 : 0 // Scale drag for rotation
        return gyroRotation + dragRotation
    }
    
    // Calculate shadow offset based on rotation angles
    private var shadowOffset: (x: CGFloat, y: CGFloat) {
        let yRotation = combinedYRotation
        let xRotation = combinedXRotation
        
        // Convert rotation angles to shadow offsets
        // More rotation = more shadow offset
        let shadowX = CGFloat(yRotation / 5.0) // Horizontal shadow based on Y-axis rotation
        let shadowY = CGFloat(xRotation / 5.0) // Vertical shadow based on X-axis rotation
        
        return (shadowX, shadowY)
    }
    
    // Calculate shadow radius based on rotation (more rotation = larger shadow)
    private var shadowRadius: CGFloat {
        let yRotation = abs(combinedYRotation)
        let xRotation = abs(combinedXRotation)
        let totalRotation = sqrt(yRotation * yRotation + xRotation * xRotation)
        return CGFloat(8 + totalRotation / 3.0) // Base 8, increases with rotation
    }
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(0.4),
                radius: shadowRadius,
                x: shadowOffset.x,
                y: shadowOffset.y
            )
            .rotation3DEffect(
                .degrees(combinedYRotation),
                axis: (x: 0, y: 1, z: 0), // Rotate around Y-axis (left/right tilt)
                perspective: 1.0
            )
            .rotation3DEffect(
                .degrees(combinedXRotation),
                axis: (x: 1, y: 0, z: 0), // Rotate around X-axis (forward/back tilt)
                perspective: 1.0
            )
            .gesture(
                enableDrag ? DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Smoothly return to gyroscope-only rotation
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                    }
                : nil
            )
            .onAppear {
                motionManager.startUpdates()
            }
            .onDisappear {
                motionManager.stopUpdates()
            }
    }
}

/// Lightweight motion manager for gyroscope effects with smoothing
@MainActor
class GyroscopeMotionManager: ObservableObject {
    @Published var gravityX: Double = 0
    @Published var gravityY: Double = 0
    @Published var gravityZ: Double = 0
    
    // Expose smoothed tilt values for Rive holographic effects
    @Published var tiltX: Double = 0 // Normalized tilt X (-1 to 1)
    @Published var tiltY: Double = 0 // Normalized tilt Y (-1 to 1)
    
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    
    // Smoothing values (exponential moving average)
    private var smoothedGravityX: Double = 0
    private var smoothedGravityY: Double = 0
    private var smoothedGravityZ: Double = 0
    private let smoothingFactor: Double = 0.15 // Lower = more smoothing (0.1-0.3 range)
    
    init() {
        motionQueue.qualityOfService = .userInitiated
    }
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ GyroscopeEffect: Device motion not available")
            return
        }
        
        print("✅ GyroscopeEffect: Starting motion updates")
        motionManager.deviceMotionUpdateInterval = 0.05 // Update 20 times per second for smoother effect
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                // Apply exponential moving average smoothing
                self.smoothedGravityX = self.smoothedGravityX * (1.0 - self.smoothingFactor) + gravity.x * self.smoothingFactor
                self.smoothedGravityY = self.smoothedGravityY * (1.0 - self.smoothingFactor) + gravity.y * self.smoothingFactor
                self.smoothedGravityZ = self.smoothedGravityZ * (1.0 - self.smoothingFactor) + gravity.z * self.smoothingFactor
                
                // Update published values with smoothed data
                self.gravityX = self.smoothedGravityX
                self.gravityY = self.smoothedGravityY
                self.gravityZ = self.smoothedGravityZ
                
                // Calculate normalized tilt values for Rive holographic effects
                // Normalize to -1 to 1 range for easy Rive input mapping
                self.tiltX = self.smoothedGravityX.clamped(to: -1.0...1.0)
                self.tiltY = self.smoothedGravityY.clamped(to: -1.0...1.0)
                
                // Debug: Print occasionally
                if Int.random(in: 0..<200) == 0 {
                    print("📱 GyroscopeEffect: tiltX=\(String(format: "%.2f", self.tiltX)), tiltY=\(String(format: "%.2f", self.tiltY))")
                }
            }
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// Helper extension for clamping
extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

extension View {
    /// Applies a gyroscope-based 3D rotation effect to the view with dynamic lighting
    /// Supports both gyroscope-based rotation and manual drag gestures
    /// - Parameters:
    ///   - intensity: Base rotation intensity (default: 15.0 degrees)
    ///   - yAxisMultiplier: Multiplier for Y-axis rotation intensity (default: 2.0 for more pronounced left/right tilt)
    ///   - enableDrag: Whether to enable drag gesture for manual rotation (default: true)
    func gyroscopeEffect(intensity: Double = 15.0, yAxisMultiplier: Double = 2.0, enableDrag: Bool = true) -> some View {
        modifier(GyroscopeEffect(intensity: intensity, yAxisMultiplier: yAxisMultiplier, enableDrag: enableDrag))
    }
}

