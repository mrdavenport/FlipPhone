import SwiftUI

/// Provides the app's fixed theme color (Lavender). Custom color selection has been removed.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    /// Fixed theme color - Lavender. No user customization.
    var themeColor: Color { ThemeManager.defaultColor }
    
    static let defaultColor = Color(red: 182/255.0, green: 137/255.0, blue: 255/255.0) // Lavender
    
    private init() {}
}
