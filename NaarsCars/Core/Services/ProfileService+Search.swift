//
//  ProfileService+Search.swift
//  NaarsCars
//
//  Member search through the public_profiles view
//

import Foundation
import Supabase

extension ProfileService {

    /// Search approved members by name through the public_profiles view (case-insensitive substring match).
    /// - Parameters:
    ///   - query: Trimmed, non-empty search text (callers enforce the minimum length)
    ///   - limit: Maximum rows (Constants.PageSizes.userSearch)
    func searchPublicProfiles(query: String, limit: Int) async throws -> [Profile] {
        // Search public profiles by name (the public_profiles view has no email column)
        // PostgREST .or() syntax: "column.operator.value,column.operator.value"
        // Use * as wildcard for ilike (case-insensitive LIKE)
        // Escape special characters for PostgREST ilike pattern
        // In PostgREST, * is the wildcard for ilike, so we need to escape it if it appears in the query
        let escapedQuery = query.replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let searchPattern = "*\(escapedQuery)*"

        AppLogger.info("messaging", "ProfileService searching public profiles for: '\(query)' (pattern: '\(searchPattern)')")

        // Select all view columns (Profile's decoder defaults any column the view lacks)
        // Using .select() without arguments gets all columns, matching other services
        let response = try await SupabaseService.shared.client
            .from("public_profiles")
            .select()
            .or("name.ilike.\(searchPattern)")
            .eq("approved", value: true)
            .limit(limit)
            .execute()

        // Use custom date decoder to handle various date formats
        // Profile model handles snake_case via CodingKeys
        let decoder = JSONDecoder()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            dateFormatter.formatOptions = [.withInternetDateTime]
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            // Try YYYY-MM-DD format
            let simpleFormatter = DateFormatter()
            simpleFormatter.dateFormat = "yyyy-MM-dd"
            simpleFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = simpleFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }

        return try decoder.decode([Profile].self, from: response.data)
    }
}
