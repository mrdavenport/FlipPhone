import UIKit
import WebKit
import SwiftUI

/// Renders SVG badges to UIImage once per unique (badgeName, color) pair and
/// caches the result. Calendar cells use the cached UIImage directly instead
/// of hosting a WKWebView per cell, eliminating per-cell web-view overhead.
@MainActor
final class BadgeImageCache {
    static let shared = BadgeImageCache()
    private init() {}

    private let imageCache = NSCache<NSString, UIImage>()

    /// Deduplicates concurrent requests for the same key so only one WKWebView
    /// is ever created per unique badge+color combination.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// Keeps SnapshotCoordinator instances alive while their WKWebView loads.
    private var coordinators: [ObjectIdentifier: SnapshotCoordinator] = [:]

    // MARK: - Public API

    /// Returns a cached UIImage, or renders one if not yet available.
    func image(for badgeName: String, color: Color) async -> UIImage? {
        let key = cacheKey(badgeName: badgeName, color: color)
        let nsKey = key as NSString

        if let cached = imageCache.object(forKey: nsKey) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<UIImage?, Never> {
            let img = await self.render(badgeName: badgeName, hexColor: color.toHexString())
            if let img { self.imageCache.setObject(img, forKey: nsKey) }
            return img
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }

    /// Fire-and-forget: warms the cache for every unique badge+color pair in
    /// the supplied list. Safe to call with duplicates.
    func prefetch(badges: [(name: String, color: Color)]) {
        var seen = Set<String>()
        for badge in badges {
            let key = cacheKey(badgeName: badge.name, color: badge.color)
            guard seen.insert(key).inserted else { continue }
            guard imageCache.object(forKey: key as NSString) == nil else { continue }
            guard inFlight[key] == nil else { continue }
            Task { _ = await self.image(for: badge.name, color: badge.color) }
        }
    }

    // MARK: - Rendering

    private func render(badgeName: String, hexColor: String) async -> UIImage? {
        guard let svgString = SVGCache.shared.rawSVG(named: badgeName) else { return nil }

        let hexNoHash = hexColor.replacingOccurrences(of: "#", with: "")
        let coloredSVG = svgString
            .replacingOccurrences(of: "#8A49F4", with: hexColor, options: .caseInsensitive)
            .replacingOccurrences(of: "8A49F4",  with: hexNoHash, options: .caseInsensitive)
            .replacingOccurrences(of: "#8a49f4", with: hexColor, options: .caseInsensitive)
            .replacingOccurrences(of: "8a49f4",  with: hexNoHash, options: .caseInsensitive)

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
                svg { width: 100%; height: 100%; display: block; }
            </style>
        </head>
        <body>\(coloredSVG)</body>
        </html>
        """

        return await withCheckedContinuation { continuation in
            let size = CGSize(width: 200, height: 200)
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.backgroundColor = .clear

            let coordinator = SnapshotCoordinator(webView: webView) { [weak self] image in
                self?.coordinators.removeValue(forKey: ObjectIdentifier(webView))
                continuation.resume(returning: image)
            }
            webView.navigationDelegate = coordinator
            coordinators[ObjectIdentifier(webView)] = coordinator
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - Helpers

    private func cacheKey(badgeName: String, color: Color) -> String {
        "\(badgeName)|\(color.toHexString())"
    }
}

// MARK: - WKNavigationDelegate that triggers the snapshot

private final class SnapshotCoordinator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let completion: (UIImage?) -> Void
    private var completed = false

    init(webView: WKWebView, completion: @escaping (UIImage?) -> Void) {
        self.webView = webView
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !completed else { return }
        completed = true
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: 200)
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            self?.completion(image)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !completed else { return }
        completed = true
        completion(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !completed else { return }
        completed = true
        completion(nil)
    }
}
