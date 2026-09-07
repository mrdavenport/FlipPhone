import SwiftUI
import UIKit

#if canImport(RiveRuntime)
import RiveRuntime

// MARK: - Debug Logging Control
/// Set to true to enable verbose Rive debug logging
private let RIVE_DEBUG_LOGGING = false

/// Helper function for debug logging
private func riveLog(_ message: String) {
    if RIVE_DEBUG_LOGGING {
        print(message)
    }
}

/// Helper for important logs that should always show (errors, key events)
private func riveLogImportant(_ message: String) {
    print(message)
}

// MARK: - Simple Rive View (for splash - optimized with async ViewModel binding)
/// Optimized RiveView wrapper that does heavy work asynchronously to avoid blocking UI.
/// Follows Rive best practices: bind ViewModel in background, update colors efficiently.
struct SimpleRiveView: UIViewRepresentable {
    let fileName: String
    let artboardName: String?
    let instanceValue: Double?
    let colorInputs: [String: Color]?
    
    init(fileName: String, artboardName: String? = nil, stateMachineName: String? = nil, instanceValue: Double? = nil, colorInputs: [String: Color]? = nil) {
        self.fileName = fileName
        self.artboardName = artboardName
        self.instanceValue = instanceValue
        self.colorInputs = colorInputs
    }
    
    func makeUIView(context: Context) -> RiveView {
        // Load RiveFile synchronously (fast enough for splash, ensures immediate binding)
        var riveFile: RiveFile?
        if let url = Bundle.main.url(forResource: fileName, withExtension: "riv") {
            do {
                let data = try Data(contentsOf: url)
                riveFile = try RiveFile(data: data, loadCdn: false)
                context.coordinator.riveFile = riveFile
            } catch {
                print("❌ [SimpleRiveView] Failed to load RiveFile: \(error)")
            }
        }
        
        // Create RiveViewModel for rendering
        let viewModel: RiveViewModel
        do {
            if let artboardName = artboardName {
                viewModel = try RiveViewModel(fileName: fileName, artboardName: artboardName)
            } else {
                viewModel = try RiveViewModel(fileName: fileName)
            }
        } catch {
            print("❌ [SimpleRiveView] Failed to create RiveViewModel: \(error)")
            return RiveView()
        }
        
        let view = viewModel.createRiveView()
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel
        
        // Set instance value immediately if provided
        if let instanceValue = instanceValue {
            do {
                try viewModel.setInput("instance", value: instanceValue)
                print("✅ [SimpleRiveView] Set instance to \(instanceValue)")
            } catch {
                print("⚠️ [SimpleRiveView] Failed to set instance: \(error)")
            }
        }
        
        // Get the ACTUAL artboard from the view (the one being rendered)
        // This is critical - we must bind to the same artboard instance the view is using
        // Use the same method as RiveViewWrapper that successfully finds the artboard
        var targetArtboard: RiveArtboard?
        
        // Method 1: Get from view's riveModel (most reliable - this is what hero-view uses)
        let viewMirror = Mirror(reflecting: view)
        for child in viewMirror.children {
            if child.label == "riveModel" {
                let modelMirror = Mirror(reflecting: child.value)
                for modelChild in modelMirror.children {
                    if let artboard = modelChild.value as? RiveArtboard {
                        targetArtboard = artboard
                        print("✅ [SimpleRiveView] Found artboard via view.riveModel: '\(artboard.name())'")
                        break
                    }
                    // Check nested properties (artboard might be nested)
                    let nestedMirror = Mirror(reflecting: modelChild.value)
                    for nestedChild in nestedMirror.children {
                        if let artboard = nestedChild.value as? RiveArtboard {
                            targetArtboard = artboard
                            print("✅ [SimpleRiveView] Found artboard via nested view.riveModel: '\(artboard.name())'")
                            break
                        }
                    }
                    if targetArtboard != nil { break }
                }
                if targetArtboard != nil { break }
            }
        }
        
        // Method 2: Try viewModel's internal artboard
        if targetArtboard == nil {
            let mirror = Mirror(reflecting: viewModel)
            for child in mirror.children {
                if let artboard = child.value as? RiveArtboard {
                    targetArtboard = artboard
                    print("✅ [SimpleRiveView] Found artboard via viewModel: '\(artboard.name())'")
                    break
                }
                // Check nested properties
                let nestedMirror = Mirror(reflecting: child.value)
                for nestedChild in nestedMirror.children {
                    if let artboard = nestedChild.value as? RiveArtboard {
                        targetArtboard = artboard
                        print("✅ [SimpleRiveView] Found artboard via nested viewModel: '\(artboard.name())'")
                        break
                    }
                }
                if targetArtboard != nil { break }
            }
        }
        
        // Bind ViewModel and colors BEFORE starting animation
        // This ensures colors are applied before the animation plays
        if let artboard = targetArtboard, let riveFile = riveFile {
            coordinator.activeArtboard = artboard
            
            // Get ViewModel definition
            let viewModelNames = ["Hero", "ViewModel1", "View Model 1"]
            var viewModelDef: RiveDataBindingViewModel?
            
            for vmName in viewModelNames {
                if let vm = riveFile.viewModelNamed(vmName) {
                    viewModelDef = vm
                    break
                }
            }
            
            if viewModelDef == nil && riveFile.viewModelCount > 0 {
                viewModelDef = try? riveFile.viewModel(at: 0)
            }
            
            if let vmDef = viewModelDef, let instance = vmDef.createDefaultInstance() {
                coordinator.viewModelInstance = instance
                
                // Bind instance to the ACTUAL artboard being rendered
                artboard.bind(viewModelInstance: instance)
                
                // Set colors IMMEDIATELY before animation starts
                if let colorInputs = colorInputs {
                    for (inputName, color) in colorInputs {
                        if let colorProperty = instance.colorProperty(fromPath: inputName) {
                            colorProperty.value = UIColor(color)
                            print("✅ [SimpleRiveView] Set color '\(inputName)' to theme color (BEFORE animation)")
                        } else {
                            print("⚠️ [SimpleRiveView] Color property '\(inputName)' not found")
                        }
                    }
                }
                
                // Advance artboard multiple times to ensure data binding applies
                artboard.advance(by: 0.016)
                artboard.advance(by: 0.0)
                
                print("✅ [SimpleRiveView] ViewModel bound to artboard '\(artboard.name())' and colors set BEFORE animation")
                
                // Start animation AFTER colors are bound
                viewModel.play()
                
                // Force view to redraw with correct colors
                view.setNeedsDisplay()
            } else {
                print("⚠️ [SimpleRiveView] Could not create ViewModel instance")
                // Start animation anyway (without colors)
                viewModel.play()
            }
        } else {
            print("⚠️ [SimpleRiveView] Could not find artboard from viewModel (will retry in updateUIView)")
            // Start animation anyway (colors will be set in updateUIView)
            viewModel.play()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: RiveView, context: Context) {
        let coordinator = context.coordinator
        
        // If ViewModel not bound yet, try to bind now (fallback)
        if coordinator.viewModelInstance == nil, let riveFile = coordinator.riveFile, let viewModel = coordinator.viewModel {
            // Get artboard using same method
            var targetArtboard: RiveArtboard?
            
            // Method 1: Get from view's riveModel
            let viewMirror = Mirror(reflecting: uiView)
            for child in viewMirror.children {
                if child.label == "riveModel" {
                    let modelMirror = Mirror(reflecting: child.value)
                    for modelChild in modelMirror.children {
                        if let artboard = modelChild.value as? RiveArtboard {
                            targetArtboard = artboard
                            break
                        }
                        let nestedMirror = Mirror(reflecting: modelChild.value)
                        for nestedChild in nestedMirror.children {
                            if let artboard = nestedChild.value as? RiveArtboard {
                                targetArtboard = artboard
                                break
                            }
                        }
                        if targetArtboard != nil { break }
                    }
                    if targetArtboard != nil { break }
                }
            }
            
            if let artboard = targetArtboard {
                coordinator.activeArtboard = artboard
                
                // Get ViewModel definition
                let viewModelNames = ["Hero", "ViewModel1", "View Model 1"]
                var viewModelDef: RiveDataBindingViewModel?
                
                for vmName in viewModelNames {
                    if let vm = riveFile.viewModelNamed(vmName) {
                        viewModelDef = vm
                        break
                    }
                }
                
                if viewModelDef == nil && riveFile.viewModelCount > 0 {
                    viewModelDef = try? riveFile.viewModel(at: 0)
                }
                
                if let vmDef = viewModelDef, let instance = vmDef.createDefaultInstance() {
                    coordinator.viewModelInstance = instance
                    artboard.bind(viewModelInstance: instance)
                    
                    // Set colors immediately
                    if let colorInputs = colorInputs {
                        for (inputName, color) in colorInputs {
                            if let colorProperty = instance.colorProperty(fromPath: inputName) {
                                colorProperty.value = UIColor(color)
                                print("✅ [SimpleRiveView] Set color '\(inputName)' in updateUIView")
                            }
                        }
                    }
                    
                    artboard.advance(by: 0.016)
                    artboard.advance(by: 0.0)
                    uiView.setNeedsDisplay()
                    print("✅ [SimpleRiveView] ViewModel bound in updateUIView")
                }
                return
            }
        }
        
        // Update colors if ViewModel is bound
        if let instance = coordinator.viewModelInstance,
           let artboard = coordinator.activeArtboard,
           let colorInputs = colorInputs {
            
            // Update colors (always update to ensure they're current)
            for (inputName, newColor) in colorInputs {
                if let colorProperty = instance.colorProperty(fromPath: inputName) {
                    let newUIColor = UIColor(newColor)
                    colorProperty.value = newUIColor
                }
            }
            
            // Advance artboard to apply changes
            artboard.advance(by: 0.016)
            uiView.setNeedsDisplay()
        }
        
        // Store last colors
        coordinator.lastColorInputs = colorInputs
    }
    
    static func dismantleUIView(_ uiView: RiveView, coordinator: Coordinator) {
        // Let ARC handle cleanup
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var viewModel: RiveViewModel?
        var riveFile: RiveFile?
        var viewModelInstance: RiveDataBindingViewModel.Instance?
        var activeArtboard: RiveArtboard?
        var lastColorInputs: [String: Color]?
    }
}

// MARK: - Full-Featured Rive View (for persistent views like hero)
struct RiveViewWrapper: UIViewRepresentable {
    let fileName: String
    let autoPlay: Bool
    let stateName: String?  // Optional: name of the state machine state or artboard to use
    let animationName: String?  // Optional: name of specific animation to play
    let uniqueId: String  // Unique identifier to prevent view reuse
    let textInputs: [String: String]?  // Optional: dictionary of text input names to values
    let artboardName: String?  // Optional: specific artboard name to use (for data binding artboard property)
    let instanceValue: Double?  // Optional: instance number to set (overrides stateName-based instance)
    let colorInputs: [String: Color]?  // Optional: dictionary of color input names to Color values
    let numberInputs: [String: Double]?  // Optional: dictionary of number property names to values (for converters)
    let boolInputs: [String: Bool]?  // Optional: dictionary of boolean property names to values
    let artboardInputs: [String: String]?  // Optional: dictionary of artboard property names to artboard names (for data binding)
    let triggerInputs: [String]?  // Optional: trigger names to fire after binding (e.g. "levelUp" when transitioning between badges)
    /// When this value changes (e.g. hero screen shown again), fire `currentTriggerInputs` even if number inputs are unchanged.
    let triggerReloadNonce: Int?
    
    init(fileName: String, autoPlay: Bool = true, stateName: String? = nil, animationName: String? = nil, uniqueId: String = UUID().uuidString, textInputs: [String: String]? = nil, artboardName: String? = nil, instanceValue: Double? = nil, colorInputs: [String: Color]? = nil, numberInputs: [String: Double]? = nil, boolInputs: [String: Bool]? = nil, artboardInputs: [String: String]? = nil, triggerInputs: [String]? = nil, triggerReloadNonce: Int? = nil) {
        self.fileName = fileName
        self.autoPlay = autoPlay
        self.stateName = stateName
        self.animationName = animationName
        self.uniqueId = uniqueId
        self.textInputs = textInputs
        self.artboardName = artboardName
        self.instanceValue = instanceValue
        self.colorInputs = colorInputs
        self.numberInputs = numberInputs
        self.boolInputs = boolInputs
        self.artboardInputs = artboardInputs
        self.triggerInputs = triggerInputs
        self.triggerReloadNonce = triggerReloadNonce
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(fileName: fileName, stateName: stateName, animationName: animationName, artboardName: artboardName)
        coordinator.uniqueId = uniqueId
        coordinator.instanceValue = instanceValue
        // Set text inputs if provided
        if let textInputs = textInputs {
            coordinator.setTextInputs(textInputs)
            // Persist so setRiveView() can apply after artboard exists
            coordinator.currentTextInputs = textInputs
        }
        // Set color inputs if provided
        if let colorInputs = colorInputs {
            print("🎨 [DEBUG] colorInputs provided: \(colorInputs.keys.joined(separator: ", "))")
            coordinator.setColorInputs(colorInputs)
            // Persist so setRiveView() can apply after artboard exists
            coordinator.currentColorInputs = colorInputs
        } else {
            print("🎨 [DEBUG] colorInputs is nil - no color binding")
        }
        // Set number inputs if provided
        if let numberInputs = numberInputs {
            print("🔢 [DEBUG] numberInputs provided: \(numberInputs.keys.sorted().joined(separator: ", "))")
            coordinator.setNumberInputs(numberInputs)
            // Persist so setRiveView() can apply after artboard exists
            coordinator.currentNumberInputs = numberInputs
        }
        // Set boolean inputs if provided
        if let boolInputs = boolInputs {
            coordinator.setBoolInputs(boolInputs)
            coordinator.currentBoolInputs = boolInputs
        }
        // Set artboard inputs if provided
        if let artboardInputs = artboardInputs {
            coordinator.setArtboardInputs(artboardInputs)
            coordinator.currentArtboardInputs = artboardInputs
        }
        // Set trigger inputs if provided (e.g. ["levelUp"] to fire on milestone transition)
        if let triggerInputs = triggerInputs {
            // IMPORTANT: Do NOT fire triggers here (no artboard yet).
            coordinator.currentTriggerInputs = triggerInputs
        }
        // Debug: List available artboards (useful for development)
        coordinator.debugArtboards()
        return coordinator
    }
    
    func makeUIView(context: Context) -> RiveView {
        let timestamp = Date().timeIntervalSince1970
        riveLog("🟢 [\(context.coordinator.uniqueId)] makeUIView() START - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
        riveLog("🎬 Attempting to load Rive file: \(fileName).riv")
        
        // Verify file exists in bundle
        guard Bundle.main.url(forResource: fileName, withExtension: "riv") != nil else {
            print("⚠️ Rive file not found in bundle: \(fileName).riv")
            print("📦 Bundle path: \(Bundle.main.bundlePath)")
            if let resourcePath = Bundle.main.resourcePath {
                print("📁 Resource path: \(resourcePath)")
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                    let rivFiles = contents.filter { $0.contains(".riv") }
                    riveLog("📋 Rive files in bundle: \(rivFiles)")
                }
            }
            return RiveView()
        }
        
        print("✅ Found Rive file in bundle: \(fileName).riv")
        
        // If artboardName is specified, we need to ensure the view uses that artboard
        // The RiveViewModel might need to be created with the artboard, or we need to
        // manually set the artboard after view creation
        let view: RiveView
        
        // Use viewModel from coordinator
        guard let viewModel = context.coordinator.viewModel else {
            print("⚠️ Failed to create RiveViewModel")
            return RiveView()
        }
        
        riveLog("🟢 [\(context.coordinator.uniqueId)] About to create RiveView...")
        view = viewModel.createRiveView()
        riveLog("🟢 [\(context.coordinator.uniqueId)] RiveView created successfully")
        
        // If artboardName is specified, try to set it on the view after creation
        if let artboardName = artboardName {
            riveLog("🎯 Artboard name specified: '\(artboardName)' - will set after view creation")
            // The artboard will be set via the coordinator's activeArtboard
            // which is loaded from the file in setRiveView
        }
        
        // Store reference to view in coordinator for state control
        riveLog("🟢 [\(context.coordinator.uniqueId)] About to call setRiveView()...")
        context.coordinator.setRiveView(view)
        riveLog("🟢 [\(context.coordinator.uniqueId)] setRiveView() completed")
        
        // Set instance value first (if provided), then set state
        // This ensures the instance is set before the state machine evaluates
        if let instanceValue = instanceValue {
            riveLog("🎬 Creating RiveView [\(context.coordinator.uniqueId)] - setting instance to \(instanceValue)")
            // Delay to ensure view is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let timestamp = Date().timeIntervalSince1970
                riveLog("🟡 [\(context.coordinator.uniqueId)] Instance value async block START - Time: \(String(format: "%.3f", timestamp))")
                riveLog("🟡 [\(context.coordinator.uniqueId)] Async block: About to set instance value...")
                context.coordinator.setInstanceValue(instanceValue)
                riveLog("🟡 [\(context.coordinator.uniqueId)] Async block: Instance value set completed")
                let endTimestamp = Date().timeIntervalSince1970
                riveLog("🟡 [\(context.coordinator.uniqueId)] Instance value async block END - Time: \(String(format: "%.3f", endTimestamp))")
            }
        }
        
        // Set the state immediately when view is created
        if let stateName = stateName {
            riveLog("🎬 Creating RiveView [\(context.coordinator.uniqueId)] with state: '\(stateName)'")
            // Delay slightly to ensure view is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let timestamp = Date().timeIntervalSince1970
                riveLog("🟡 [\(context.coordinator.uniqueId)] State async block START - Time: \(String(format: "%.3f", timestamp))")
                riveLog("🟡 [\(context.coordinator.uniqueId)] Async block: About to set state '\(stateName)'...")
                context.coordinator.setState(stateName)
                riveLog("🟡 [\(context.coordinator.uniqueId)] Async block: State set completed")
                let endTimestamp = Date().timeIntervalSince1970
                riveLog("🟡 [\(context.coordinator.uniqueId)] State async block END - Time: \(String(format: "%.3f", endTimestamp))")
            }
        }
        
        riveLog("🟢 [\(context.coordinator.uniqueId)] makeUIView() END - returning view")
        return view
    }
    
    func updateUIView(_ uiView: RiveView, context: Context) {
        let timestamp = Date().timeIntervalSince1970
        riveLog("🟠 [\(context.coordinator.uniqueId)] updateUIView() called - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
        let coordinator = context.coordinator
        
        // If ViewModel binding wasn't done yet, do it now that the view is in the hierarchy
        // Try to find artboard if not already found
        if coordinator.activeArtboard == nil {
            // Try to find artboard through reflection
            let mirror = Mirror(reflecting: uiView)
            if let riveModel = mirror.children.first(where: { $0.label == "riveModel" })?.value {
                let modelMirror = Mirror(reflecting: riveModel)
                for child in modelMirror.children {
                    let nestedMirror = Mirror(reflecting: child.value)
                    for nestedChild in nestedMirror.children {
                        if let artboard = nestedChild.value as? RiveArtboard {
                            coordinator.activeArtboard = artboard
                            riveLog("✅ [\(coordinator.uniqueId)] Found active artboard in updateUIView: '\(artboard.name())'")
                            break
                        }
                    }
                }
            }
        }
        
        // Bind ViewModel only to the VIEW's artboard (from reflection). Never bind to a file-created artboard — that one isn't drawn.
        if coordinator.viewModelInstance == nil,
           let riveFile = coordinator.riveFile,
           let artboard = coordinator.activeArtboard {
                // Bind immediately - this enables both data binding AND scripting
                riveLog("🟠 [\(coordinator.uniqueId)] Binding ViewModel immediately...")
                coordinator.bindViewModelInstance(artboard: artboard, riveFile: riveFile)
                riveLog("🟠 [\(coordinator.uniqueId)] ViewModel binding complete")
                
                if let colorInputs = colorInputs {
                    riveLog("🎨 [\(coordinator.uniqueId)] Setting color inputs after ViewModel binding...")
                    coordinator.setColorInputs(colorInputs)
                }
                if let numberInputs = numberInputs {
                    riveLog("🔢 [\(coordinator.uniqueId)] Setting number inputs after ViewModel binding...")
                    coordinator.setNumberInputs(numberInputs)
                }
        }
        
        // Update state if it changed
        
        // Update instance value if it changed
        if let instanceValue = instanceValue, coordinator.instanceValue != instanceValue {
            coordinator.instanceValue = instanceValue
            coordinator.setInstanceValue(instanceValue)
        }
        
        // Only update state if it changed
        if let stateName = stateName, coordinator.currentStateName != stateName {
            coordinator.setState(stateName)
        }
        
        // If animation name changed, play it
        if let animationName = animationName, coordinator.currentAnimationName != animationName {
            coordinator.playAnimation(animationName)
        }
        
        // Update text inputs if they changed
        if let textInputs = textInputs {
            // Check if any text input value has changed
            var hasChanged = false
            if let current = coordinator.currentTextInputs {
                // Compare each value
                for (key, newValue) in textInputs {
                    if current[key] != newValue {
                        hasChanged = true
                        break
                    }
                }
                // Also check if any keys were removed
                if !hasChanged && current.count != textInputs.count {
                    hasChanged = true
                }
            } else {
                // First time setting text inputs
                hasChanged = true
            }
            
            if hasChanged {
                coordinator.setTextInputs(textInputs)
                coordinator.currentTextInputs = textInputs
            }
        } else if coordinator.currentTextInputs != nil {
            // Text inputs were removed
            coordinator.currentTextInputs = nil
        }
        
        // Update color inputs - always re-apply to override any Rive animation/state that may change them
        // (e.g. flipphone_logo sessionResults state switches arrow color to default ~1s in)
        if let colorInputs = colorInputs {
            coordinator.setColorInputs(colorInputs)
            coordinator.currentColorInputs = colorInputs
        } else if coordinator.currentColorInputs != nil {
            // Color inputs were removed
            coordinator.currentColorInputs = nil
        }
        
        // Update number inputs if they changed
        if let numberInputs = numberInputs {
            // Check if any number input value has changed
            var hasChanged = false
            if let current = coordinator.currentNumberInputs {
                // Compare each value
                for (key, newValue) in numberInputs {
                    if let currentValue = current[key] {
                        if abs(currentValue - newValue) > 0.001 { // Allow small floating point differences
                            hasChanged = true
                            break
                        }
                    } else {
                        hasChanged = true
                        break
                    }
                }
                // Also check if any keys were removed
                if !hasChanged && current.count != numberInputs.count {
                    hasChanged = true
                }
            } else {
                // First time setting number inputs
                hasChanged = true
            }
            
            if hasChanged {
                coordinator.setNumberInputs(numberInputs)
                coordinator.currentNumberInputs = numberInputs
                // Fire triggers when number inputs change (e.g. levelUp when tier/milestone numbers change) so the same Rive view can transition smoothly.
                if let triggerInputs = triggerInputs, !triggerInputs.isEmpty {
                    coordinator.currentTriggerInputs = triggerInputs
                    coordinator.fireTriggerInputs()
                }
            }
        } else if coordinator.currentNumberInputs != nil {
            // Number inputs were removed
            coordinator.currentNumberInputs = nil
        }
        
        // Update boolean inputs if they changed
        if let boolInputs = boolInputs {
            // Check if any boolean input value has changed
            var hasChanged = false
            if let current = coordinator.currentBoolInputs {
                // Compare each value
                for (key, newValue) in boolInputs {
                    if let currentValue = current[key] {
                        if currentValue != newValue {
                            hasChanged = true
                            break
                        }
                    } else {
                        hasChanged = true
                        break
                    }
                }
                // Also check if any keys were removed
                if !hasChanged && current.count != boolInputs.count {
                    hasChanged = true
                }
            } else {
                // First time setting boolean inputs
                hasChanged = true
            }
            
            if hasChanged {
                coordinator.setBoolInputs(boolInputs)
                coordinator.currentBoolInputs = boolInputs
            }
        } else if coordinator.currentBoolInputs != nil {
            // Boolean inputs were removed
            coordinator.currentBoolInputs = nil
        }
        
        // Update artboard inputs if they changed
        if let artboardInputs = artboardInputs {
            // Check if any artboard input value has changed
            var hasChanged = false
            if let current = coordinator.currentArtboardInputs {
                // Compare each value
                for (key, newValue) in artboardInputs {
                    if let currentValue = current[key] {
                        if currentValue != newValue {
                            hasChanged = true
                            break
                        }
                    } else {
                        hasChanged = true
                        break
                    }
                }
                // Also check if any keys were removed
                if !hasChanged && current.count != artboardInputs.count {
                    hasChanged = true
                }
            } else {
                // First time setting artboard inputs
                hasChanged = true
            }
            
            if hasChanged {
                coordinator.setArtboardInputs(artboardInputs)
                coordinator.currentArtboardInputs = artboardInputs
            }
        } else if coordinator.currentArtboardInputs != nil {
            // Artboard inputs were removed
            coordinator.currentArtboardInputs = nil
        }

        // Update trigger inputs if they changed (e.g. ["levelUp"])
        if let triggerInputs = triggerInputs {
            if coordinator.currentTriggerInputs != triggerInputs {
                coordinator.setTriggerInputs(triggerInputs)
            }
        } else {
            coordinator.currentTriggerInputs = nil
        }

        // Re-fire triggers when the host bumps `triggerReloadNonce` (hero visible again; inputs unchanged).
        if let nonce = triggerReloadNonce, nonce > 0, coordinator.lastTriggerReloadNonce != nonce {
            coordinator.lastTriggerReloadNonce = nonce
            coordinator.fireTriggerInputs()
            // Rive sometimes misses the first fire if the view just laid out or was alpha-0; a short delayed refire is cheap.
            let c = coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                c.fireTriggerInputs()
            }
        }
        
        // SwiftUI handles layout automatically - no need for async layout calls
        // (Removing async block as it can cause crashes when view is dismantled before block runs)
        let endTimestamp = Date().timeIntervalSince1970
        riveLog("🟠 [\(context.coordinator.uniqueId)] updateUIView() END - Time: \(String(format: "%.3f", endTimestamp))")
    }
    
    static func dismantleUIView(_ uiView: RiveView, coordinator: Coordinator) {
        let timestamp = Date().timeIntervalSince1970
        riveLog("🔴 [\(coordinator.uniqueId)] dismantleUIView() - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
        // Pause animation BEFORE deallocation to prevent [RiveArtboard dealloc] crash.
        // The crash occurs when the Rive render loop (CADisplayLink) is still ticking
        // as the artboard is being released — pausing stops the loop cleanly.
        coordinator.viewModel?.pause()
        // Do NOT nil out references here — let ARC handle cleanup naturally after pause.
    }
    
    class Coordinator {
        var viewModel: RiveViewModel?
        var riveView: RiveView?
        var riveFile: RiveFile?
        var currentStateName: String?
        var currentAnimationName: String?
        var uniqueId: String = ""
        let fileName: String
        var artboardName: String? // Store artboard name if specified
        var instanceValue: Double? // Store instance value if specified
        var currentTextInputs: [String: String]? // Track current text inputs to detect changes
        var currentColorInputs: [String: Color]? // Track current color inputs to detect changes
        var currentNumberInputs: [String: Double]? // Track current number inputs to detect changes
        var currentBoolInputs: [String: Bool]? // Track current boolean inputs to detect changes
        var currentArtboardInputs: [String: String]? // Track current artboard inputs to detect changes
        var currentTriggerInputs: [String]? // Trigger names to fire (e.g. "levelUp")
        var lastTriggerReloadNonce: Int?
        var activeArtboard: RiveArtboard? // Store reference to the artboard being displayed
        var lastBoundArtboardName: String? // Fallback heuristic (human-readable)
        var lastBoundArtboardObjectId: ObjectIdentifier? // Correct heuristic for stale binding
        var viewModelInstance: RiveDataBindingViewModel.Instance? // Store view model instance (strong reference required)

        deinit {
            // Swift releases stored properties in REVERSE declaration order.
            // viewModelInstance (declared last) would normally be released BEFORE activeArtboard,
            // but the C++ ArtboardInstance destructor accesses the bound ViewModelInstance
            // during cleanup — producing EXC_BAD_ACCESS (address=0x8) if the instance is
            // already gone. Explicitly nil activeArtboard first so its C++ dealloc runs
            // while viewModelInstance is still alive.
            activeArtboard = nil
            viewModelInstance = nil
        }
        
        init(fileName: String, stateName: String?, animationName: String?, artboardName: String?) {
            self.fileName = fileName
            self.artboardName = artboardName

            if let stateName = stateName {
                self.currentStateName = stateName
            }

            // Load the Rive file ONCE and share it between the RiveModel (used by RiveViewModel
            // for rendering) and self.riveFile (used for data-binding helpers like viewModelNamed).
            // Previously the file was loaded twice — once manually and once inside RiveViewModel(fileName:) —
            // blocking the main thread for ~500 ms on a 6 MB file.
            //
            // If RivePrewarmCache already has the data (pre-loaded during the splash screen),
            // the expensive Data(contentsOf:) disk read is skipped entirely.
            if let url = Bundle.main.url(forResource: fileName, withExtension: "riv") {
                do {
                    // Use pre-warmed data when available so the disk read is skipped.
                    // Cannot use ?? with try inline, so branch explicitly.
                    let data: Data
                    if let cached = RivePrewarmCache.shared.getData(for: fileName) {
                        data = cached
                    } else {
                        data = try Data(contentsOf: url)
                    }
                    let riveFile = try RiveFile(data: data, loadCdn: false)
                    self.riveFile = riveFile
                    print("✅ Loaded RiveFile in Coordinator for '\(fileName)'")

                    let resolvedArtboard = self.resolvedArtboardName(in: riveFile)
                    let model = RiveModel(riveFile: riveFile)
                    self.viewModel = RiveViewModel(model, stateMachineName: nil, artboardName: resolvedArtboard)
                    print("✅ Created RiveViewModel from RiveFile for '\(fileName)' artboard: '\(resolvedArtboard ?? "default")'")
                } catch {
                    print("⚠️ Failed to load RiveFile for '\(fileName)': \(error) — falling back to fileName init")
                    // Avoid passing a possibly-invalid artboard name: RiveViewModel uses `try!` internally.
                    self.viewModel = RiveViewModel(fileName: fileName)
                    print("✅ Created RiveViewModel (fallback fileName init) for '\(fileName)'")
                }
            }
        }
        
        func setRiveView(_ view: RiveView) {
            let timestamp = Date().timeIntervalSince1970
            riveLog("🔵 [\(uniqueId)] setRiveView() START - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
            self.riveView = view
            riveLog("🔵 [\(uniqueId)] View reference stored")
            // Now that we have the view, try to set the state
            if let stateName = currentStateName {
                riveLog("🔵 [\(uniqueId)] Setting initial state: '\(stateName)'")
                setState(stateName)
                riveLog("🔵 [\(uniqueId)] Initial state set completed")
            }
            
            // IMPORTANT: Try to access the artboard from the RiveView
            // This is the artboard instance that's actually being displayed
            // The RiveView should have access to the active artboard
            // Common patterns: view.artboard, view.getArtboard(), view.riveArtboard
            // Note: The exact API may vary - we'll try to access it when setting text
            
            // Try to find the active artboard through reflection now that we have the view
            riveLog("🔍 [\(uniqueId)] Searching for active artboard through RiveView reflection...")
            let mirror = Mirror(reflecting: view)
            var foundArtboard = false
            
            // First, try to access riveModel directly (we saw this in the reflection output)
            if let riveModel = mirror.children.first(where: { $0.label == "riveModel" })?.value {
                riveLog("   Found riveModel, checking for artboard...")
                let modelMirror = Mirror(reflecting: riveModel)
                for child in modelMirror.children {
                    riveLog("     Checking riveModel property: \(child.label ?? "unnamed")")
                    if let artboard = child.value as? RiveArtboard {
                        self.activeArtboard = artboard
                        print("✅ [\(uniqueId)] Found active artboard through riveModel: '\(artboard.name())'")
                        foundArtboard = true
                        break
                    }
                    // Also check nested properties (artboard might be nested)
                    let nestedMirror = Mirror(reflecting: child.value)
                    for nestedChild in nestedMirror.children {
                        if let artboard = nestedChild.value as? RiveArtboard {
                            self.activeArtboard = artboard
                            print("✅ [\(uniqueId)] Found active artboard through nested riveModel property: '\(artboard.name())'")
                            foundArtboard = true
                            break
                        }
                    }
                    if foundArtboard { break }
                }
            }
            
            // Also try through viewModel's riveModel
            if !foundArtboard, let viewModel = viewModel {
                riveLog("🔍 [\(uniqueId)] Searching for active artboard through RiveViewModel reflection...")
                let viewModelMirror = Mirror(reflecting: viewModel)
                
                // Try riveModel property
                if let riveModel = viewModelMirror.children.first(where: { $0.label == "riveModel" })?.value {
                    riveLog("   Found riveModel in viewModel, checking for artboard...")
                    let modelMirror = Mirror(reflecting: riveModel)
                    for child in modelMirror.children {
                        riveLog("     Checking viewModel.riveModel property: \(child.label ?? "unnamed")")
                        if let artboard = child.value as? RiveArtboard {
                            self.activeArtboard = artboard
                            print("✅ [\(uniqueId)] Found active artboard through viewModel.riveModel: '\(artboard.name())'")
                            foundArtboard = true
                            break
                        }
                        // Also check nested properties
                        let nestedMirror = Mirror(reflecting: child.value)
                        for nestedChild in nestedMirror.children {
                            if let artboard = nestedChild.value as? RiveArtboard {
                                self.activeArtboard = artboard
                                print("✅ [\(uniqueId)] Found active artboard through nested viewModel.riveModel property: '\(artboard.name())'")
                                foundArtboard = true
                                break
                            }
                        }
                        if foundArtboard { break }
                    }
                }
                
                // Try defaultModel property
                if !foundArtboard, let defaultModel = viewModelMirror.children.first(where: { $0.label == "defaultModel" })?.value {
                    riveLog("   Found defaultModel, checking for artboard...")
                    let modelMirror = Mirror(reflecting: defaultModel)
                    for child in modelMirror.children {
                        if let artboard = child.value as? RiveArtboard {
                            self.activeArtboard = artboard
                            print("✅ [\(uniqueId)] Found active artboard through defaultModel: '\(artboard.name())'")
                            foundArtboard = true
                            break
                        }
                    }
                }
            }
            
            if !foundArtboard {
                print("⚠️ [\(uniqueId)] Could not find active artboard through reflection - will use file artboard")
            }

            // Bind ViewModel to the VIEW's artboard immediately so data binding (number inputs, themeColor) works
            if let artboard = self.activeArtboard, let file = self.riveFile, self.viewModelInstance == nil {
                riveLog("🔗 [\(uniqueId)] Binding ViewModel to view artboard in setRiveView...")
                bindViewModelInstance(artboard: artboard, riveFile: file)
            }

            // CRITICAL: Set instance BEFORE applying number inputs / firing triggers.
            // Many Rive files gate visibility/logic on the instance value.
            if let instanceValue = self.instanceValue {
                self.setInstanceValue(instanceValue)
            }
            
            // If we have text inputs, set them now that we have the view and artboard
            // The active artboard should now be found through reflection
            if let textInputs = currentTextInputs {
                // Try immediately - the active artboard should be found now
                riveLog("🔄 [\(self.uniqueId)] Setting text inputs after view initialization...")
                self.setTextInputs(textInputs)
                
                // Also try after a short delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    riveLog("🔄 [\(self.uniqueId)] Setting text inputs after 0.3s delay (ensuring binding is applied)...")
                    self.setTextInputs(textInputs)
                }
            }
            
            // If we have color inputs, set them now that we have the view and artboard
            if let colorInputs = currentColorInputs {
                // Try immediately - the active artboard should be found now
                riveLog("🎨 [\(self.uniqueId)] Setting color inputs after view initialization...")
                self.setColorInputs(colorInputs)
                
                // Rive quirk: state/instance may still be applying shortly after initialization
                // (e.g. instance async + state async). Re-apply around that window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    riveLog("🎨 [\(self.uniqueId)] Re-applying color inputs after 0.18s (state/instance settling)...")
                    self.setColorInputs(colorInputs)
                    self.viewModel?.play()
                    self.riveView?.setNeedsDisplay()
                    self.riveView?.setNeedsLayout()
                }
                
                // Also try after a short delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    riveLog("🎨 [\(self.uniqueId)] Setting color inputs after 0.3s delay (ensuring binding is applied)...")
                    self.setColorInputs(colorInputs)
                }
                // Re-apply at 1s to override Rive animation that may switch arrow color (e.g. sessionResults state)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.setColorInputs(colorInputs)
                }
            }
            
            // If we have number inputs, set them now that we have the view and artboard
            if let numberInputs = currentNumberInputs {
                // Try immediately - the active artboard should be found now
                print("🔢 [\(self.uniqueId)] Setting number inputs after view initialization...")
                self.setNumberInputs(numberInputs)
                
                // Also try after a short delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("🔢 [\(self.uniqueId)] Setting number inputs after 0.3s delay (ensuring binding is applied)...")
                    self.setNumberInputs(numberInputs)
                }
            } else {
                print("⚠️ [\(self.uniqueId)] No number inputs present at view initialization")
            }
            
            // If we have boolean inputs, set them now that we have the view and artboard
            if let boolInputs = currentBoolInputs {
                // Try immediately - the active artboard should be found now
                riveLog("🔘 [\(self.uniqueId)] Setting boolean inputs after view initialization...")
                self.setBoolInputs(boolInputs)
                
                // Also try after a short delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    riveLog("🔘 [\(self.uniqueId)] Setting boolean inputs after 0.3s delay (ensuring binding is applied)...")
                    self.setBoolInputs(boolInputs)
                }
            }
            
            // If we have artboard inputs, set them now that we have the view and artboard
            if let artboardInputs = currentArtboardInputs {
                // Try immediately - the active artboard should be found now
                riveLog("🎯 [\(self.uniqueId)] Setting artboard inputs after view initialization...")
                self.setArtboardInputs(artboardInputs)
                
                // Also try after a short delay to ensure everything is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    riveLog("🎯 [\(self.uniqueId)] Setting artboard inputs after 0.3s delay (ensuring binding is applied)...")
                    self.setArtboardInputs(artboardInputs)
                }
            }
            
            let endTimestamp = Date().timeIntervalSince1970
            riveLog("🔵 [\(uniqueId)] setRiveView() END - Time: \(String(format: "%.3f", endTimestamp))")
        }
        
        // Helper method to bind ViewModel instance (called with delay to avoid interfering with animation)
        func bindViewModelInstance(artboard: RiveArtboard, riveFile: RiveFile) {
            let timestamp = Date().timeIntervalSince1970
            riveLog("🟣 [\(self.uniqueId)] bindViewModelInstance() START - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
            guard self.viewModelInstance == nil else {
                riveLog("🔗 [\(self.uniqueId)] ViewModel instance already bound, skipping")
                return
            }
            
            riveLog("🔗 [\(self.uniqueId)] Setting ViewModel instance on artboard '\(artboard.name())'...")
            
            // Get the ViewModel from the RiveFile
            let viewModelCount = riveFile.viewModelCount
            riveLog("🔍 [\(self.uniqueId)] Found \(viewModelCount) ViewModel(s) in file")
            
            // Prefer "Hero" (Rive-renamed), then legacy names, so number/color/trigger inputs bind to the correct instance
            let preferredNames = ["Hero", "View Model 1", "ViewModel1"]
            var viewModelFound = false
            for vmName in preferredNames {
                if let viewModel = riveFile.viewModelNamed(vmName), !viewModelFound {
                    riveLog("   Using ViewModel '\(vmName)' for data binding")
                    let instanceCount = viewModel.instanceCount
                    riveLog("   ViewModel '\(vmName)' has \(instanceCount) instance(s)")
                    if let instance = viewModel.createDefaultInstance() {
                        self.viewModelInstance = instance
                        riveLog("🔗 [\(self.uniqueId)] Attempting to bind ViewModel instance...")
                        riveLog("🟣 [\(self.uniqueId)] About to call artboard.bind(viewModelInstance:)...")
                        artboard.bind(viewModelInstance: instance)
                        self.lastBoundArtboardName = artboard.name()
                        self.lastBoundArtboardObjectId = ObjectIdentifier(artboard)
                        riveLog("🟣 [\(self.uniqueId)] artboard.bind() call completed")
                        artboard.advance(by: 0.016)
                        artboard.advance(by: 0.0)
                        if let viewModel = self.viewModel { viewModel.play() }
                        print("✅ [\(self.uniqueId)] ViewModel '\(vmName)' default instance bound to artboard")
                        viewModelFound = true
                        break
                    }
                }
            }
            if !viewModelFound {
                for i in 0..<viewModelCount {
                    if let viewModel = try? riveFile.viewModel(at: i) {
                        let viewModelName = viewModel.name
                        riveLog("   ViewModel \(i): '\(viewModelName)' (fallback)")
                        if let instance = viewModel.createDefaultInstance() {
                            self.viewModelInstance = instance
                            artboard.bind(viewModelInstance: instance)
                            self.lastBoundArtboardName = artboard.name()
                            self.lastBoundArtboardObjectId = ObjectIdentifier(artboard)
                            artboard.advance(by: 0.016)
                            artboard.advance(by: 0.0)
                            self.viewModel?.play()
                            print("✅ [\(self.uniqueId)] ViewModel '\(viewModelName)' default instance bound (fallback)")
                            viewModelFound = true
                            break
                        } else if let instance = viewModel.createInstance(fromName: "default") {
                            self.viewModelInstance = instance
                            artboard.bind(viewModelInstance: instance)
                            self.lastBoundArtboardName = artboard.name()
                            self.lastBoundArtboardObjectId = ObjectIdentifier(artboard)
                            artboard.advance(by: 0.016)
                            artboard.advance(by: 0.0)
                            self.viewModel?.play()
                            print("✅ [\(self.uniqueId)] ViewModel '\(viewModelName)' instance 'default' bound (fallback)")
                            viewModelFound = true
                            break
                        }
                    }
                }
            }
            
            if !viewModelFound {
                print("⚠️ [\(self.uniqueId)] Could not find or bind ViewModel instance")
            } else {
                print("✅ [\(self.uniqueId)] ViewModel instance successfully bound")
            }
            let endTimestamp = Date().timeIntervalSince1970
            riveLog("🟣 [\(self.uniqueId)] bindViewModelInstance() END - Time: \(String(format: "%.3f", endTimestamp))")
        }
        
        func getInstanceValue(for stateName: String) -> Double {
            switch stateName.lowercased() {
            case "splash":
                return 0.0  // logo (for splash screen)
            case "hero":
                return 0.0  // logo (for hero animation)
            case "sessionresults":
                return 1.0  // sessionResults
            case "activesession":
                return 2.0  // activeSession
            case "milestoneresults":
                return 4.0  // milestoneResults
            case "milestoneview_complete", "milestoneviewcomplete":
                return 5.0  // milestoneView_complete
            case "milestoneview_incomplete", "milestoneviewincomplete":
                return 6.0  // milestoneView_incomplete
            default:
                return 0.0
            }
        }
        
        func debugAvailableInputs() {
            guard let viewModel = viewModel else { return }
            
            // Try to access state machine and list inputs
            // This is for debugging - the exact API may vary
            riveLog("🔍 Attempting to debug available inputs...")
            
            // The Rive iOS SDK 6.12 API may be different
            // We'll need to use reflection or check available methods
        }
        
        func setInstanceValue(_ value: Double) {
            guard let viewModel = viewModel else {
                print("⚠️ Cannot set instance - viewModel is nil")
                return
            }
            
            riveLog("🎯 [\(uniqueId)] Setting instance value to \(value)")
            
            // Set the instance input directly
            do {
                try viewModel.setInput("instance", value: value)
                print("✅ [\(uniqueId)] Set instance input to \(value)")
            } catch {
                print("⚠️ [\(uniqueId)] Failed to set instance input: \(error)")
            }
        }
        
        func setState(_ stateName: String) {
            let timestamp = Date().timeIntervalSince1970
            riveLog("🟦 [\(uniqueId)] setState() START - '\(stateName)' - Thread: \(Thread.isMainThread ? "Main" : "Background") - Time: \(String(format: "%.3f", timestamp))")
            guard let viewModel = viewModel else { 
                print("⚠️ Cannot set state - viewModel is nil")
                return 
            }
            
            // Don't update if it's already set to the same state
            if currentStateName == stateName {
                riveLog("🟦 [\(uniqueId)] State already set to '\(stateName)', skipping")
                return
            }
            
            currentStateName = stateName
            riveLog("🟦 [\(uniqueId)] currentStateName updated to '\(stateName)'")
            
            // Use provided instanceValue if available, otherwise calculate from stateName
            let instanceToSet: Double
            if let providedInstance = instanceValue {
                instanceToSet = providedInstance
            } else {
                instanceToSet = getInstanceValue(for: stateName)
            }
            
            riveLog("🎯 [\(uniqueId)] Setting state: '\(stateName)' (instance = \(instanceToSet))")
            riveLog("🟦 [\(uniqueId)] About to call viewModel.setInput('instance', value: \(instanceToSet))...")
            
            // Set instance value first, then the state will use it
            do {
                try viewModel.setInput("instance", value: instanceToSet)
                riveLog("🟦 [\(uniqueId)] viewModel.setInput() call completed")
                print("✅ [\(uniqueId)] Set instance to \(instanceToSet) for state '\(stateName)'")
            } catch {
                print("⚠️ [\(uniqueId)] Failed to set input: \(error)")
            }
            riveLog("🟦 [\(uniqueId)] setState() END")
        }
        
        func playAnimation(_ animationName: String) {
            guard let viewModel = viewModel else { return }
            
            currentAnimationName = animationName
            
            // The RiveViewModel should handle animation playback automatically
            // based on the state machine configuration
            riveLog("🎬 Animation '\(animationName)' should play via state machine")
        }
        
        func resolvedArtboardName(in riveFile: RiveFile) -> String? {
            guard let requested = artboardName, !requested.isEmpty else { return nil }
            if (try? riveFile.artboard(fromName: requested)) != nil {
                return requested
            }
            print("⚠️ [\(uniqueId)] Artboard '\(requested)' not found in '\(fileName)' — using default")
            debugArtboards()
            return nil
        }

        func debugArtboards() {
            // Helper function to list all available artboards in a Rive file
            guard let riveFile = riveFile else {
                print("⚠️ [\(uniqueId)] Cannot debug artboards - riveFile is nil")
                return
            }
            
            do {
                let artboardCount = riveFile.artboardCount()
                riveLog("📋 [\(uniqueId)] Rive file '\(fileName)' has \(artboardCount) artboard(s):")
                
                for i in 0..<artboardCount {
                    if let artboard = try? riveFile.artboard(from: i) {
                        riveLog("   \(i): '\(artboard.name())'")
                    }
                }
                
                // Also show the default/main artboard
                let mainArtboard = try riveFile.artboard()
                riveLog("   Default/Main artboard: '\(mainArtboard.name())'")
            } catch {
                print("⚠️ [\(uniqueId)] Error listing artboards: \(error)")
            }
        }
        
        func setTextInputs(_ textInputs: [String: String]) {
            // To set text inputs in Rive:
            // Method 1: Use Data Binding (preferred) - Set the data binding value
            // Method 2: Direct Text Run access - Set the text run directly
            
            // First, try to get the artboard from the RiveView (the active artboard)
            // This is the artboard that's actually being displayed
            var artboard: RiveArtboard?
            
            if let riveView = riveView {
                // Try to access the artboard from the RiveView
                // The RiveView should have access to the active artboard
                // Note: The exact API may vary - this is a common pattern
                // artboard = riveView.artboard
                // If that doesn't work, we'll fall back to getting it from the file
            }
            
            // Fallback: Get artboard from RiveFile if we couldn't get it from the view
            if artboard == nil {
                guard let riveFile = riveFile else {
                    print("⚠️ [\(uniqueId)] Cannot set text inputs - riveFile is nil")
                    return
                }
                
                do {
                    // Try to get the specific artboard by name if provided, or fall back to main artboard
                    if let artboardName = artboardName {
                        // Try to get the specific artboard by name
                        if let namedArtboard = try? riveFile.artboard(fromName: artboardName) {
                            artboard = namedArtboard
                            print("✅ [\(uniqueId)] Using artboard '\(artboardName)' from file")
                        } else {
                            // Artboard name not found, list available artboards and use main
                            print("⚠️ [\(uniqueId)] Artboard '\(artboardName)' not found")
                            debugArtboards()
                            let mainArtboard = try riveFile.artboard()
                            artboard = mainArtboard
                            riveLog("   Falling back to main artboard: '\(mainArtboard.name)'")
                        }
                    } else {
                        // No artboard name specified, use the default/main artboard
                        let mainArtboard = try riveFile.artboard()
                        artboard = mainArtboard
                        riveLog("📋 [\(uniqueId)] Using default artboard: '\(mainArtboard.name)'")
                    }
                } catch {
                    print("⚠️ [\(uniqueId)] Error accessing artboard from file: \(error)")
                    return
                }
            }
            
            guard let artboard = artboard else {
                print("⚠️ [\(uniqueId)] Could not get artboard for text inputs")
                return
            }
            
            // Set each text input
            for (inputName, textValue) in textInputs {
                // Check if this value actually changed
                let previousValue = currentTextInputs?[inputName]
                if previousValue == textValue {
                    // Skip if value hasn't changed
                    continue
                }
                
                print("📝 [\(uniqueId)] Updating text input '\(inputName)': '\(previousValue ?? "nil")' → '\(textValue)'")
                
                // METHOD 1: Try Data Binding first (if using "Generated String 1" or similar)
                // Data bindings are accessed through the artboard
                var dataBindingFound = false
                
                // Try common data binding names
                let dataBindingNames = [
                    "Generated String 1",  // The name you set in Rive
                    "generatedString1",
                    "GeneratedString1"
                ]
                
                for _ in dataBindingNames {
                    // Try to access the data binding through the artboard
                    // The API might be: artboard.dataBinding(named:), artboard.binding(named:), etc.
                    // Since we don't know the exact API, we'll try reflection first
                    let artboardMirror = Mirror(reflecting: artboard)
                    for child in artboardMirror.children {
                        // Look for methods or properties related to data bindings
                        if let label = child.label, label.lowercased().contains("binding") || label.lowercased().contains("data") {
                            riveLog("   Found potential data binding property: \(label)")
                        }
                    }
                    
                    // Try direct access (if API is known)
                    // This is a placeholder - we'll need to check the actual Rive iOS SDK API
                    // Example: if let binding = artboard.dataBinding(named: bindingName) {
                    //     binding.setValue(textValue)
                    //     dataBindingFound = true
                    // }
                }
                
                // Get the target artboard (try to find the active one first)
                var targetArtboard = artboard
                
                // Try to access the artboard through the RiveView using reflection
                if let riveView = riveView {
                    let mirror = Mirror(reflecting: riveView)
                    for child in mirror.children {
                        if let artboard = child.value as? RiveArtboard {
                            targetArtboard = artboard
                            self.activeArtboard = artboard
                            print("✅ [\(uniqueId)] Found artboard through RiveView reflection: '\(artboard.name())'")
                            break
                        }
                    }
                    
                    if let viewModel = viewModel {
                        let viewModelMirror = Mirror(reflecting: viewModel)
                        for child in viewModelMirror.children {
                            if let artboard = child.value as? RiveArtboard {
                                targetArtboard = artboard
                                self.activeArtboard = artboard
                                print("✅ [\(uniqueId)] Found artboard through RiveViewModel reflection: '\(artboard.name())'")
                                break
                            }
                        }
                    }
                }
                
                if let storedArtboard = self.activeArtboard {
                    targetArtboard = storedArtboard
                    print("✅ [\(uniqueId)] Using stored active artboard: '\(storedArtboard.name())'")
                }
                
                // METHOD 1: Set data binding value (primary method)
                // View Model: "View Model 1"
                // String Property: "txt"
                // Since the text run is bound to this property, updating it will automatically update the text
                riveLog("🔍 [\(uniqueId)] Attempting to set data binding '\(inputName)' in 'View Model 1' to '\(textValue)'")
                
                var dataBindingSet = false
                
                // Try to access the view model instance through the artboard
                // The Rive iOS SDK should have methods like:
                // - artboard.viewModelInstance(named: "View Model 1")
                // - artboard.getViewModelInstance("View Model 1")
                // - artboard.viewModelInstances.first(where: { $0.name == "View Model 1" })
                
                // Try using reflection to find view model instances and their methods
                let artboardMirror = Mirror(reflecting: targetArtboard)
                riveLog("   Searching artboard for view model access methods...")
                
                // List all methods/properties on the artboard that might relate to view models
                for child in artboardMirror.children {
                    if let label = child.label {
                        let lowerLabel = label.lowercased()
                        if lowerLabel.contains("viewmodel") || lowerLabel.contains("view_model") || lowerLabel.contains("model") || lowerLabel.contains("binding") {
                            riveLog("   Found potential view model property: \(label)")
                            
                            // Try to access the view model instance
                            let valueMirror = Mirror(reflecting: child.value)
                            for vmChild in valueMirror.children {
                                riveLog("     View model child: \(vmChild.label ?? "unnamed")")
                            }
                        }
                    }
                }
                
                // Try direct API access using common Rive SDK patterns
                // Based on Rive documentation and web search, try these patterns:
                riveLog("   Attempting to access view model 'View Model 1' and property 'txt'...")
                
                // Try to access the view model instance and set the string property
                // We'll try multiple API patterns since the exact signature may vary
                
                // Pattern 1: Try artboard.viewModelInstance(named:) -> stringProperty(named:) -> value
                // This is the most common pattern in Rive SDKs
                // Note: We'll need to check if these methods exist in Rive iOS SDK
                // If they don't exist, we'll get a compile error which will tell us the correct API
                
                // Since Swift doesn't allow dynamic method calls easily, we'll try to call it directly
                // If the method doesn't exist, the compiler will tell us
                // If it exists with a different signature, we'll get a compile error with suggestions
                
                // For now, we'll use a workaround: try to find the method through the artboard's type
                // and use reflection or try-catch to handle if it doesn't exist
                
                // Let's try to call it and see what happens
                // The actual implementation depends on the Rive iOS SDK version
                // Common patterns:
                // 1. targetArtboard.viewModelInstance(named: "View Model 1")?.stringProperty(named: "txt")?.value = textValue
                // 2. targetArtboard.viewModelInstance(named: "View Model 1")?.stringProperty(named: "txt")?.setValue(textValue)
                // 3. targetArtboard.getViewModelInstance("View Model 1")?.getStringProperty("txt")?.setValue(textValue)
                
                // Try to actually call the API methods
                // If they don't exist, we'll get compile errors that tell us the correct API
                // Let's try the most common patterns:
                
                // Try to access view model through different objects
                // The API might be on RiveFile, RiveViewModel, or RiveArtboard with a different method name
                
                // Pattern 1: Access through RiveFile -> View Model -> Instance -> String Property
                // Based on Rive iOS SDK 6.12.2 headers:
                // 1. riveFile.viewModel(named: "View Model 1") -> RiveDataBindingViewModel
                // 2. viewModel.createInstance(fromName:) or createDefaultInstance() -> RiveDataBindingViewModelInstance
                // 3. instance.stringPropertyFromPath("txt") -> RiveDataBindingViewModelInstanceStringProperty
                // 4. property.value = textValue
                // 5. artboard.bind(viewModelInstance: instance)
                
                if let riveFile = riveFile {
                    // Step 1: Get the view model from the file (try "Hero" first, then legacy names)
                    var viewModel: RiveDataBindingViewModel?
                    for name in ["Hero", "View Model 1", "ViewModel1"] {
                        if let vm = riveFile.viewModelNamed(name) {
                            viewModel = vm
                            break
                        }
                    }
                    if let viewModel = viewModel {
                        // Step 2: Create an instance from the view model
                        // Try createDefaultInstance first (the default instance)
                        // IMPORTANT: Store a strong reference to the instance (required by SDK)
                        if let instance = viewModel.createDefaultInstance() {
                            // Store the instance to maintain a strong reference
                            self.viewModelInstance = instance
                            
                            // Step 3: Get the string property using the inputName (not hardcoded "txt")
                            // API: stringProperty(fromPath:) (Swift name)
                            // Try the inputName first, then try variations if it doesn't work
                            var stringProperty: RiveDataBindingViewModel.Instance.StringProperty?
                            
                            // Try exact match first
                            stringProperty = instance.stringProperty(fromPath: inputName)
                            
                            // If that fails, try with different path formats
                            if stringProperty == nil {
                                // Try with property name variations
                                let variations = [
                                    inputName.replacingOccurrences(of: " ", with: "-"),  // "badge style" -> "badge-style"
                                    inputName.replacingOccurrences(of: "-", with: " "),  // "badge-style" -> "badge style"
                                    inputName.lowercased(),
                                    inputName.capitalized
                                ]
                                
                                for variation in variations {
                                    if let prop = instance.stringProperty(fromPath: variation) {
                                        stringProperty = prop
                                        riveLog("   ✅ Found property using variation: '\(variation)'")
                                        break
                                    }
                                }
                            }
                            
                            if let stringProperty = stringProperty {
                                // Step 4: Set the value
                                stringProperty.value = textValue
                                
                                // Step 5: Bind the instance to the artboard
                                // CRITICAL: Use the active artboard if available, otherwise use targetArtboard
                                let artboardToBind = self.activeArtboard ?? targetArtboard
                                artboardToBind.bind(viewModelInstance: instance)
                                
                                // Also try to advance the artboard to ensure the change is visible
                                artboardToBind.advance(by: 0.0)
                                
                                // Force a redraw
                                if let riveView = riveView {
                                    riveView.setNeedsDisplay()
                                    riveView.setNeedsLayout()
                                }
                                
                                dataBindingSet = true
                                print("✅ [\(uniqueId)] Set data binding '\(inputName)' to '\(textValue)' and bound to artboard '\(artboardToBind.name())'")
                                riveLog("   Using active artboard: \(self.activeArtboard != nil ? "YES" : "NO")")
                            } else {
                                // Try accessing the property directly from the properties array
                                // The property might be a generic PropertyData that needs to be cast
                                if let property = instance.properties.first(where: { $0.name == inputName }) {
                                    riveLog("🔍 [\(uniqueId)] Found property '\(inputName)' in properties array, attempting to set value...")
                                    
                                    // Try to cast to string property and set value
                                    // The property might need to be accessed differently
                                    if let stringProperty = property as? RiveDataBindingViewModel.Instance.StringProperty {
                                        stringProperty.value = textValue
                                        
                                        let artboardToBind = self.activeArtboard ?? targetArtboard
                                        artboardToBind.bind(viewModelInstance: instance)
                                        artboardToBind.advance(by: 0.0)
                                        
                                        if let riveView = riveView {
                                            riveView.setNeedsDisplay()
                                            riveView.setNeedsLayout()
                                        }
                                        
                                        dataBindingSet = true
                                        print("✅ [\(uniqueId)] Set property '\(inputName)' to '\(textValue)' via direct property access")
                                    } else {
                                        // Try to get the string property using the property's name/path
                                        // The property exists, so try accessing it via stringProperty(fromPath:) with the property name
                                        if let stringProperty = instance.stringProperty(fromPath: property.name) {
                                            stringProperty.value = textValue
                                            
                                            let artboardToBind = self.activeArtboard ?? targetArtboard
                                            artboardToBind.bind(viewModelInstance: instance)
                                            artboardToBind.advance(by: 0.0)
                                            
                                            if let riveView = riveView {
                                                riveView.setNeedsDisplay()
                                                riveView.setNeedsLayout()
                                            }
                                            
                                            dataBindingSet = true
                                            print("✅ [\(uniqueId)] Set property '\(inputName)' to '\(textValue)' via property.name path")
                                        } else {
                                            // The property exists but stringProperty(fromPath:) didn't work
                                            // Try using the property's name directly to get the string property
                                            print("⚠️ [\(uniqueId)] Property '\(inputName)' exists but direct cast failed (type: \(type(of: property)))")
                                            riveLog("   💡 Trying to get string property using property name '\(property.name)'...")
                                            
                                            // Try getting the string property using the property's actual name
                                            var stringProperty: RiveDataBindingViewModel.Instance.StringProperty?
                                            
                                            // Try with property.name
                                            stringProperty = instance.stringProperty(fromPath: property.name)
                                            
                                            // If that fails, try variations of the property name
                                            if stringProperty == nil {
                                                let variations = [
                                                    property.name.replacingOccurrences(of: " ", with: "-"),
                                                    property.name.replacingOccurrences(of: "-", with: " "),
                                                    property.name.lowercased(),
                                                    property.name.capitalized
                                                ]
                                                
                                                for variation in variations {
                                                    if let prop = instance.stringProperty(fromPath: variation) {
                                                        stringProperty = prop
                                                        riveLog("   ✅ Found string property using variation: '\(variation)'")
                                                        break
                                                    }
                                                }
                                            }
                                            
                                            // If still not found, try casting the property directly
                                            if stringProperty == nil {
                                                if let strProp = property as? RiveDataBindingViewModel.Instance.StringProperty {
                                                    stringProperty = strProp
                                                    riveLog("   ✅ Cast property directly to StringProperty")
                                                }
                                            }
                                            
                                            if let stringProperty = stringProperty {
                                                stringProperty.value = textValue
                                                
                                                let artboardToBind = self.activeArtboard ?? targetArtboard
                                                artboardToBind.bind(viewModelInstance: instance)
                                                artboardToBind.advance(by: 0.0)
                                                
                                                if let riveView = riveView {
                                                    riveView.setNeedsDisplay()
                                                    riveView.setNeedsLayout()
                                                }
                                                
                                                dataBindingSet = true
                                                print("✅ [\(uniqueId)] Set property '\(inputName)' (via '\(property.name)') to '\(textValue)'")
                                            } else {
                                                riveLog("   ⚠️ Could not get string property using property name '\(property.name)'")
                                                riveLog("   💡 Property might be a different type (not a string property)")
                                                riveLog("   💡 Property type: \(type(of: property))")
                                            }
                                        }
                                    }
                                } else {
                                    print("⚠️ [\(uniqueId)] String property '\(inputName)' not found in view model instance")
                                    riveLog("   Available properties: \(instance.properties.map { $0.name }.joined(separator: ", "))")
                                    
                                    // Debug: List all properties with their types
                                    riveLog("   📋 All properties in view model instance:")
                                    for property in instance.properties {
                                        riveLog("      - \(property.name) (type: \(type(of: property)))")
                                    }
                                }
                            }
                        } else {
                            print("⚠️ [\(uniqueId)] Could not create default instance from view model")
                            // Try creating instance by name if default doesn't work
                            // The instance name might be the same as the view model name or different
                            if let instance = viewModel.createInstance(fromName: "View Model 1") {
                                self.viewModelInstance = instance
                                if let stringProperty = instance.stringProperty(fromPath: inputName) {
                                    stringProperty.value = textValue
                                    targetArtboard.bind(viewModelInstance: instance)
                                    dataBindingSet = true
                                    print("✅ [\(uniqueId)] Set data binding '\(inputName)' to '\(textValue)' via named instance")
                                }
                            }
                        }
                    } else {
                        print("⚠️ [\(uniqueId)] View model 'View Model 1' not found in RiveFile")
                        riveLog("   Available view models: \(riveFile.viewModelCount)")
                    }
                }
                
                // If data binding was set successfully, we're done
                // The text should update automatically through the binding
                if !dataBindingSet {
                    print("⚠️ [\(uniqueId)] Data binding not set - will try text run fallback")
                }
                
                // Pattern 2: Try alternative method names
                // Uncomment and try if Pattern 1 doesn't work:
                /*
                if let viewModelInstance = targetArtboard.getViewModelInstance("View Model 1") {
                    if let stringProperty = viewModelInstance.getStringProperty("txt") {
                        stringProperty.setValue(textValue)
                        dataBindingSet = true
                        print("✅ [\(uniqueId)] Set data binding 'txt' to '\(textValue)' via getViewModelInstance")
                    }
                }
                */
                
                // For now, log what we're trying to do
                // The user should check Rive iOS SDK documentation or try uncommenting the patterns above
                riveLog("   ⚠️ Data binding API call commented out - need to verify exact Rive iOS SDK API")
                riveLog("   Try uncommenting Pattern 1 or Pattern 2 above and see which one compiles")
                riveLog("   Or check Rive iOS SDK headers/documentation for viewModelInstance/stringProperty methods")
                
                // METHOD 2: Fall back to direct text run access ONLY if data binding didn't work
                // Note: With data binding set up, we shouldn't need this, but keeping as fallback
                var textRunFound = false
                
                if !dataBindingSet {
                    print("⚠️ [\(uniqueId)] Data binding not set successfully, trying text run fallback...")
                    riveLog("   This shouldn't be necessary if data binding is properly configured")
                    let possibleNames = [
                        inputName,  // Try the provided name first
                        "Run 1",    // Default Rive text run name
                        "run 1",    // Lowercase version
                        "sessionDuration",  // Without brackets
                        "[sessionDuration]"  // With brackets (as shown in hierarchy)
                    ]
                    
                    for name in possibleNames {
                    if let textRun = targetArtboard.textRun(name) {
                        // Set the text using setText method
                        textRun.setText(textValue)
                        print("✅ [\(uniqueId)] Set text input '\(inputName)' to '\(textValue)' using text run name '\(name)'")
                        riveLog("   Text run current text after setting: '\(textRun.text())'")
                        
                        // Force the artboard to update/advance to show the change
                        targetArtboard.advance(by: 0.0)
                        
                        // Force a redraw
                        if let riveView = riveView {
                            riveView.setNeedsDisplay()
                            riveView.setNeedsLayout()
                        }
                        
                        // Verify the text was actually set
                        let verifyText = textRun.text()
                        if verifyText == textValue {
                            print("✅ [\(uniqueId)] Verified: Text run text is '\(verifyText)'")
                        } else {
                            print("⚠️ [\(uniqueId)] Warning: Text run text is '\(verifyText)', expected '\(textValue)'")
                        }
                        
                        // IMPORTANT: In Rive, text updates only work when the animation is playing
                        // Make sure the animation is playing/active
                        // Also, try advancing the artboard multiple times to ensure the change is visible
                        for _ in 0..<3 {
                            targetArtboard.advance(by: 0.016) // Advance by one frame (60fps)
                        }
                        
                        textRunFound = true
                        break
                    }
                }
                
                    if !textRunFound {
                        print("⚠️ [\(uniqueId)] Text run '\(inputName)' not found on artboard")
                        riveLog("   Tried names: \(possibleNames.joined(separator: ", "))")
                        riveLog("   Artboard name: \(targetArtboard.name())")
                        riveLog("   In Rive Editor: Right-click on 'Run 1' under '[sessionDuration]' and select 'Export Name'")
                        riveLog("   Then set the exported name to exactly '\(inputName)' (case-sensitive)")
                    }
                }
            }
        }
        
        func setColorInputs(_ colorInputs: [String: Color]) {
            // Set color inputs through data binding
            // Similar to text inputs, but for color properties
            
            // Always re-resolve the currently displayed artboard from the live RiveView.
            // Transitions can effectively swap which artboard is "active", and re-applying
            // to an old artboard instance causes the tint to revert.
            var targetArtboard: RiveArtboard? = nil
            if let riveView = riveView {
                let mirror = Mirror(reflecting: riveView)
                for child in mirror.children {
                    if let artboard = child.value as? RiveArtboard {
                        targetArtboard = artboard
                        self.activeArtboard = artboard
                        break
                    }
                }
            }
            // Fallback to last known if reflection failed for this pass.
            if targetArtboard == nil {
                targetArtboard = self.activeArtboard
            }
            
            if targetArtboard == nil {
                // Important: do not fall back to resolving an artboard from the raw riveFile.
                // That artboard may not be the one being rendered by the RiveView, leading
                // to "console shows values, but nothing updates visually" behavior.
                print("⚠️ [\(uniqueId)] Skipping color inputs — could not resolve active artboard from RiveView")
                return
            }
            
            guard let artboard = targetArtboard else {
                print("⚠️ [\(uniqueId)] Could not get artboard for color inputs")
                return
            }

        // Ensure `activeArtboard` is set even when we couldn't discover it via `riveView` reflection yet.
        // Without this, the viewModel instance may not get bound early enough for the first color pass.
        self.activeArtboard = artboard
            
            // Set each color input through data binding
            for (inputName, color) in colorInputs {
                riveLog("🎨 [\(uniqueId)] Setting color input '\(inputName)' to theme color")
                
                // First, try to use the already-bound viewModelInstance
                if let instance = self.viewModelInstance {
                    var colorProperty = instance.colorProperty(fromPath: inputName)
                    if colorProperty == nil {
                        let variations = ["Theme Color", "theme_color", inputName.replacingOccurrences(of: " ", with: "-"), inputName.capitalized]
                        for v in variations {
                            colorProperty = instance.colorProperty(fromPath: v)
                            if colorProperty != nil { break }
                        }
                    }
                    if let colorProperty = colorProperty {
                        colorProperty.value = UIColor(color)
                        riveLog("✅ [\(uniqueId)] Set color property '\(inputName)' via existing instance")
                        if let artboardToBind = self.activeArtboard {
                            artboardToBind.bind(viewModelInstance: instance)
                            self.lastBoundArtboardName = artboardToBind.name()
                            self.lastBoundArtboardObjectId = ObjectIdentifier(artboardToBind)
                            artboardToBind.advance(by: 0.016)
                            // Rive quirk: after setting VM properties, ensure the view model is playing
                            // so converters/data-binding actually propagate on first render.
                            self.viewModel?.play()
                        }
                        riveView?.setNeedsDisplay()
                    } else {
                        print("⚠️ [\(uniqueId)] Color property '\(inputName)' not found. Available: \(instance.properties.map { $0.name }.joined(separator: ", "))")
                    }
                    continue
                }
                
                // Fallback: create instance only if we have the VIEW's artboard to bind to (never bind to file artboard — it's not drawn)
                if let riveFile = riveFile, let artboardToBind = self.activeArtboard {
                    for vmName in ["Hero", "View Model 1", "ViewModel1"] {
                        guard let viewModel = riveFile.viewModelNamed(vmName),
                              let instance = viewModel.createDefaultInstance() else { continue }
                        self.viewModelInstance = instance
                        var colorProperty = instance.colorProperty(fromPath: inputName)
                        if colorProperty == nil {
                            let variations = ["Theme Color", "theme_color", inputName.capitalized]
                            for v in variations { if let p = instance.colorProperty(fromPath: v) { colorProperty = p; break } }
                        }
                        if let colorProperty = colorProperty {
                            colorProperty.value = UIColor(color)
                            artboardToBind.bind(viewModelInstance: instance)
                            self.lastBoundArtboardName = artboardToBind.name()
                            self.lastBoundArtboardObjectId = ObjectIdentifier(artboardToBind)
                            artboardToBind.advance(by: 0.016)
                            // Rive quirk: after setting VM properties, ensure the view model is playing
                            // so converters/data-binding actually propagate on first render.
                            self.viewModel?.play()
                            print("✅ [\(uniqueId)] Set color property '\(inputName)' (new instance bound to view artboard)")
                            riveView?.setNeedsDisplay()
                        } else {
                            print("⚠️ [\(uniqueId)] Color '\(inputName)' not found. Available: \(instance.properties.map { $0.name }.joined(separator: ", "))")
                        }
                        break
                    }
                } else if self.activeArtboard == nil {
                    print("⚠️ [\(uniqueId)] Skipping color input — activeArtboard nil (view artboard not found); data binding will apply after layout)")
                }
            }
        }
        
        func setNumberInputs(_ numberInputs: [String: Double]) {
            // IMPORTANT: Never call riveFile.artboard() here to create a temporary artboard.
            // Temporary artboards get bound to the viewModelInstance, and their C++ destructor
            // crashes when the local variable goes out of scope while the binding is still live.
            // Instead, use ONLY self.activeArtboard (established during bindViewModelInstance).
            guard let riveFile = riveFile else {
                print("⚠️ [\(uniqueId)] Cannot set number inputs — riveFile is nil")
                return
            }

            // Resolve the artboard that is actually being displayed.
            // If reflection didn't find it yet, fall back to resolving by `artboardName`.
            var artboard: RiveArtboard? = self.activeArtboard
            if artboard == nil, let riveView = riveView {
                let mirror = Mirror(reflecting: riveView)
                for child in mirror.children {
                    if let found = child.value as? RiveArtboard {
                        artboard = found
                        self.activeArtboard = found
                        break
                    }
                }
            }
            guard let targetArtboard = artboard else {
                // Important: do not fall back to resolving an artboard from the raw riveFile.
                // That artboard may not be the one being rendered by the RiveView, leading
                // to "console shows values, but nothing updates visually" behavior.
                print("⚠️ [\(uniqueId)] Skipping number inputs — could not resolve active artboard from RiveView yet")
                return
            }

            // Resolve instance: reuse the already-bound instance when available.
            // Creating a new instance and binding it on every update would double-bind
            // the artboard, which corrupts the C++ binding state.
            let isNewInstance: Bool
            let instance: RiveDataBindingViewModel.Instance
            if let existing = self.viewModelInstance {
                instance = existing
                isNewInstance = false
            } else {
                var vmDef: RiveDataBindingViewModel?
                for name in ["Hero", "View Model 1", "ViewModel1"] {
                    if let vm = riveFile.viewModelNamed(name) {
                        vmDef = vm
                        break
                    }
                }
                if vmDef == nil, riveFile.viewModelCount > 0 {
                    vmDef = try? riveFile.viewModel(at: 0)
                }
                guard let vmDef, let newInstance = vmDef.createDefaultInstance() else {
                    print("⚠️ [\(uniqueId)] No view model found for number inputs")
                    return
                }
                self.viewModelInstance = newInstance
                instance = newInstance
                isNewInstance = true
            }

            // Ensure ViewModel is playing before we set values
            self.viewModel?.play()

            // Session badge shape is typically driven by sessionSeconds (or legacy totalSessionSeconds) → Rive converter.

            // Bind instance to the target artboard if needed (prevents stale bindings when the state swaps artboards).
            if isNewInstance || self.lastBoundArtboardObjectId != ObjectIdentifier(targetArtboard) {
                targetArtboard.bind(viewModelInstance: instance)
                self.lastBoundArtboardName = targetArtboard.name()
                self.lastBoundArtboardObjectId = ObjectIdentifier(targetArtboard)
                targetArtboard.advance(by: 0.016)
                targetArtboard.advance(by: 0.0)
            }

            // Set number properties on the instance
            for (inputName, numberValue) in numberInputs {
                print("🔢 [\(uniqueId)] Setting number input '\(inputName)' to \(numberValue)")

                var numberProperty: RiveDataBindingViewModel.Instance.NumberProperty?

                // Exact match
                numberProperty = instance.numberProperty(fromPath: inputName)

                // Variations (Rive may export as "Total Session Seconds" or totalSessionSeconds)
                if numberProperty == nil {
                    let variations: [String] = [
                        inputName.replacingOccurrences(of: " ", with: "-"),
                        inputName.replacingOccurrences(of: "-", with: " "),
                        inputName.lowercased(),
                        inputName.capitalized,
                        "Total Session Seconds",
                        "total_session_seconds"
                    ]
                    for variation in variations {
                        if let prop = instance.numberProperty(fromPath: variation) {
                            numberProperty = prop
                            riveLog("   ✅ Found number property using variation: '\(variation)'")
                            break
                        }
                    }
                }

                // Properties array fallback
                if numberProperty == nil,
                   let property = instance.properties.first(where: { $0.name == inputName }) {
                    numberProperty = instance.numberProperty(fromPath: property.name)
                }

                if let numberProperty {
                    numberProperty.value = Float(numberValue)
                    print("✅ [\(uniqueId)] Set number property '\(inputName)' to \(numberValue)")
                } else {
                    print("⚠️ [\(uniqueId)] Number property '\(inputName)' not found in view model instance")
                }
            }

            // Legacy VM property "sessionDuration" (number): mirror from sessionSeconds or totalSessionSeconds
            let sessionSecsForDurationAlias = numberInputs["sessionSeconds"] ?? numberInputs["totalSessionSeconds"]
            if let secs = sessionSecsForDurationAlias, !numberInputs.keys.contains("sessionDuration") {
                // Don't write 0 into sessionDuration on hero (cumulative payload) — avoids clobbering tier-related bindings in older files
                let skipZeroHero = numberInputs["cumulativeSeconds"] != nil && secs == 0
                if !skipZeroHero {
                    let namesToTry = ["sessionDuration", "Session Duration", "session_duration"]
                    for name in namesToTry {
                        if let prop = instance.numberProperty(fromPath: name) {
                            prop.value = Float(secs)
                            riveLog("✅ [\(uniqueId)] Set number property '\(name)' to \(secs) (alias for session duration)")
                            break
                        }
                    }
                }
            }

            // Session result sends `sessionSeconds` only (no cumulative fields). Mirror to legacy VM names so old .riv converters keep working.
            // Do not mirror when hero sends `cumulativeSeconds` + `sessionSeconds: 0` — that would zero out `totalSessionSeconds` and break tier display.
            if let secs = numberInputs["sessionSeconds"], numberInputs["totalSessionSeconds"] == nil,
               numberInputs["cumulativeSeconds"] == nil {
                for legacyName in ["totalSessionSeconds", "Total Session Seconds", "total_session_seconds"] {
                    if let prop = instance.numberProperty(fromPath: legacyName) {
                        prop.value = Float(secs)
                        riveLog("✅ [\(uniqueId)] Set number property '\(legacyName)' to \(secs) (mirror sessionSeconds)")
                        break
                    }
                }
            }

            // State machine conditions (e.g. instance swaps) read State Machine Inputs (SMI), not View Model properties.
            // Mirror numbers to SMI so transitions/conditions that read SMI see the same values as the VM.
            // IMPORTANT: If your Rive logic reads SMI (state machine inputs) instead of VM properties,
            // we need to mirror all numberInputs into SMI as best-effort.
            for (inputName, value) in numberInputs {
                let smiNames: [String] = [
                    inputName,
                    inputName.replacingOccurrences(of: " ", with: "-"),
                    inputName.replacingOccurrences(of: "-", with: " "),
                    inputName.capitalized
                ]
                var didSet = false
                for smiName in smiNames {
                    do {
                        try self.viewModel?.setInput(smiName, value: value)
                        print("✅ [\(uniqueId)] Set state machine input '\(smiName)' to \(value)")
                        didSet = true
                        break
                    } catch {
                        // Try next name
                    }
                }
                if !didSet, inputName == "totalSessionSeconds" || inputName == "sessionSeconds" {
                    // Extra aliases commonly used in older files. On hero, avoid mirroring sessionSeconds=0 to legacy tier SMIs (cumulative payload).
                    let aliases: [String] = {
                        if numberInputs["cumulativeSeconds"] != nil, inputName == "sessionSeconds", value == 0 {
                            return []
                        }
                        return [
                            "sessionDuration", "Total Session Seconds", "total_session_seconds",
                            "totalSessionSeconds", "sessionSeconds", "Session Seconds", "session_seconds"
                        ]
                    }()
                    for alias in aliases {
                        do {
                            try self.viewModel?.setInput(alias, value: value)
                            print("✅ [\(uniqueId)] Set state machine input '\(alias)' to \(value)")
                            break
                        } catch {
                            // ignore
                        }
                    }
                }
            }

            // If we created a new instance, ensure it is bound (in case `lastBoundArtboardName` was nil).
            if isNewInstance, self.lastBoundArtboardName == nil {
                targetArtboard.bind(viewModelInstance: instance)
                self.lastBoundArtboardName = targetArtboard.name()
                self.lastBoundArtboardObjectId = ObjectIdentifier(targetArtboard)
                riveLog("🔗 [\(uniqueId)] Bound new ViewModel instance to artboard '\(targetArtboard.name())'")
            }

            // Advance to flush the new values into the state machine
            targetArtboard.advance(by: 0.016)
            targetArtboard.advance(by: 0.0)

            self.viewModel?.play()
            
            // Ensure colors are applied after numbers + trigger-state changes.
            // This avoids an initial-load race where the state machine transition may
            // override VM-tinted elements after we set colors.
            if let colorInputs = self.currentColorInputs {
                self.setColorInputs(colorInputs)
            }
            riveView?.setNeedsDisplay()
            riveView?.setNeedsLayout()

            // Fire triggers (e.g. levelUp) after number inputs and colors are set
            fireTriggerInputs()
        }

        /// Fire any trigger inputs (e.g. "levelUp") on the view model. Call after setting number/color so the badge transition is reflected.
        func fireTriggerInputs() {
            guard let names = currentTriggerInputs, !names.isEmpty else { return }
            for name in names {
                do {
                    try viewModel?.triggerInput(name)
                    print("✅ [\(uniqueId)] Fired trigger '\(name)'")
                } catch {
                    print("⚠️ [\(uniqueId)] Could not fire trigger '\(name)': \(error)")
                }
            }

            // Some Rive states/transitions may override colors right after triggers.
            // Re-apply the last known color inputs once shortly after triggers.
            if let colorInputs = self.currentColorInputs {
                let d: Double = 0.08
                DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                    self.setColorInputs(colorInputs)
                    self.viewModel?.play()
                    self.riveView?.setNeedsDisplay()
                    self.riveView?.setNeedsLayout()
                }
            }
        }
        
        func setTriggerInputs(_ triggerInputs: [String]) {
            currentTriggerInputs = triggerInputs
            // Don’t fire immediately; wait until instance + inputs are applied.
        }
        
        func setBoolInputs(_ boolInputs: [String: Bool]) {
            // Set boolean inputs through data binding
            // These are used for boolean properties in state machines
            
            var targetArtboard: RiveArtboard?
            
            if let riveView = riveView {
                let mirror = Mirror(reflecting: riveView)
                for child in mirror.children {
                    if let artboard = child.value as? RiveArtboard {
                        targetArtboard = artboard
                        self.activeArtboard = artboard
                        break
                    }
                }
            }
            
            if targetArtboard == nil {
                guard let riveFile = riveFile else {
                    print("⚠️ [\(uniqueId)] Cannot set boolean inputs - riveFile is nil")
                    return
                }
                
                do {
                    if let artboardName = artboardName {
                        if let namedArtboard = try? riveFile.artboard(fromName: artboardName) {
                            targetArtboard = namedArtboard
                        } else {
                            targetArtboard = try riveFile.artboard()
                        }
                    } else {
                        targetArtboard = try riveFile.artboard()
                    }
                } catch {
                    print("⚠️ [\(uniqueId)] Error accessing artboard for boolean inputs: \(error)")
                    return
                }
            }
            
            guard let artboard = targetArtboard else {
                print("⚠️ [\(uniqueId)] Could not get artboard for boolean inputs")
                return
            }
            
            // Set each boolean input through data binding
            // Note: Rive SDK may not have a direct boolProperty method
            // Boolean inputs in state machines are typically controlled via stateName
            // This method is kept for potential future use or if the SDK supports it
            for (inputName, boolValue) in boolInputs {
                riveLog("🔘 [\(uniqueId)] Boolean input '\(inputName)' requested: \(boolValue)")
                riveLog("   💡 Note: Boolean state machine inputs are controlled via stateName")
                riveLog("   💡 The stateName should be set to 'locked' or 'unlocked' based on this boolean")
                
                // Try to find boolean property if the SDK supports it
                if let riveFile = riveFile {
                    var viewModel: RiveDataBindingViewModel?
                    for name in ["Hero", "View Model 1", "ViewModel1"] {
                        if let vm = riveFile.viewModelNamed(name) { viewModel = vm; break }
                    }
                    if let viewModel = viewModel {
                        if let instance = self.viewModelInstance ?? viewModel.createDefaultInstance() {
                            self.viewModelInstance = instance
                            
                            // Check available properties to see if boolean is supported
                            let propertyNames = instance.properties.map { $0.name }
                            riveLog("   Available properties: \(propertyNames.joined(separator: ", "))")
                            
                            // Bind instance to artboard
                            let artboardToBind = self.activeArtboard ?? artboard
                            artboardToBind.bind(viewModelInstance: instance)
                            artboardToBind.advance(by: 0.0)
                            
                            if let riveView = riveView {
                                riveView.setNeedsDisplay()
                                riveView.setNeedsLayout()
                            }
                        }
                    }
                }
            }
        }
        
        func setArtboardInputs(_ artboardInputs: [String: String]) {
            // Set artboard inputs through data binding
            // This allows switching between artboards dynamically
            
            guard let riveFile = riveFile else {
                print("⚠️ [\(uniqueId)] Cannot set artboard inputs - riveFile is nil")
                return
            }
            
            // Set each artboard input through data binding
            for (propertyName, artboardName) in artboardInputs {
                riveLog("🎯 [\(uniqueId)] Setting artboard input '\(propertyName)' to artboard '\(artboardName)'")
                
                // Get the view model (try "Hero" first, then legacy names)
                var viewModel: RiveDataBindingViewModel?
                for name in ["Hero", "View Model 1", "ViewModel1"] {
                    if let vm = riveFile.viewModelNamed(name) { viewModel = vm; break }
                }
                if let viewModel = viewModel {
                    // Create or reuse instance
                    if let instance = self.viewModelInstance ?? viewModel.createDefaultInstance() {
                        self.viewModelInstance = instance
                        
                        // Get the artboard property using the property name
                        // Using the documented Rive SDK API
                        if let artboardProperty = instance.artboardProperty(fromPath: propertyName) {
                            // Get the bindable artboard from the file
                            // Using the documented Rive SDK API
                            // Note: bindableArtboard(withName:) can throw and returns non-optional
                            do {
                                let bindableArtboard = try riveFile.bindableArtboard(withName: artboardName)
                                
                                // Set the artboard property value
                                // The setValue method should take just the bindable artboard
                                // Note: The property object itself handles the property name
                                artboardProperty.setValue(bindableArtboard)
                                print("✅ [\(uniqueId)] Set artboard property '\(propertyName)' to artboard '\(artboardName)'")
                                
                                // After setting the property, the Rive runtime should automatically switch to that artboard
                                // We don't need to manually get the artboard from the property - the view model should handle it
                                // Instead, get the artboard directly from the file using the name we set
                                let targetArtboard = try riveFile.artboard(fromName: artboardName)
                                
                                riveLog("📋 [\(uniqueId)] Using artboard '\(targetArtboard.name())' from file")
                                
                                riveLog("📋 [\(uniqueId)] Artboard from property: '\(targetArtboard.name())'")
                                
                                // Update the active artboard to the one from the property
                                self.activeArtboard = targetArtboard
                                
                                // Bind instance to the target artboard
                                targetArtboard.bind(viewModelInstance: instance)
                                targetArtboard.advance(by: 0.0)
                                
                                print("✅ [\(uniqueId)] Switched to artboard '\(targetArtboard.name())' from property")
                                
                                // IMPORTANT: After switching artboards, the target artboard's state machine is now active
                                // Each artboard (flipPhone_animations, milestoneBadges) has its own state machine
                                // We need to set the state AND instance value on the TARGET artboard's state machine
                                if let stateName = self.currentStateName {
                                    riveLog("🔄 [\(uniqueId)] Re-setting state '\(stateName)' on target artboard '\(targetArtboard.name())'...")
                                    
                                    // Preserve the original instanceValue so it's used when re-setting the state
                                    let previousStateName = self.currentStateName
                                    let preservedInstanceValue = self.instanceValue
                                    
                                    // Clear the current state name so setState will actually set it again
                                    self.currentStateName = nil
                                    
                                    // Re-call setState AND setInstanceValue after the artboard switch completes
                                    // IMPORTANT: We need to set the instance on the TARGET artboard's state machine, not the viewModel
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        if let stateName = previousStateName {
                                            // Calculate the instance value to use
                                            let instanceToSet = preservedInstanceValue ?? self.getInstanceValue(for: stateName)
                                            
                                            riveLog("🎯 [\(self.uniqueId)] Setting instance \(instanceToSet) and state '\(stateName)' on artboard '\(targetArtboard.name())'...")
                                            
                                            // After switching artboards, the viewModel should now be using the target artboard's state machine
                                            // Set the instance value on the viewModel (which should now be using the target artboard)
                                            // Then set the state
                                            riveLog("🎯 [\(self.uniqueId)] Setting instance \(instanceToSet) on viewModel (target artboard: '\(targetArtboard.name())')...")
                                            
                                            // Set instance value first
                                            self.setInstanceValue(instanceToSet)
                                            
                                            // Temporarily set instanceValue so setState uses it
                                            let originalInstanceValue = self.instanceValue
                                            self.instanceValue = preservedInstanceValue
                                            
                                            // Set the state (which should use the instance we just set)
                                            self.setState(stateName)
                                            
                                            // Restore original instanceValue
                                            self.instanceValue = originalInstanceValue
                                            
                                            // Advance the artboard to apply changes
                                            targetArtboard.advance(by: 0.0)
                                            
                                            // Update the view
                                            if let riveView = self.riveView {
                                                riveView.setNeedsDisplay()
                                                riveView.setNeedsLayout()
                                            }
                                        }
                                    }
                                }
                                
                                // Update the RiveView to use the new artboard
                                if let riveView = riveView {
                                    // Force the view to update
                                    targetArtboard.advance(by: 0.0)
                                    riveView.setNeedsDisplay()
                                    riveView.setNeedsLayout()
                                    riveLog("🔄 [\(uniqueId)] Updated RiveView to use new artboard")
                                }
                                
                                // Alternative approach: The artboard property should automatically update the displayed artboard
                                // If it's not working, the issue might be in the Rive setup
                                // Make sure in Rive Editor:
                                // 1. The artboard property is marked as "Bindable"
                                // 2. The property type is "Artboard" (not "Reference")
                                // 3. The property is connected to actually switch the artboard
                            } catch {
                                print("⚠️ [\(uniqueId)] Could not create bindable artboard for '\(artboardName)': \(error)")
                                riveLog("   💡 Check that artboard '\(artboardName)' exists in the Rive file")
                                debugArtboards()
                            }
                        } else {
                            print("⚠️ [\(uniqueId)] Artboard property '\(propertyName)' not found in view model instance")
                            riveLog("   Available properties: \(instance.properties.map { $0.name }.joined(separator: ", "))")
                            riveLog("   💡 Tip: In Rive Editor, create an artboard property in 'View Model 1' named '\(propertyName)'")
                            riveLog("   💡 The property type must be 'Artboard' in the View Model")
                        }
                    } else {
                        print("⚠️ [\(uniqueId)] Could not create instance for artboard input '\(propertyName)'")
                    }
                } else {
                    print("⚠️ [\(uniqueId)] View model 'View Model 1' not found for artboard input '\(propertyName)'")
                }
            }
        }
    }
}

#else

// Fallback when RiveRuntime is not available
struct RiveViewWrapper: UIViewRepresentable {
    let fileName: String
    let autoPlay: Bool
    
    init(fileName: String, autoPlay: Bool = true) {
        self.fileName = fileName
        self.autoPlay = autoPlay
    }
    
    func makeUIView(context: Context) -> UIView {
        print("⚠️ RiveRuntime not available - using fallback")
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed
    }
}

#endif

