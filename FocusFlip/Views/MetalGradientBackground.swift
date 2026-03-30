import SwiftUI
import MetalKit
import Metal

struct MetalGradientBackground: UIViewRepresentable {
    var page: Int = 0 // 0 = red/orange, 1 = blue, 2 = cyan/green, 3 = pink/cyan
    var customColors: [Color]? = nil // Optional custom colors (overrides page)
    var backgroundColor: Color? = nil // Optional background color (replaces black, defaults to black if nil)
    
    // Map theme color to appropriate gradient page
    // Maps ThemeManager colors to Metal gradient pages (0-3)
    static func pageForTheme(_ themeColor: Color) -> Int {
        let uiColor = UIColor(themeColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Match specific ThemeManager colors to gradient pages
        // Theme colors: Lavender, Coral, Mint, Sky, Peach, Rose, Lime, Gold
        
        // Lavender (#B689FF) - purple -> page 3 (pink/cyan)
        if abs(r - 182/255.0) < 0.01 && abs(g - 137/255.0) < 0.01 && abs(b - 255/255.0) < 0.01 {
            return 3
        }
        
        // Coral (#FF7F66) - red/orange -> page 0 (red/orange)
        if abs(r - 255/255.0) < 0.01 && abs(g - 127/255.0) < 0.01 && abs(b - 102/255.0) < 0.01 {
            return 0
        }
        
        // Mint (#66D4AC) - green/cyan -> page 2 (cyan/green)
        if abs(r - 102/255.0) < 0.01 && abs(g - 212/255.0) < 0.01 && abs(b - 172/255.0) < 0.01 {
            return 2
        }
        
        // Sky (#66B2FF) - blue -> page 1 (blue)
        if abs(r - 102/255.0) < 0.01 && abs(g - 178/255.0) < 0.01 && abs(b - 255/255.0) < 0.01 {
            return 1
        }
        
        // Peach (#FFB380) - orange -> page 0 (red/orange)
        if abs(r - 255/255.0) < 0.01 && abs(g - 179/255.0) < 0.01 && abs(b - 128/255.0) < 0.01 {
            return 0
        }
        
        // Rose (#FF80A6) - pink -> page 3 (pink/cyan)
        if abs(r - 255/255.0) < 0.01 && abs(g - 128/255.0) < 0.01 && abs(b - 166/255.0) < 0.01 {
            return 3
        }
        
        // Lime (#B2E666) - green -> page 2 (cyan/green)
        if abs(r - 178/255.0) < 0.01 && abs(g - 230/255.0) < 0.01 && abs(b - 102/255.0) < 0.01 {
            return 2
        }
        
        // Gold (#FFD666) - yellow/orange -> page 0 (red/orange)
        if abs(r - 255/255.0) < 0.01 && abs(g - 214/255.0) < 0.01 && abs(b - 102/255.0) < 0.01 {
            return 0
        }
        
        // Fallback: Map based on dominant color channel
        if r > 0.7 && g < 0.5 && b < 0.5 {
            // Red/Pink dominant -> page 0 (red/orange)
            return 0
        } else if b > 0.6 && r < 0.5 {
            // Blue dominant -> page 1 (blue)
            return 1
        } else if g > 0.6 && b > 0.4 {
            // Cyan/Green dominant -> page 2 (cyan/green)
            return 2
        } else if r > 0.5 && (g > 0.4 || b > 0.5) {
            // Pink/Magenta -> page 3 (pink/cyan)
            return 3
        } else {
            // Default to page 3 (pink/cyan) for purple/lavender
            return 3
        }
    }
    
    // Create a dark version of a color (reduces brightness while maintaining hue)
    static func darkColor(_ color: Color, brightness: CGFloat = 0.25) -> Color {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, l: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &l, alpha: &a)
        
        // Increase brightness slightly and keep good saturation to make it more visible
        // The shader applies additional darkening, so we need a brighter base
        return Color(hue: h, saturation: min(1.0, s * 0.9), brightness: brightness, opacity: a)
    }
    
    // Create custom gradient colors from theme color using HSL for better color harmony
    static func customColorsForTheme(_ themeColor: Color) -> [Color] {
        let uiColor = UIColor(themeColor)
        var h: CGFloat = 0, s: CGFloat = 0, l: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &l, alpha: &a)
        
        // Create 5 harmonious colors by varying saturation and lightness
        // Keep hue consistent for color harmony
        return [
            // Color 1: Bright, high saturation (lighter, vibrant)
            Color(hue: h, saturation: min(1.0, s * 1.1), brightness: min(1.0, l * 1.3)),
            // Color 2: Original theme color
            Color(hue: h, saturation: s, brightness: l),
            // Color 3: Medium saturation, slightly darker
            Color(hue: h, saturation: min(1.0, s * 0.9), brightness: max(0.2, l * 0.7)),
            // Color 4: Lower saturation, darker (deep tone)
            Color(hue: h, saturation: max(0.3, s * 0.7), brightness: max(0.15, l * 0.5)),
            // Color 5: High saturation, medium brightness (rich tone)
            Color(hue: h, saturation: min(1.0, s * 1.05), brightness: min(0.9, l * 1.1))
        ]
    }
    
    func makeUIView(context: Context) -> UIView {
        // Check if Metal is available (simulators may have limited Metal support)
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("⚠️ [MetalGradientBackground] Metal device not available, using fallback gradient")
            return createFallbackGradientView()
        }
        
        // Try to create the Metal view and setup
        do {
            let mtkView = MTKView()
            mtkView.device = device
            mtkView.delegate = context.coordinator
            mtkView.preferredFramesPerSecond = 60
            mtkView.enableSetNeedsDisplay = false
            mtkView.isPaused = false
            mtkView.framebufferOnly = false
            mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            mtkView.backgroundColor = .clear
            
            // Setup Metal - if this fails, use fallback
            try context.coordinator.setupMetal(device: device, view: mtkView, page: page, customColors: customColors, backgroundColor: backgroundColor)
            
            // Verify setup succeeded by checking if pipeline state was created
            guard context.coordinator.renderPipelineState != nil else {
                print("⚠️ [MetalGradientBackground] Metal setup failed (pipeline state nil), using fallback gradient")
                return createFallbackGradientView()
            }
            
            // Update size after a brief delay to ensure layout is complete
            DispatchQueue.main.async {
                let size = mtkView.bounds.size
                if size.width > 0 && size.height > 0 {
                    mtkView.drawableSize = size
                    context.coordinator.updateViewSizeBuffer(size: size)
                }
            }
            
            return mtkView
        } catch {
            print("⚠️ [MetalGradientBackground] Metal initialization error: \(error), using fallback gradient")
            return createFallbackGradientView()
        }
    }
    
    // Create a fallback gradient view using Core Animation
    private func createFallbackGradientView() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Create a simple gradient layer as fallback
        let gradientLayer = CAGradientLayer()
        if let customColors = customColors, !customColors.isEmpty {
            gradientLayer.colors = customColors.prefix(2).map { UIColor($0).cgColor }
        } else {
            // Default gradient based on page
            switch page {
            case 0: // red/orange
                gradientLayer.colors = [UIColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 1.0).cgColor,
                                       UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0).cgColor]
            case 1: // blue
                gradientLayer.colors = [UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0).cgColor,
                                       UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0).cgColor]
            case 2: // cyan/green
                gradientLayer.colors = [UIColor(red: 0.0, green: 0.8, blue: 0.9, alpha: 1.0).cgColor,
                                       UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0).cgColor]
            case 3: // pink/cyan
                gradientLayer.colors = [UIColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 1.0).cgColor,
                                       UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0).cgColor]
            default:
                gradientLayer.colors = [UIColor.black.cgColor, UIColor.darkGray.cgColor]
            }
        }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(gradientLayer)
        
        // Update gradient frame when view layout changes
        DispatchQueue.main.async {
            gradientLayer.frame = view.bounds
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Only update if it's an MTKView
        guard let mtkView = uiView as? MTKView else {
            // For fallback view, update gradient frame if needed
            if let gradientLayer = uiView.layer.sublayers?.first as? CAGradientLayer {
                gradientLayer.frame = uiView.bounds
            }
            return
        }
        context.coordinator.page = page
        context.coordinator.updateCustomColors(customColors)
        context.coordinator.updateBackgroundColor(backgroundColor)
        
        // Update drawable size if view bounds changed
        let currentSize = mtkView.bounds.size
        if currentSize.width > 0 && currentSize.height > 0 {
            if mtkView.drawableSize.width != currentSize.width || mtkView.drawableSize.height != currentSize.height {
                mtkView.drawableSize = currentSize
                context.coordinator.updateViewSizeBuffer(size: currentSize)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Error enum for Metal setup failures
    enum MetalSetupError: Error {
        case commandQueueCreationFailed
        case libraryCreationFailed
        case shaderFunctionNotFound
        case pipelineStateCreationFailed
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var renderPipelineState: MTLRenderPipelineState!
        var vertexBuffer: MTLBuffer!
        var timeBuffer: MTLBuffer!
        var viewSizeBuffer: MTLBuffer!
        var pageBuffer: MTLBuffer!
        var customColorsBuffer: MTLBuffer!
        var useCustomColorsBuffer: MTLBuffer!
        var backgroundColorBuffer: MTLBuffer!
        var page: Int = 0
        var customColors: [Color]?
        var backgroundColor: Color?
        var startTime: CFTimeInterval!
        
        // Structure to match Metal shader
        // Must match CustomColors struct in Metal shader exactly
        struct CustomColorsStruct {
            var color1: SIMD3<Float>  // 12 bytes (3 * Float)
            var color2: SIMD3<Float>  // 12 bytes
            var color3: SIMD3<Float>  // 12 bytes
            var color4: SIMD3<Float>  // 12 bytes
            var color5: SIMD3<Float>  // 12 bytes
            // Total: 60 bytes
        }
        
        func setupMetal(device: MTLDevice, view: MTKView, page: Int, customColors: [Color]?, backgroundColor: Color?) throws {
            self.device = device
            self.page = page
            self.customColors = customColors
            self.backgroundColor = backgroundColor
            self.startTime = CACurrentMediaTime()
            
            // Create command queue
            guard let queue = device.makeCommandQueue() else {
                throw MetalSetupError.commandQueueCreationFailed
            }
            commandQueue = queue
            
            // Load shader library
            guard let library = device.makeDefaultLibrary() else {
                throw MetalSetupError.libraryCreationFailed
            }
            
            // Load shader functions
            guard let vertexFunction = library.makeFunction(name: "gradient_animation_vertex"),
                  let fragmentFunction = library.makeFunction(name: "gradient_animation_fragment") else {
                throw MetalSetupError.shaderFunctionNotFound
            }
            
            // Create render pipeline descriptor
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            // Create render pipeline state
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                throw MetalSetupError.pipelineStateCreationFailed
            }
            
            // Create vertex buffer (full screen quad)
            let vertices: [Float] = [
                -1.0, -1.0, 0.0,
                 1.0, -1.0, 0.0,
                -1.0,  1.0, 0.0,
                 1.0,  1.0, 0.0
            ]
            vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
            
            // Create time buffer
            var time: Float = 0.0
            timeBuffer = device.makeBuffer(bytes: &time, length: MemoryLayout<Float>.size, options: [])
            
            // Create view size buffer
            updateViewSizeBuffer(size: view.bounds.size)
            
            // Create page buffer
            var pageValue = Int32(page)
            pageBuffer = device.makeBuffer(bytes: &pageValue, length: MemoryLayout<Int32>.size, options: [])
            
            // Create custom colors buffer
            updateCustomColors(customColors)
            
            // Create background color buffer
            updateBackgroundColor(backgroundColor)
        }
        
        func updateBackgroundColor(_ color: Color?) {
            self.backgroundColor = color
            
            // Default to black if no color provided
            let bgColor = color ?? Color.black
            let uiColor = UIColor(bgColor)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
            
            let bgColorFloat = SIMD3<Float>(Float(r), Float(g), Float(b))
            // Debug: print the color values to verify it's being set
            print("🎨 [MetalGradientBackground] Setting background color: R=\(String(format: "%.3f", r)), G=\(String(format: "%.3f", g)), B=\(String(format: "%.3f", b))")
            backgroundColorBuffer = device.makeBuffer(bytes: [bgColorFloat], length: MemoryLayout<SIMD3<Float>>.size, options: [])
        }
        
        func updateCustomColors(_ colors: [Color]?) {
            self.customColors = colors
            
            // Always create the useCustomColors buffer
            var useCustom = Int32(0)
            
            if let colors = colors, colors.count >= 5 {
                // Convert SwiftUI Colors to Metal float3
                let uiColors = colors.map { UIColor($0) }
                var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
                var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
                var r3: CGFloat = 0, g3: CGFloat = 0, b3: CGFloat = 0
                var r4: CGFloat = 0, g4: CGFloat = 0, b4: CGFloat = 0
                var r5: CGFloat = 0, g5: CGFloat = 0, b5: CGFloat = 0
                
                uiColors[0].getRed(&r1, green: &g1, blue: &b1, alpha: nil)
                uiColors[1].getRed(&r2, green: &g2, blue: &b2, alpha: nil)
                uiColors[2].getRed(&r3, green: &g3, blue: &b3, alpha: nil)
                uiColors[3].getRed(&r4, green: &g4, blue: &b4, alpha: nil)
                uiColors[4].getRed(&r5, green: &g5, blue: &b5, alpha: nil)
                
                let customColorsStruct = CustomColorsStruct(
                    color1: SIMD3<Float>(Float(r1), Float(g1), Float(b1)),
                    color2: SIMD3<Float>(Float(r2), Float(g2), Float(b2)),
                    color3: SIMD3<Float>(Float(r3), Float(g3), Float(b3)),
                    color4: SIMD3<Float>(Float(r4), Float(g4), Float(b4)),
                    color5: SIMD3<Float>(Float(r5), Float(g5), Float(b5))
                )
                
                // Create buffer with proper memory management
                var structCopy = customColorsStruct
                customColorsBuffer = device.makeBuffer(bytes: &structCopy, length: MemoryLayout<CustomColorsStruct>.size, options: [])
                useCustom = Int32(1)
            } else {
                // Create a dummy buffer with zeros when not using custom colors
                var dummyStruct = CustomColorsStruct(
                    color1: SIMD3<Float>(0, 0, 0),
                    color2: SIMD3<Float>(0, 0, 0),
                    color3: SIMD3<Float>(0, 0, 0),
                    color4: SIMD3<Float>(0, 0, 0),
                    color5: SIMD3<Float>(0, 0, 0)
                )
                customColorsBuffer = device.makeBuffer(bytes: &dummyStruct, length: MemoryLayout<CustomColorsStruct>.size, options: [])
            }
            
            var useCustomCopy = useCustom
            useCustomColorsBuffer = device.makeBuffer(bytes: &useCustomCopy, length: MemoryLayout<Int32>.size, options: [])
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            updateViewSizeBuffer(size: size)
        }
        
        func updateViewSizeBuffer(size: CGSize) {
            guard size.width > 0 && size.height > 0 else { return }
            var viewSize: [Float] = [Float(size.width), Float(size.height)]
            viewSizeBuffer = device.makeBuffer(bytes: &viewSize, length: viewSize.count * MemoryLayout<Float>.size, options: [])
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPipelineState = renderPipelineState,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let viewSizeBuffer = viewSizeBuffer,
                  customColorsBuffer != nil,
                  useCustomColorsBuffer != nil else {
                // If viewSizeBuffer is nil, try to initialize it from current view bounds
                if viewSizeBuffer == nil {
                    let size = view.bounds.size
                    if size.width > 0 && size.height > 0 {
                        updateViewSizeBuffer(size: size)
                    }
                }
                return
            }
            
            // Update time
            let currentTime = CACurrentMediaTime()
            let elapsedTime = Float(currentTime - startTime)
            let timePointer = timeBuffer.contents().bindMemory(to: Float.self, capacity: 1)
            timePointer.pointee = elapsedTime
            
            // Update page if changed
            let pagePointer = pageBuffer.contents().bindMemory(to: Int32.self, capacity: 1)
            pagePointer.pointee = Int32(page)
            
            // Create command buffer
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            // Create render command encoder
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(timeBuffer, offset: 0, index: 1)
            renderEncoder.setVertexBuffer(viewSizeBuffer, offset: 0, index: 2)
            renderEncoder.setVertexBuffer(pageBuffer, offset: 0, index: 3)
            
            // Set fragment shader buffers
            if customColorsBuffer != nil {
                renderEncoder.setFragmentBuffer(customColorsBuffer, offset: 0, index: 3)
            }
            if useCustomColorsBuffer != nil {
                renderEncoder.setFragmentBuffer(useCustomColorsBuffer, offset: 0, index: 4)
            }
            // Always set background color buffer (it's always created, defaults to black if nil)
            if backgroundColorBuffer != nil {
                renderEncoder.setFragmentBuffer(backgroundColorBuffer, offset: 0, index: 5)
            } else {
                // Fallback: create black buffer if somehow not initialized
                var blackColor = SIMD3<Float>(0.0, 0.0, 0.0)
                let blackBuffer = device.makeBuffer(bytes: &blackColor, length: MemoryLayout<SIMD3<Float>>.size, options: [])
                renderEncoder.setFragmentBuffer(blackBuffer, offset: 0, index: 5)
            }
            renderEncoder.setFragmentBuffer(timeBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(viewSizeBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentBuffer(pageBuffer, offset: 0, index: 2)
            
            if let customColorsBuffer = customColorsBuffer {
                renderEncoder.setFragmentBuffer(customColorsBuffer, offset: 0, index: 3)
            }
            if let useCustomColorsBuffer = useCustomColorsBuffer {
                renderEncoder.setFragmentBuffer(useCustomColorsBuffer, offset: 0, index: 4)
            }
            if let backgroundColorBuffer = backgroundColorBuffer {
                renderEncoder.setFragmentBuffer(backgroundColorBuffer, offset: 0, index: 5)
            }
            
            // Custom colors buffers (always set, even if not using custom colors)
            // These must always be set because they're declared in the shader
            renderEncoder.setFragmentBuffer(customColorsBuffer, offset: 0, index: 3)
            renderEncoder.setFragmentBuffer(useCustomColorsBuffer, offset: 0, index: 4)
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
