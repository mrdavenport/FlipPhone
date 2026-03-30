import SwiftUI
import UIKit
import QuartzCore

// MARK: - UIKit Confetti View
public final class ConfettiUIView: UIView {
    public var colors: [UIColor] = []
    public var intensity: Float = 0.8
    public var style: ConfettiViewStyle = .large

    private(set) var emitter: CAEmitterLayer?
    private var active = false
    private var image: CGImage?

    public func startConfetti(beginAtTimeZero: Bool = true) {
        emitter?.removeFromSuperlayer()
        emitter = CAEmitterLayer()

        if beginAtTimeZero {
            emitter?.beginTime = CACurrentMediaTime()
        }

        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterShape = .line
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)

        var cells = [CAEmitterCell]()
        for color in colors {
            cells.append(confettiWithColor(color: color))
        }

        emitter?.emitterCells = cells

        switch style {
        case .large:
            emitter?.birthRate = 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.emitter?.birthRate = 0.6
            }
        case .small:
            emitter?.birthRate = 0.35
        }

        layer.addSublayer(emitter!)
        active = true
    }

    public func stopConfetti() {
        emitter?.birthRate = 0
        active = false
    }
    
    public func updateColors() {
        guard let emitter = emitter, active else { return }
        
        // Update emitter cells with new colors
        var cells = [CAEmitterCell]()
        for color in colors {
            cells.append(confettiWithColor(color: color))
        }
        
        emitter.emitterCells = cells
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        emitter?.emitterPosition = CGPoint(x: frame.size.width / 2.0, y: -10)
        emitter?.emitterSize = CGSize(width: frame.size.width, height: 1)
    }

    func confettiWithColor(color: UIColor) -> CAEmitterCell {
        let confetti = CAEmitterCell()
        confetti.birthRate = 12.0 * intensity
        confetti.lifetime = 14.0 * intensity
        confetti.lifetimeRange = 0
        confetti.color = color.cgColor
        confetti.velocity = CGFloat(350.0 * intensity)
        confetti.velocityRange = CGFloat(80.0 * intensity)
        confetti.emissionLongitude = CGFloat(Double.pi)
        confetti.emissionRange = CGFloat(Double.pi)
        confetti.spin = CGFloat(3.5 * intensity)
        confetti.spinRange = CGFloat(4.0 * intensity)
        // Scale is set after image creation
        confetti.scaleSpeed = CGFloat(-0.1 * intensity)
        
        // Create a simple square confetti shape if no image is provided
        if let image = image {
            confetti.contents = image
        } else {
            // Create a simple colored square - smaller size for confetti pieces
            let size = CGSize(width: 6, height: 6)
            let renderer = UIGraphicsImageRenderer(size: size)
            let squareImage = renderer.image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            confetti.contents = squareImage.cgImage
        }
        
        // Reduce scale to make confetti pieces smaller
        confetti.scale = 0.5
        confetti.scaleRange = 0.3
        confetti.contentsScale = 1.0
        confetti.setValue("plane", forKey: "particleType")
        confetti.setValue(Double.pi, forKey: "orientationRange")
        confetti.setValue(Double.pi / 2, forKey: "orientationLongitude")
        confetti.setValue(Double.pi / 2, forKey: "orientationLatitude")

        if style == .small {
            confetti.scale = 0.3
            confetti.scaleRange = 0.2
            confetti.contentsScale = 2.0
            confetti.velocity = CGFloat(70.0 * intensity)
            confetti.velocityRange = CGFloat(20.0 * intensity)
        }

        return confetti
    }

    public func isActive() -> Bool {
        return self.active
    }
}

public enum ConfettiViewStyle {
    case large
    case small
}

// MARK: - SwiftUI Wrapper
struct ConfettiView: UIViewRepresentable {
    var colors: [Color]
    var intensity: Float = 0.8
    var style: ConfettiViewStyle = .large
    var shouldStart: Bool = false
    
    func makeUIView(context: Context) -> ConfettiUIView {
        let view = ConfettiUIView()
        view.colors = colors.map { UIColor($0) }
        view.intensity = intensity
        view.style = style
        return view
    }
    
    func updateUIView(_ uiView: ConfettiUIView, context: Context) {
        let newColors = colors.map { UIColor($0) }
        
        // Compare colors by checking RGB components
        func colorsAreEqual(_ c1: UIColor, _ c2: UIColor) -> Bool {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return abs(r1 - r2) < 0.01 && abs(g1 - g2) < 0.01 && 
                   abs(b1 - b2) < 0.01 && abs(a1 - a2) < 0.01
        }
        
        let colorsChanged = newColors.count != uiView.colors.count || 
                           zip(newColors, uiView.colors).contains { !colorsAreEqual($0, $1) }
        
        uiView.colors = newColors
        uiView.intensity = intensity
        uiView.style = style
        
        if shouldStart && !uiView.isActive() {
            uiView.startConfetti()
        } else if !shouldStart && uiView.isActive() {
            uiView.stopConfetti()
        } else if shouldStart && uiView.isActive() && colorsChanged {
            // Colors changed while confetti is active - update the emitter cells
            uiView.updateColors()
        }
    }
}
