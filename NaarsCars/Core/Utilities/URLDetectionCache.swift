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
        let urls = matches.compactMap { Self.webURL(for: $0, in: text) }

        lock.lock()
        cache[text] = urls
        lock.unlock()

        return urls
    }

    /// The web URL a link match should open, or nil when the match is not a web link.
    ///
    /// Uses the detector's own URL: it carries the scheme for links typed without one
    /// ("www.example.com"), which the matched substring does not. Only web links get a preview
    /// card; mailto: and other schemes are left as plain text. The detector fills in http://
    /// for a link typed without a scheme; that is upgraded to https, as browsers do, because
    /// App Transport Security refuses the plain-http fetch the preview needs. A link typed with
    /// an explicit http:// is left as typed.
    static func webURL(for match: NSTextCheckingResult, in text: String) -> URL? {
        guard let url = match.url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        guard scheme == "http",
              let typedRange = Range(match.range, in: text),
              !text[typedRange].lowercased().hasPrefix("http://"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }
}
