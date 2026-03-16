//
//  FlightCodeParser.swift
//  NaarsCars
//
//  Parses first flight code from ride notes (cue-based + direct patterns). Normalizes to AIRLINECODE+DIGITS.
//
//  Logic: We try cue-based patterns first ("flight AS587", "on AS 587", "Alaska flight AS 587") so that
//  natural language is reliably matched. Then we try a direct pattern: 2–3 letters immediately followed
//  by (optional space/dash and) 1–4 digits. We do NOT use \b after the airline code because in regex
//  \w includes digits, so "AS587" has no word boundary between S and 5—we use (?=[\s\-]*\d) so the
//  letters must be followed by optional space/dash then a digit (avoids "Order" matching as "Or").
//  False positives avoided: "#1234" (negative lookbehind), "1545 NW Market" (NW not followed by digits),
//  "arrive 10:15" (no letter group before digits), "Order 1234" (no digit after "Or").
//
//  Validation: Matches from the direct pattern or weak cues ("on", "taking") are accepted only if
//  airlineCode is in AirlineDatabase.knownAirlineCodes. Matches from strong cues ("flight", "flt",
//  "alaska flight") are accepted without DB check to allow natural language like "flight AS587".
//

import Foundation

/// Result of parsing a single flight code from notes (for persistence and display).
struct FlightParseResult: Sendable {
    /// Substring as found in the notes
    let rawMatch: String
    /// Airline code uppercased (2 or 3 letters)
    let airlineCode: String
    /// Numeric part as string (stripped, may have leading zero)
    let numberDigits: String
    /// Normalized form: airlineCode + numberDigits, no spaces (e.g. "AS587", "DL1234")
    let normalized: String
    /// URL for Google search: https://www.google.com/search?q=<normalized>+flight
    let googleQueryURL: String
}

/// Parses the first flight code from notes. Uses cue-based patterns first (e.g. "flight AS587"), then direct code+digits. Open-data only.
enum FlightCodeParser {

    /// Strong cue: "flight", "flt", "Alaska flight" — accept without airline DB validation.
    private static let strongCuePatterns: [(pattern: String, sourceLabel: String)] = [
        (#"(?i)(?:flight|flt\.?)\s*:?\s*([A-Za-z]{2,3})[\s\-]*(\d{1,4})"#, "strongCue"),
        (#"(?i)(?:alaska(?:\s+airlines?)?\s+flight)\s+([A-Za-z]{2,3})[\s\-]*(\d{1,4})"#, "strongCue"),
    ]
    /// Weak cue: "on", "taking" — require airlineCode in AirlineDatabase.knownAirlineCodes.
    private static let weakCuePatterns: [(pattern: String, sourceLabel: String)] = [
        (#"(?i)(?:on|taking)\s+([A-Za-z]{2,3})[\s\-]*(\d{1,4})"#, "weakCue"),
    ]

    /// Direct: 2–3 letters (not after # or word char) then optional space/dash then 1–4 digits. No \b so "AS587" matches (digits are \w).
    private static let directPattern = #"(?<![#\w])([A-Za-z]{2,3})(?=[\s\-]*\d)[\s\-]*(\d{1,4})(?![0-9])"#

    /// Parse the first flight code from notes. Tries cue-based patterns first, then direct. Returns normalized code (e.g. AS587) or nil.
    static func parseFirstFlightCode(from notes: String?) -> FlightParseResult? {
        #if DEBUG
        AppLogger.info("rides", "[FlightAudit] parseFirstFlightCode entered; notesLength=\(notes?.count ?? 0)")
        #endif
        guard let text = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            #if DEBUG
            AppLogger.info("rides", "[FlightAudit] parseFirstFlightCode returning nil (empty/nil notes)")
            #endif
            return nil
        }

        // 1a) Strong cues first (flight/flt/alaska flight) — no airline validation
        for item in strongCuePatterns {
            if let result = matchPattern(item.pattern, in: text, sourceLabel: item.sourceLabel) {
                return result
            }
        }

        // 1b) Weak cues ("on", "taking") — require known airline
        for item in weakCuePatterns {
            if let result = matchPattern(item.pattern, in: text, sourceLabel: item.sourceLabel),
               isKnownAirline(result.airlineCode) {
                return result
            }
        }

        // 2) Direct pattern (e.g. "AS587", "DL 1234") — require known airline to avoid SR 99, NE 45th, WA 520
        if let result = matchPattern(directPattern, in: text, sourceLabel: "direct"),
           isKnownAirline(result.airlineCode) {
            return result
        }

        #if DEBUG
        AppLogger.info("rides", "[FlightAudit] parseFirstFlightCode no regex match")
        #endif
        return nil
    }

    private static func matchPattern(
        _ pattern: String,
        in text: String,
        sourceLabel: String,
        options: NSRegularExpression.Options = []
    ) -> FlightParseResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let codeRange = Range(match.range(at: 1), in: text),
              let numRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let airlineCode = String(text[codeRange]).uppercased()
        let numberDigits = String(text[numRange])
        let normalized = airlineCode + numberDigits
        let rawMatch = Range(match.range, in: text).map { String(text[$0]) } ?? normalized
        let query = (normalized + " flight").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized
        let googleQueryURL = "https://www.google.com/search?q=\(query)"
        #if DEBUG
        AppLogger.info("rides", "[FlightAudit] parseFirstFlightCode match raw=\(rawMatch) normalized=\(normalized) source=\(sourceLabel)")
        #endif
        return FlightParseResult(
            rawMatch: rawMatch,
            airlineCode: airlineCode,
            numberDigits: numberDigits,
            normalized: normalized,
            googleQueryURL: googleQueryURL
        )
    }

    /// True if code is in AirlineDatabase.knownAirlineCodes (used to reject direct/weak-cue matches like SR, NE, WA).
    private static func isKnownAirline(_ airlineCode: String) -> Bool {
        AirlineDatabase.knownAirlineCodes.contains(airlineCode.uppercased())
    }
}
