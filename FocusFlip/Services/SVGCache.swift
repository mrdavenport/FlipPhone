import Foundation

/// Shared in-memory cache for SVG assets.
///
/// Two levels:
///  1. `rawStrings`  — raw SVG file content keyed by bundle resource name.
///     Avoids repeated `Data(contentsOf:)` calls for the same badge file.
///  2. `coloredStrings` — color-replaced SVG content keyed by "name|#hexColor".
///     Avoids repeated `String.replacingOccurrences` work per visible cell.
///
/// Both caches are backed by `NSCache` so the OS can evict entries under
/// memory pressure without crashing.
final class SVGCache {
    static let shared = SVGCache()
    private init() {}

    private let rawStrings = NSCache<NSString, NSString>()
    private let coloredStrings = NSCache<NSString, NSString>()

    // MARK: - Raw SVG loading

    /// Returns the raw SVG string for the given resource name, loading from
    /// disk only on the first call.  Subsequent calls return the cached value.
    func rawSVG(named name: String) -> String? {
        let key = name as NSString
        if let cached = rawStrings.object(forKey: key) {
            return cached as String
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Badges")
                ?? Bundle.main.url(forResource: name, withExtension: "svg"),
              let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        rawStrings.setObject(string as NSString, forKey: key)
        return string
    }

    // MARK: - Color-replaced SVG

    /// Returns a color-replaced copy of the badge SVG.  The result is cached
    /// so the same badge+color pair is only processed once.
    func coloredSVG(named name: String, hexColor: String) -> String? {
        let cacheKey = "\(name)|\(hexColor)" as NSString
        if let cached = coloredStrings.object(forKey: cacheKey) {
            return cached as String
        }
        guard let raw = rawSVG(named: name) else { return nil }

        let hexNoHash = hexColor.replacingOccurrences(of: "#", with: "")
        var result = raw
            .replacingOccurrences(of: "#8A49F4", with: hexColor, options: .caseInsensitive)
            .replacingOccurrences(of: "8A49F4",  with: hexNoHash, options: .caseInsensitive)
            .replacingOccurrences(of: "#8a49f4", with: hexColor, options: .caseInsensitive)
            .replacingOccurrences(of: "8a49f4",  with: hexNoHash, options: .caseInsensitive)

        coloredStrings.setObject(result as NSString, forKey: cacheKey)
        return result
    }

    // MARK: - Cache management

    func clearAll() {
        rawStrings.removeAllObjects()
        coloredStrings.removeAllObjects()
    }
}
