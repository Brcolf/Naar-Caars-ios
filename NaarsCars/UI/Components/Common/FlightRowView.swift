//
//  FlightRowView.swift
//  NaarsCars
//
//  Displays extracted flight info with tappable flight number (opens browser search for status).
//

import SwiftUI

/// Display style for the flight row
enum FlightRowStyle {
    /// Single line: "Flight: DL1234" (flight number tappable)
    case compact
    /// Multi-line: label, flight number (tappable), optional airline and route
    case detail
}

/// Row showing flight number and optional airline/route; flight number opens flight status search in browser.
struct FlightRowView: View {
    let flightInfo: FlightInfo
    var style: FlightRowStyle = .compact

    private var statusSearchURL: URL? {
        URL(string: Constants.URLs.flightStatusSearch(normalizedFlightNumber: flightInfo.normalizedFlightNumber))
    }

    var body: some View {
        switch style {
        case .compact:
            compactRow
        case .detail:
            detailRow
        }
    }

    private var compactRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "airplane")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
            Text("ride_detail_flight".localized + ": ")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
            if let url = statusSearchURL {
                Link(destination: url) {
                    Text(flightInfo.normalizedFlightNumber)
                        .font(.naarsCaption)
                        .fontWeight(.medium)
                        .foregroundColor(.naarsPrimary)
                }
                .accessibilityLabel(flightInfo.normalizedFlightNumber)
                .accessibilityHint("ride_flight_search_hint".localized)
                .accessibilityIdentifier("ride.flightStatusLink")
            } else {
                Text(flightInfo.normalizedFlightNumber)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
            }
            Spacer()
        }
    }

    private var detailRow: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            HStack(spacing: 8) {
                Label("ride_detail_flight".localized, systemImage: "airplane")
                    .font(.naarsHeadline)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let url = statusSearchURL {
                    Link(destination: url) {
                        Text(flightInfo.normalizedFlightNumber)
                            .font(.naarsTitle3)
                            .fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                    }
                    .accessibilityLabel(flightInfo.normalizedFlightNumber)
                    .accessibilityHint("ride_flight_search_hint".localized)
                    .accessibilityIdentifier("ride.flightStatusLink")
                } else {
                    Text(flightInfo.normalizedFlightNumber)
                        .font(.naarsTitle3)
                        .fontWeight(.semibold)
                }
                if let name = flightInfo.airlineName, !name.isEmpty {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(name)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
            }
            if let orig = flightInfo.originAirport, let dest = flightInfo.destinationAirport {
                HStack(spacing: 4) {
                    Text(orig.name)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(dest.name)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else if let o = flightInfo.originAirportIATA, let d = flightInfo.destinationAirportIATA {
                Text("\(o) → \(d)")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
