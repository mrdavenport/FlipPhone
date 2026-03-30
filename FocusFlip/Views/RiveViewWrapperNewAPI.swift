import SwiftUI
import UIKit

#if canImport(RiveRuntime)
@_spi(RiveExperimental) import RiveRuntime

/// Experimental Swift-first Rive wrapper.
///
/// Uses the upstream experimental API behind `@_spi(RiveExperimental)`:
/// - `Worker` + `File` + `Rive` for view creation
/// - `rive.viewModelInstance.setValue(of:to:)` for properties
/// - `rive.viewModelInstance.fire(trigger:)` for triggers
struct RiveViewWrapperNewAPI: View {
    /// Runtime flag for A/B testing the experimental Swift-first Rive API.
    /// Stored in UserDefaults so you can flip it in-app (see `SettingsView`).
    @AppStorage("rive_use_experimental_api") private var useExperimentalRive: Bool = false

    let fileName: String
    let autoPlay: Bool
    let stateName: String?
    let animationName: String?
    let uniqueId: String

    let textInputs: [String: String]?
    let artboardName: String?
    let instanceValue: Double?
    let colorInputs: [String: SwiftUI.Color]?
    let numberInputs: [String: Double]?
    let boolInputs: [String: Bool]?
    let artboardInputs: [String: String]?
    let triggerInputs: [String]?
    let triggerReloadNonce: Int?

    init(
        fileName: String,
        autoPlay: Bool = true,
        stateName: String? = nil,
        animationName: String? = nil,
        uniqueId: String = UUID().uuidString,
        textInputs: [String: String]? = nil,
        artboardName: String? = nil,
        instanceValue: Double? = nil,
        colorInputs: [String: SwiftUI.Color]? = nil,
        numberInputs: [String: Double]? = nil,
        boolInputs: [String: Bool]? = nil,
        artboardInputs: [String: String]? = nil,
        triggerInputs: [String]? = nil,
        triggerReloadNonce: Int? = nil
    ) {
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

    @State private var rive: Rive?
    @State private var lastTriggerSignature: String?

    private var loadKey: String {
        // Only reload when the actual Rive config changes.
        // Inputs update through `setValue` / `fire` after load.
        "\(fileName)|\(artboardName ?? "")"
    }

    private var triggerSignature: String {
        guard let triggerInputs else { return "" }
        return triggerInputs.joined(separator: "|")
    }

    private var numberSignature: String {
        guard let numberInputs else { return "" }
        return numberInputs
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "|")
    }

    private var colorSignature: String {
        guard let colorInputs else { return "" }
        return colorInputs
            .map { "\($0.key)=\($0.value.description)" }
            .sorted()
            .joined(separator: "|")
    }

    private var textSignature: String {
        guard let textInputs else { return "" }
        return textInputs
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        Group {
            if !useExperimentalRive {
                // Legacy wrapper path (your current production behavior).
                RiveViewWrapper(
                    fileName: fileName,
                    autoPlay: autoPlay,
                    stateName: stateName,
                    animationName: animationName,
                    uniqueId: uniqueId,
                    textInputs: textInputs,
                    artboardName: artboardName,
                    instanceValue: instanceValue,
                    colorInputs: colorInputs,
                    numberInputs: numberInputs,
                    boolInputs: boolInputs,
                    artboardInputs: artboardInputs,
                    triggerInputs: triggerInputs,
                    triggerReloadNonce: triggerReloadNonce
                )
            } else {
                // Experimental wrapper path.
                Group {
                    if let rive {
                        RiveUIViewRepresentable(rive: rive)
                            .paused(!autoPlay)
                    } else {
                        // Keep layout stable while Rive loads.
                Rectangle().fill(SwiftUI.Color.clear)
                    }
                }
                .task(id: loadKey) {
                    await loadRive()
                }
                .onChange(of: numberSignature) { _, _ in
                    applyDataBindings()
                }
                .onChange(of: colorSignature) { _, _ in
                    applyDataBindings()
                }
                .onChange(of: textSignature) { _, _ in
                    applyDataBindings()
                }
                .onChange(of: triggerSignature) { _, _ in
                    fireTriggersIfNeeded(force: true)
                }
                .onChange(of: triggerReloadNonce) { _, newValue in
                    guard let n = newValue, n > 0 else { return }
                    fireTriggersIfNeeded(force: true)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 140_000_000)
                        fireTriggersIfNeeded(force: true)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadRive() async {
        do {
            let worker = try await Worker()
            let file = try await File(source: .local(fileName, Bundle.main), worker: worker)

            if let artboardName {
                let artboard = try await file.createArtboard(artboardName)
                self.rive = try await Rive(file: file, artboard: artboard)
            } else {
                self.rive = try await Rive(file: file)
            }

            applyDataBindings()
            fireTriggersIfNeeded(force: true)
        } catch {
            print("⚠️ [RiveViewWrapperNewAPI] Failed to load Rive '\(fileName)': \(error)")
            self.rive = nil
        }
    }

    @MainActor
    private func applyDataBindings() {
        guard let viewModelInstance = rive?.viewModelInstance else { return }

        if let instance = computedInstanceValue {
            viewModelInstance.setValue(of: NumberProperty(path: "instance"), to: Float(instance))
        }

        if let numberInputs {
            for (path, value) in numberInputs {
                viewModelInstance.setValue(of: NumberProperty(path: path), to: Float(value))
            }
        }

        if let boolInputs {
            for (path, value) in boolInputs {
                viewModelInstance.setValue(of: BoolProperty(path: path), to: value)
            }
        }

        if let textInputs {
            for (path, value) in textInputs {
                viewModelInstance.setValue(of: StringProperty(path: path), to: value)
            }
        }

        if let colorInputs {
            for (path, swiftUIColor) in colorInputs {
                viewModelInstance.setValue(of: ColorProperty(path: path), to: riveColor(from: swiftUIColor))
            }
        }
    }

    @MainActor
    private func fireTriggersIfNeeded(force: Bool) {
        guard let viewModelInstance = rive?.viewModelInstance else { return }

        let sig = triggerSignature
        guard !sig.isEmpty else { return }
        if !force, lastTriggerSignature == sig { return }

        // Apply all data binding first so trigger-driven transitions see updated inputs.
        applyDataBindings()

        triggerInputs?.forEach { name in
            viewModelInstance.fire(trigger: TriggerProperty(path: name))
        }

        lastTriggerSignature = sig
    }

    private var computedInstanceValue: Double? {
        if let instanceValue { return instanceValue }
        guard let stateName else { return nil }
        return getInstanceValue(for: stateName)
    }

    private func getInstanceValue(for stateName: String) -> Double {
        // Mirrors legacy wrapper behavior.
        switch stateName.lowercased() {
        case "splash":
            return 0.0
        case "hero":
            return 0.0
        case "sessionresults":
            return 1.0
        case "activesession":
            return 2.0
        case "milestoneresults":
            return 4.0
        case "milestoneview_complete", "milestoneviewcomplete":
            return 5.0
        default:
            return 0.0
        }
    }

    private func riveColor(from swiftUIColor: SwiftUI.Color) -> RiveRuntime.Color {
        // SwiftUI -> UIColor -> RGBA bytes.
        let uiColor = UIColor(swiftUIColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Experimental runtime uses UInt8 channels.
        let red = UInt8(clamping: Int(round(r * 255)))
        let green = UInt8(clamping: Int(round(g * 255)))
        let blue = UInt8(clamping: Int(round(b * 255)))
        let alpha = UInt8(clamping: Int(round(a * 255)))

        return RiveRuntime.Color(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

#else
/// Fallback: if RiveRuntime isn't available, render nothing.
struct RiveViewWrapperNewAPI: View {
    init(
        fileName: String,
        autoPlay: Bool = true,
        stateName: String? = nil,
        animationName: String? = nil,
        uniqueId: String = UUID().uuidString,
        textInputs: [String: String]? = nil,
        artboardName: String? = nil,
        instanceValue: Double? = nil,
        colorInputs: [String: SwiftUI.Color]? = nil,
        numberInputs: [String: Double]? = nil,
        boolInputs: [String: Bool]? = nil,
        artboardInputs: [String: String]? = nil,
        triggerInputs: [String]? = nil,
        triggerReloadNonce: Int? = nil
    ) {}

    var body: some View { Rectangle().fill(SwiftUI.Color.clear) }
}

#endif

