//
//  AirlineDatabase.swift
//  NaarsCars
//
//  Loads airline IATA -> name from bundled JSON; in-memory cache, sync load. Used for flight parsing and display.
//

import Foundation

/// Loads and caches airline code -> name from bundled JSON. Open-data only.
enum AirlineDatabase {

    private static let lock = NSLock()
    private static var _byIATA: [String: String]?
    private static var _loadTime: TimeInterval?

    /// All loaded airlines by IATA code. Loads from bundle on first access (synchronous).
    static var byIATA: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = _byIATA { return cached }
        let start = CFAbsoluteTimeGetCurrent()
        let result = loadFromBundle()
        _byIATA = result
        _loadTime = CFAbsoluteTimeGetCurrent() - start
        if _loadTime ?? 0 > 0.1 {
            AppLogger.info("rides", "[AirlineDatabase] initial load took \(String(format: "%.3f", _loadTime ?? 0))s")
        }
        return result
    }

    /// Set of known IATA airline codes (for flight number parser to avoid false positives).
    static var knownAirlineCodes: Set<String> {
        Set(byIATA.keys)
    }

    /// Airline name for IATA code, or nil.
    static func name(iata: String) -> String? {
        byIATA[iata.uppercased()]
    }

    private static func loadFromBundle() -> [String: String] {
        let url = Bundle.main.url(forResource: "airlines", withExtension: "json", subdirectory: "FlightData")
            ?? Bundle.main.url(forResource: "airlines", withExtension: "json")
        guard let u = url, let data = try? Data(contentsOf: u) else {
            AppLogger.warning("rides", "[AirlineDatabase] airlines.json not found in bundle")
            return [:]
        }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            AppLogger.warning("rides", "[AirlineDatabase] failed to decode airlines.json")
            return [:]
        }
        return decoded.mapKeys { $0.uppercased() }
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var out: [T: Value] = [:]
        for (k, v) in self { out[transform(k)] = v }
        return out
    }
}
