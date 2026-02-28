//
//  AirportDatabase.swift
//  NaarsCars
//
//  Loads airport open data from bundle (OurAirports-style); in-memory cache, sync load.
//

import Foundation

/// Loads and caches airport data from bundled JSON (IATA, name, lat, lon, timezone). Open-data only.
enum AirportDatabase {

    private static let lock = NSLock()
    private static var _byIATA: [String: AirportInfo]?
    private static var _loadTime: TimeInterval?

    /// All loaded airports by IATA code. Loads from bundle on first access (synchronous).
    static var byIATA: [String: AirportInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = _byIATA { return cached }
        let start = CFAbsoluteTimeGetCurrent()
        let result = loadFromBundle()
        _byIATA = result
        _loadTime = CFAbsoluteTimeGetCurrent() - start
        if _loadTime ?? 0 > 0.1 {
            AppLogger.info("rides", "[AirportDatabase] initial load took \(String(format: "%.3f", _loadTime ?? 0))s")
        }
        return result
    }

    /// Look up airport by IATA code. Returns nil if not in bundle.
    static func airport(iata: String) -> AirportInfo? {
        byIATA[iata.uppercased()]
    }

    private static func loadFromBundle() -> [String: AirportInfo] {
        let url = Bundle.main.url(forResource: "airports", withExtension: "json", subdirectory: "FlightData")
            ?? Bundle.main.url(forResource: "airports", withExtension: "json")
        guard let u = url, let data = try? Data(contentsOf: u) else {
            AppLogger.warning("rides", "[AirportDatabase] airports.json not found in bundle")
            return [:]
        }
        struct AirportRow: Decodable {
            let iata: String
            let name: String
            let lat: Double
            let lon: Double
            let tz: String?
        }
        guard let rows = try? JSONDecoder().decode([AirportRow].self, from: data) else {
            AppLogger.warning("rides", "[AirportDatabase] failed to decode airports.json")
            return [:]
        }
        var out: [String: AirportInfo] = [:]
        for row in rows {
            let key = row.iata.uppercased()
            out[key] = AirportInfo(
                iata: key,
                name: row.name,
                latitude: row.lat,
                longitude: row.lon,
                timezone: row.tz
            )
        }
        return out
    }
}
