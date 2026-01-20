//
//  JSONDecoderFactory.swift
//  NaarsCars
//
//  Centralized JSON decoder configuration
//  Uses shared DateFormatters for performance
//

import Foundation

/// Factory for creating pre-configured JSON decoders
enum JSONDecoderFactory {
    
    /// Create a decoder configured for Supabase date formats
    /// Handles ISO8601 with and without fractional seconds, plus DATE format
    /// Uses shared DateFormatters for performance
    static func createSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds (for TIMESTAMP fields)
            if let date = DateFormatters.iso8601WithFractional.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 without fractional seconds
            if let date = DateFormatters.iso8601Standard.date(from: dateString) {
                return date
            }
            
            // Try DATE format (YYYY-MM-DD)
            if let date = DateFormatters.apiDateFormatter.date(from: dateString) {
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
