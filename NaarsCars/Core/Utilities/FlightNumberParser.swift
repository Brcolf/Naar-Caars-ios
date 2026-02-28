//
//  FlightNumberParser.swift
//  NaarsCars
//
//  Extracts commercial flight numbers from free text; avoids false positives using known airline codes.
//

import Foundation

/// Extracts a single flight number from text using open-data airline codes to avoid false positives.
enum FlightNumberParser {

    /// Pattern: 2-letter airline code (optional space/dash) + digits. Case-insensitive.
    /// Must not be preceded by word character or # (avoids "Order 1234", "#1234").
    private static let flightPattern = #"""
    (?<![#\w])                    # not after # or word char
    ([A-Za-z]{2})                 # airline code (capture 1)
    [\s\-]*                       # optional space or dash
    (\d{1,4})                     # flight number (capture 2)
    (?![0-9])                     # not more digits (avoid 12345 as flight "12" + "345")
    """#

    /// Extract first flight number from string. Returns nil if no match or airline code not in known set.
    /// - Parameters:
    ///   - text: Free text (e.g. ride notes)
    ///   - knownAirlineCodes: Set of valid IATA 2-letter codes (e.g. from AirlineDatabase). If nil, any 2-letter prefix is accepted (higher false positive risk).
    /// - Returns: FlightInfo with raw match, normalized number, airline code, and numeric part; airlineName and airports are nil (caller enriches).
    static func extract(
        from text: String,
        knownAirlineCodes: Set<String>? = nil
    ) -> FlightInfo? {
        guard let regex = try? NSRegularExpression(pattern: flightPattern, options: .allowCommentsAndWhitespace),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let codeRange = Range(match.range(at: 1), in: text),
              let numRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let code = String(text[codeRange]).uppercased()
        let numStr = String(text[numRange])
        guard let num = Int(numStr), num > 0 else { return nil }
        if let known = knownAirlineCodes, !known.contains(code) {
            return nil
        }
        let fullRange = match.range
        let rawTextMatch = (fullRange.location != NSNotFound && Range(fullRange, in: text) != nil)
            ? String(text[Range(fullRange, in: text)!])
            : (code + numStr)
        return FlightInfo(
            rawTextMatch: rawTextMatch,
            normalizedFlightNumber: code + numStr,
            airlineCode: code,
            flightNumberInt: num,
            airlineName: nil,
            originAirportIATA: nil,
            destinationAirportIATA: nil,
            originAirport: nil,
            destinationAirport: nil
        )
    }
}
