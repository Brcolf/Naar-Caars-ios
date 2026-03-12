// NaarsCars/Core/Utilities/URLDetectionCache.swift
import Foundation

/// Thread-safe URL detection cache using NSDataDetector.
/// Avoids re-parsing message text on every view evaluation.
final class URLDetectionCache: @unchecked Sendable {
    static let shared = URLDetectionCache()

    private let lock = NSLock()
    private var cache: [String: [URL]] = [:]
    private let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    func urls(for text: String) -> [URL] {
        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let results = detector.matches(in: text, range: range).compactMap { $0.url }

        lock.lock()
        cache[text] = results
        lock.unlock()

        return results
    }
}
