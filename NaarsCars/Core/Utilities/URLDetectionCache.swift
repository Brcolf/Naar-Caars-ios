//
//  URLDetectionCache.swift
//  NaarsCars
//
//  Thread-safe cache for NSDataDetector results to avoid expensive regex on repeated calls.
//

import Foundation

// MARK: - URL Detection Cache

/// Thread-safe cache for NSDataDetector results to avoid expensive regex on every render cycle
final class URLDetectionCache: @unchecked Sendable {

    static let shared = URLDetectionCache()

    private var cache: [String: [URL]] = [:]
    private let lock = NSLock()
    private static let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    func urls(for text: String) -> [URL] {
        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let matches = Self.detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []
        let urls = matches.compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }

        lock.lock()
        cache[text] = urls
        lock.unlock()

        return urls
    }
}
