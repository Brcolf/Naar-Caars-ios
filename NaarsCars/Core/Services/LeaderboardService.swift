//
//  LeaderboardService.swift
//  NaarsCars
//
//  Service for leaderboard operations using server-side calculation
//

import Foundation
import Supabase

/// Time period for leaderboard filtering
enum LeaderboardPeriod: String, Codable, CaseIterable {
    case allTime = "All Time"
    case thisYear = "This Year"
    case thisQuarter = "This Quarter"
    case thisMonth = "This Month"
    
    var displayName: String {
        rawValue
    }
}

/// Extension for date range calculation
extension LeaderboardPeriod {
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
            
        case .thisYear:
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)) else {
                return (Date(timeIntervalSince1970: 0), now)
            }
            return (start, now)
            
        case .thisQuarter:
            let month = calendar.component(.month, from: now)
            let quarter = (month - 1) / 3
            var components = calendar.dateComponents([.year], from: now)
            components.month = quarter * 3 + 1
            components.day = 1
            guard let start = calendar.date(from: components) else {
                return (Date(timeIntervalSince1970: 0), now)
            }
            return (start, now)
            
        case .thisMonth:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return (Date(timeIntervalSince1970: 0), now)
            }
            return (start, now)
        }
    }
}

/// Parameters for Supabase RPC `get_leaderboard`.
/// Declared at top level to avoid unintended global actor isolation.
private struct LeaderboardParams: Encodable, Sendable {
    let start_date: String
    let end_date: String

    private enum CodingKeys: String, CodingKey {
        case start_date
        case end_date
    }

    // Make Encodable conformance explicitly nonisolated to avoid main-actor isolated synthesis
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start_date, forKey: .start_date)
        try container.encode(end_date, forKey: .end_date)
    }
}

/// Service for leaderboard operations
/// Uses server-side database function for efficient calculation
final class LeaderboardService {
    
    // MARK: - Singleton
    
    static let shared = LeaderboardService()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Leaderboard
    
    /// Fetch leaderboard entries for a given time period
    /// Uses server-side database function for efficient calculation
    /// - Parameter period: Time period filter
    /// - Returns: Array of leaderboard entries sorted by requests fulfilled (descending)
    /// - Throws: AppError if fetch fails
    func fetchLeaderboard(period: LeaderboardPeriod) async throws -> [LeaderboardEntry] {
        let (startDate, endDate) = period.dateRange
        
        // Format dates as YYYY-MM-DD for PostgreSQL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        let params = LeaderboardParams(start_date: startDateString, end_date: endDateString)
        
        // Access supabase client
        let client = await SupabaseService.shared.client
        
        let response = try await client
            .rpc("get_leaderboard", params: params)
            .execute()
        
        // Decode entries
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var entries = try decoder.decode([LeaderboardEntry].self, from: response.data)
        
        // Add rank numbers (1-indexed)
        for index in entries.indices {
            entries[index].rank = index + 1
        }
        
        // Filter out users with 0 fulfilled requests (only show active users)
        entries = entries.filter { $0.requestsFulfilled > 0 || $0.requestsMade > 0 }
        
        AppLogger.info("leaderboard", "Fetched \(entries.count) leaderboard entries for period: \(period.displayName)")
        return entries
    }
    
    /// Find current user's rank in leaderboard
    /// - Parameters:
    ///   - userId: Current user's ID
    ///   - period: Time period filter
    /// - Returns: User's rank if found, nil if not in top 100
    /// - Throws: AppError if fetch fails
    func findCurrentUserRank(userId: UUID, period: LeaderboardPeriod) async throws -> Int? {
        let entries = try await fetchLeaderboard(period: period)
        
        if let index = entries.firstIndex(where: { $0.userId == userId }) {
            return index + 1 // 1-indexed rank
        }
        
        return nil
    }
    
}

