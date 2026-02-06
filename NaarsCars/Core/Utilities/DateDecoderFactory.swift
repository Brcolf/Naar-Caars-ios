//
//  DateDecoderFactory.swift
//  NaarsCars
//
//  Shared JSON decoder factory configured for Supabase date formats
//  Eliminates duplicate decoder creation across services
//

import Foundation

/// Factory for creating JSON decoders with Supabase-compatible date decoding strategies
///
/// Supabase returns dates in multiple formats depending on the column type:
/// - TIMESTAMPTZ: ISO8601 with fractional seconds (e.g. "2024-01-15T10:30:00.123456+00:00")
/// - TIMESTAMP: ISO8601 without fractional seconds (e.g. "2024-01-15T10:30:00+00:00")
/// - DATE: Simple date format (e.g. "2024-01-15")
///
/// Used by RideService, FavorService, MessageService, and others.
enum DateDecoderFactory {

    /// Create a JSON decoder that handles all Supabase date formats
    /// including ISO8601 with/without fractional seconds and plain date strings
    static func makeSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds (for TIMESTAMPTZ fields)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try DATE format (YYYY-MM-DD) - use local timezone to avoid off-by-one day issues
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = .current
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }

    /// Create a JSON decoder optimized for messaging (no plain date support needed)
    /// Handles ISO8601 with and without fractional seconds
    static func makeMessagingDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = formatter.date(from: dateString) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
}
