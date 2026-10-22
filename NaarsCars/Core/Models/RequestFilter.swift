//
//  RequestFilter.swift
//  NaarsCars
//
//  Filter type for unified requests dashboard
//

import Foundation

/// Filter type for unified requests dashboard
enum RequestFilter: String, CaseIterable {
    case open = "Open Requests"
    case mine = "My Requests"
    /// The Helping tile: requests the person helps with. The raw value stays, because it is the
    /// tile's accessibility identifier (`requests.filter.Claimed Requests`).
    case claimed = "Claimed Requests"

    /// The tile titles: Open, Mine, Helping.
    var localizedKey: String {
        switch self {
        case .open: return "requests_tile_open"
        case .mine: return "requests_tile_mine"
        case .claimed: return "requests_tile_helping"
        }
    }
}


