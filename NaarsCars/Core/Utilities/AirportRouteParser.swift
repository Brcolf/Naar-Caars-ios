//
//  AirportRouteParser.swift
//  NaarsCars
//
//  Extracts origin/destination airport codes from free text (e.g. SEA->LAX, Seattle to LAX).
//

import Foundation

/// Extracts origin and destination IATA codes from text when both are present.
enum AirportRouteParser {

    /// IATA code: exactly 3 uppercase letters
    private static let iataPattern = "[A-Z]{3}"

    /// Matches: SEA->LAX, SEA to LAX, SEA-LAX, SEA/LAX, SEA - LAX. Case-insensitive for "to".
    /// Does not match a single airport (no guess for the other).
    /// - Returns: (originIATA, destinationIATA) if two distinct 3-letter codes found with a known separator; nil otherwise.
    static func extractAirports(from text: String) -> (originIATA: String, destinationIATA: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Separators: "->", " to ", "-", "/", " - "
        let separators = ["->", " to ", "-", "/", " - "]
        var best: (originIATA: String, destinationIATA: String)?

        for sep in separators {
            let parts: [String]
            if sep == " to " {
                guard let r = trimmed.range(of: sep, options: .caseInsensitive) else { continue }
                parts = [
                    String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespaces),
                    String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                ]
            } else {
                parts = trimmed.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            }
            guard parts.count >= 2 else { continue }
            let first = parts[0].uppercased()
            let second = parts[1].uppercased()
            let o = extractOneIATA(from: first)
            let d = extractOneIATA(from: second)
            if let o = o, let d = d, o != d, o.count == 3, d.count == 3 {
                best = (originIATA: o, destinationIATA: d)
                break
            }
        }

        return best
    }

    /// From a string like "SEA" or "Seattle" or "LAX airport", extract a single 3-letter IATA if present.
    private static func extractOneIATA(from segment: String) -> String? {
        let uppercased = segment.uppercased()
        guard let regex = try? NSRegularExpression(pattern: "\\b" + iataPattern + "\\b"),
              let match = regex.firstMatch(in: uppercased, range: NSRange(uppercased.startIndex..., in: uppercased)),
              let r = Range(match.range, in: uppercased) else {
            return nil
        }
        return String(uppercased[r])
    }
}
