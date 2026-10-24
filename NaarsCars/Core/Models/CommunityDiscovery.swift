//
//  CommunityDiscovery.swift
//  NaarsCars
//
//  Models of community discovery: points, service areas, search rows, the create draft and the
//  access change (supabase/migrations/20261021_0021_discovery_rpcs.sql)
//

import Foundation

/// A latitude and longitude in degrees.
struct GeoPoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    /// The point with both values rounded to `decimals` places (3 places is about 100 m).
    func rounded(toDecimals decimals: Int) -> GeoPoint {
        let factor = pow(10, Double(decimals))
        return GeoPoint(
            latitude: (latitude * factor).rounded() / factor,
            longitude: (longitude * factor).rounded() / factor
        )
    }
}

/// A community's service area: a town or ZIP code and a circle around its centre.
struct ServiceArea: Equatable, Sendable {
    let name: String
    let center: GeoPoint
    let radiusMiles: Int

    /// nil unless all four values are set (the server stores all four or none).
    static func make(name: String?, latitude: Double?, longitude: Double?, radiusMiles: Int?) -> ServiceArea? {
        guard let name, let latitude, let longitude, let radiusMiles else { return nil }
        return ServiceArea(name: name, center: GeoPoint(latitude: latitude, longitude: longitude), radiusMiles: radiusMiles)
    }
}

extension ServiceArea {
    /// The four area columns of a `communities` row or an RPC object.
    enum ColumnKeys: String, CodingKey {
        case name = "area_name"
        case latitude = "area_center_lat"
        case longitude = "area_center_lng"
        case radiusMiles = "area_radius_miles"
    }

    /// Reads the four area columns from the same object as the rest of a row; nil unless all four are present.
    static func decodeColumns(from decoder: Decoder) throws -> ServiceArea? {
        let c = try decoder.container(keyedBy: ColumnKeys.self)
        return make(
            name: try c.decodeIfPresent(String.self, forKey: .name),
            latitude: try c.decodeIfPresent(Double.self, forKey: .latitude),
            longitude: try c.decodeIfPresent(Double.self, forKey: .longitude),
            radiusMiles: try c.decodeIfPresent(Int.self, forKey: .radiusMiles)
        )
    }
}

/// One row of `search_communities_by_name`, `find_communities_near` or `check_community_area`.
/// `distanceMiles` is null for a name search; otherwise miles from the point (or between centres).
struct CommunitySearchResult: Identifiable, Equatable, Sendable, Decodable {
    let id: UUID
    let name: String
    let description: String?
    let joinPolicy: String
    let areaName: String?
    let radiusMiles: Int?
    let memberCount: Int
    let distanceMiles: Double?

    /// nil for a policy this build does not know.
    var policy: CommunityJoinPolicy? { CommunityJoinPolicy(rawValue: joinPolicy) }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case joinPolicy = "join_policy"
        case areaName = "area_name"
        case radiusMiles = "area_radius_miles"
        case memberCount = "member_count"
        case distanceMiles = "distance_miles"
    }
}

/// The `{success, communities}` answer of the three discovery list RPCs.
struct CommunitySearchResults: Decodable, Sendable {
    let communities: [CommunitySearchResult]
}

/// What `create_community_with_area` is asked to create. `area` nil creates a hidden community;
/// a set area creates a listed one. `reason` is sent only for a listed community.
struct NewCommunityDraft: Equatable, Sendable {
    var name: String
    var description: String?
    var joinPolicy: CommunityJoinPolicy
    /// IANA identifier (the device's at creation); nil is omitted.
    var timezone: String?
    var area: ServiceArea?
    var reason: String?
}

/// An owner's change to `update_community_access`. `newArea` nil keeps the stored area;
/// `reason` is sent only while listed.
struct CommunityAccessChange: Equatable, Sendable {
    var isListed: Bool
    var joinPolicy: CommunityJoinPolicy
    var newArea: ServiceArea?
    var reason: String?
}
