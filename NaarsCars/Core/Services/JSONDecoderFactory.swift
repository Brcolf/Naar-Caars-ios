//
//  JSONDecoderFactory.swift
//  NaarsCars
//
//  Centralized JSON decoder configuration
//

import Foundation

/// Factory for creating pre-configured JSON decoders
enum JSONDecoderFactory {
    
    /// Create a decoder configured for Supabase date formats
    /// Handles ISO8601 with and without fractional seconds, plus DATE format
    static func createSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let formatterStandard = ISO8601DateFormatter()
        formatterStandard.formatOptions = [.withInternetDateTime]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds (for TIMESTAMP fields)
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 without fractional seconds
            if let date = formatterStandard.date(from: dateString) {
                return date
            }
            
            // Try DATE format (YYYY-MM-DD)
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
    
    /// Create a standard decoder with ISO8601 date decoding
    static func createStandardDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
