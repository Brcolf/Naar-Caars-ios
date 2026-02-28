//
//  FlightInfo.swift
//  NaarsCars
//
//  Extracted flight info from ride notes (open-data enrichment only).
//

import Foundation

/// Airport info from open data (e.g. OurAirports)
struct AirportInfo: Sendable {
    let iata: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timezone: String?
}

/// Extracted and enriched flight info for display; no live status.
struct FlightInfo: Sendable {
    /// Substring that matched the flight number pattern
    let rawTextMatch: String
    /// Normalized flight number (e.g. "DL1234")
    let normalizedFlightNumber: String
    /// IATA airline code (e.g. "DL")
    let airlineCode: String
    /// Numeric part of flight number
    let flightNumberInt: Int
    /// Best-effort airline name from open data
    let airlineName: String?
    /// Origin IATA if parsed from text (e.g. SEA)
    let originAirportIATA: String?
    /// Destination IATA if parsed from text (e.g. LAX)
    let destinationAirportIATA: String?
    /// Enriched origin airport (name, coords, timezone)
    let originAirport: AirportInfo?
    /// Enriched destination airport (name, coords, timezone)
    let destinationAirport: AirportInfo?

    /// Build minimal FlightInfo for display from persisted flight_normalized (e.g. "DL123", "SWA1234").
    static func fromPersisted(normalized: String) -> FlightInfo? {
        let t = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let code = String(t.prefix(while: { $0.isLetter }))
        let numPart = t.dropFirst(code.count)
        let flightNumberInt = Int(numPart) ?? 0
        let airlineCode = code.uppercased()
        let airlineName = AirlineDatabase.name(iata: airlineCode)
        return FlightInfo(
            rawTextMatch: t,
            normalizedFlightNumber: t,
            airlineCode: airlineCode.isEmpty ? t : airlineCode,
            flightNumberInt: flightNumberInt,
            airlineName: airlineName,
            originAirportIATA: nil,
            destinationAirportIATA: nil,
            originAirport: nil,
            destinationAirport: nil
        )
    }

    /// Display flight for a ride: use persisted flight_normalized if set, else extract from notes. Synchronous.
    static func displayInfo(for ride: Ride) -> FlightInfo? {
        if let n = ride.flightNormalized, !n.isEmpty {
            #if DEBUG
            AppLogger.info("rides", "[FlightAudit] displayInfo rideId=\(ride.id) source=persisted flight_normalized=\(n)")
            #endif
            return fromPersisted(normalized: n)
        }
        let fallback = extract(from: ride.notes, pickup: ride.pickup, destination: ride.destination)
        #if DEBUG
        AppLogger.info("rides", "[FlightAudit] displayInfo rideId=\(ride.id) source=\(fallback != nil ? "fallbackFromNotes" : "none") flight_normalized=\(ride.flightNormalized ?? "nil") fallbackCode=\(fallback?.normalizedFlightNumber ?? "nil")")
        #endif
        return fallback
    }

    /// Extract and enrich flight info from ride notes only (pickup/destination not used for flight code to avoid false positives like "SR 99", "NE 45th"). Uses same FlightCodeParser as persistence.
    static func extract(from notes: String?, pickup: String? = nil, destination: String? = nil) -> FlightInfo? {
        let notesTrimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notesTrimmed.isEmpty, let result = FlightCodeParser.parseFirstFlightCode(from: notesTrimmed) else { return nil }
        let flightNumberInt = Int(result.numberDigits) ?? 0
        let airlineName = AirlineDatabase.name(iata: result.airlineCode)
        let combined = [notes, pickup, destination].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let route = combined.isEmpty ? nil : AirportRouteParser.extractAirports(from: combined)
        let originIATA = route?.originIATA
        let destIATA = route?.destinationIATA
        let originAirport = originIATA.flatMap { AirportDatabase.airport(iata: $0) }
        let destAirport = destIATA.flatMap { AirportDatabase.airport(iata: $0) }
        return FlightInfo(
            rawTextMatch: result.rawMatch,
            normalizedFlightNumber: result.normalized,
            airlineCode: result.airlineCode,
            flightNumberInt: flightNumberInt,
            airlineName: airlineName,
            originAirportIATA: originIATA,
            destinationAirportIATA: destIATA,
            originAirport: originAirport,
            destinationAirport: destAirport
        )
    }
}
