//
//  RivePrewarmCache.swift
//  FocusFlip
//
//  Caches raw Rive file data so RiveViewWrapper's Coordinator can skip disk I/O.
//  Defined in its own file (no #if canImport) so the linker always has the symbol
//  when FocusFlipApp calls it from inside #if canImport(RiveRuntime).
//

import Foundation

/// Caches raw Rive file data so Coordinator.init can skip disk I/O.
/// Pre-warm during the splash screen (~2 s) so the main thread never blocks
/// on a large file read during the splash → home transition.
final class RivePrewarmCache {
    static let shared = RivePrewarmCache()
    private let lock = NSLock()
    private var dataCache: [String: Data] = [:]

    private init() {}

    /// Begin loading `fileName.riv` from the bundle on a background thread.
    func prewarm(fileName: String) {
        lock.lock()
        let alreadyCached = dataCache[fileName] != nil
        lock.unlock()
        guard !alreadyCached else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let url = Bundle.main.url(forResource: fileName, withExtension: "riv"),
                  let data = try? Data(contentsOf: url) else { return }
            self.lock.lock()
            self.dataCache[fileName] = data
            self.lock.unlock()
            print("✅ [RivePrewarmCache] Pre-warmed \(fileName).riv (\(data.count / 1024) KB)")
        }
    }

    /// Returns cached data synchronously (nil if not yet loaded).
    func getData(for fileName: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dataCache[fileName]
    }
}
