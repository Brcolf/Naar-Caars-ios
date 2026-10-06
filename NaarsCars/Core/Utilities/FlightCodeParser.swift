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
//  Validation: every match is checked against AirlineDatabase.knownAirlineCodes. After a strong cue
//  ("flight", "flt", "alaska flight") a code missing from that short list is still kept when it was
//  typed as a code, in capital letters ("flight SWA1234"). Ordinary words after the cue are not
//  flights: "flight at 5:30" used to become AT5 and "flight in 2 hours" IN2.
//  Every match of a pattern is tried, not only the first ("pick up at 5, AA 100" has "at 5" first).
//  The airline code may be two characters with one digit (B6, F9, G4). A number that is a time
//  ("5:30", "6pm") or a date ("12/5") is never a flight number.
//  Two known codes are also words: without "flight" in front, "as"/"it" not typed in capitals and
//  followed by a short number is read as the word ("as 3 of us", "make it 15 min"). A code with a
//  digit straight after "gate", "apt", "unit" and the like is that label ("Gate B6 10 min").
//

import Foundation

/// Result of parsing a single flight code from notes (for persistence and display).
struct FlightParseResult: Sendable {
    /// Substring as found in the notes
    let rawMatch: String
    /// Airline code uppercased (2 or 3 letters, or 2 characters with one digit such as "B6")
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

    /// An airline code: 2–3 letters, or two characters with one digit (B6 JetBlue, F9 Frontier, G4 Allegiant).
    private static let codePattern = #"[A-Za-z]{2,3}|[A-Za-z][0-9]|[0-9][A-Za-z]"#
    /// A flight number: 1–4 digits that are not part of a longer number, a time ("5:30", "6pm", "6 p.m.") or a date ("12/5").
    private static let numberPattern = #"(\d{1,4})(?![0-9]|[:/][0-9]|\s*[AaPp]\.?[Mm]\b)"#

    /// Strong cue: "flight", "flt", "Alaska flight" — a known airline, or a code typed in capitals (see `isAcceptedCode`).
    private static let strongCuePatterns: [(pattern: String, sourceLabel: String)] = [
        (cuePattern(#"(?:flight|flt\.?)\s*:?\s*"#), "strongCue"),
        (cuePattern(#"(?:alaska(?:\s+airlines?)?\s+flight)\s+"#), "strongCue"),
    ]
    /// Weak cue: "on", "taking" — require airlineCode in AirlineDatabase.knownAirlineCodes.
    private static let weakCuePatterns: [(pattern: String, sourceLabel: String)] = [
        (cuePattern(#"(?:on|taking)\s+"#), "weakCue"),
    ]

    /// Direct: an airline code (not after # or word char) then optional space/dash then the number. No \b so "AS587" matches (digits are \w).
    private static let directPattern = #"(?<![#\w])("# + codePattern + #")(?=[\s\-]*\d)[\s\-]*"# + numberPattern

    /// Two- and three-letter words that follow "flight" in ordinary notes, month and weekday
    /// abbreviations included. They are rejected even when the whole note is in capitals
    /// ("FLIGHT IN 2 HOURS", "FLIGHT DEC 20").
    private static let wordsThatAreNotAirlines: Set<String> = [
        "AT", "IN", "ON", "TO", "NO", "IS", "HAS", "WAS", "ETA", "ETD", "BY", "FOR", "THE", "DUE", "AND", "OUT", "NUM",
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"
    ]

    /// Airline codes that are also everyday words (AS Alaska, IT Tigerair Taiwan), each with the
    /// longest number that still reads as a quantity after the word: "as 3 of us",
    /// "make it 15 min". See `firstAcceptedMatch`.
    private static let airlineCodesThatAreWords: [String: Int] = ["AS": 1, "IT": 2]

    /// Words that label a gate or a unit. A letter-and-digit code straight after one
    /// ("Gate B6 10 min", "Apt B612") is that label, not a JetBlue flight.
    private static let gateAndUnitLabels = ["gate", "apt", "apt.", "apartment", "unit", "door", "room", "suite"]

    /// A cue followed by an airline code (capture 1) and a flight number (capture 2); case-insensitive.
    private static func cuePattern(_ cue: String) -> String {
        "(?i)" + cue + "(" + codePattern + #")[\s\-]*"# + numberPattern
    }

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

        // 1a) Strong cues first (flight/flt/alaska flight) — known airline, or a code typed in capitals
        for item in strongCuePatterns {
            if let result = firstAcceptedMatch(item.pattern, in: text, sourceLabel: item.sourceLabel, afterStrongCue: true) {
                return result
            }
        }

        // 1b) Weak cues ("on", "taking") — require known airline
        for item in weakCuePatterns {
            if let result = firstAcceptedMatch(item.pattern, in: text, sourceLabel: item.sourceLabel, afterStrongCue: false) {
                return result
            }
        }

        // 2) Direct pattern (e.g. "AS587", "DL 1234") — require known airline to avoid SR 99, NE 45th, WA 520
        if let result = firstAcceptedMatch(directPattern, in: text, sourceLabel: "direct", afterStrongCue: false) {
            return result
        }

        #if DEBUG
        AppLogger.info("rides", "[FlightAudit] parseFirstFlightCode no regex match")
        #endif
        return nil
    }

    /// The first match of `pattern` whose airline code passes `isAcceptedCode`. Every match is
    /// tried in order: testing only the first one lost "AA 100" in "pick up at 5, AA 100".
    private static func firstAcceptedMatch(
        _ pattern: String,
        in text: String,
        sourceLabel: String,
        afterStrongCue: Bool
    ) -> FlightParseResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let codeRange = Range(match.range(at: 1), in: text),
                  let numRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            let typedCode = String(text[codeRange])
            guard isAcceptedCode(typedCode, afterStrongCue: afterStrongCue) else {
                continue
            }
            // Without "flight" in front, "as" or "it" not typed in capitals and followed by a
            // short number is the word, not Alaska or Tigerair. Trying every match (above)
            // would otherwise turn "pick up at 5, make it 2 bags" into flight IT2.
            if !afterStrongCue,
               typedCode != typedCode.uppercased(),
               let quantityDigits = airlineCodesThatAreWords[typedCode.uppercased()],
               text[numRange].count <= quantityDigits {
                continue
            }
            // A gate or a unit, not a flight: "Gate B6 10 min", "Apt B612".
            if !afterStrongCue, typedCode.contains(where: { $0.isNumber }) {
                let textBefore = text[..<codeRange.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                if gateAndUnitLabels.contains(where: { textBefore.hasSuffix($0) }) {
                    continue
                }
            }
            let airlineCode = typedCode.uppercased()
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
        return nil
    }

    /// Whether the code as typed in the notes may be shown as a flight. A known airline always
    /// passes. After "flight"/"flt" a code missing from the bundled list (28 carriers) is kept
    /// only when it was typed as a code: letters only, in capitals ("flight SWA1234"), and not
    /// a common word. "flight at 5", "flight in 2 hours" and "flight dec 20" are not flights.
    private static func isAcceptedCode(_ typedCode: String, afterStrongCue: Bool) -> Bool {
        let code = typedCode.uppercased()
        if isKnownAirline(code) {
            return true
        }
        guard afterStrongCue else {
            return false
        }
        return typedCode == code
            && typedCode.allSatisfy { $0.isLetter }
            && !wordsThatAreNotAirlines.contains(code)
    }

    /// True if code is in AirlineDatabase.knownAirlineCodes (used to reject direct/weak-cue matches like SR, NE, WA).
    private static func isKnownAirline(_ airlineCode: String) -> Bool {
        AirlineDatabase.knownAirlineCodes.contains(airlineCode.uppercased())
    }
}
