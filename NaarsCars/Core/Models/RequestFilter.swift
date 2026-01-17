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
    case claimed = "Claimed by Me"
    
    var localizedKey: String {
        switch self {
        case .open: return "requests_filter_open"
        case .mine: return "requests_filter_mine"
        case .claimed: return "requests_filter_claimed"
        }
    }
}


