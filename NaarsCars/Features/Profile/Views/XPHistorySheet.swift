//
//  XPHistorySheet.swift
//  NaarsCars
//
//  Sheet showing user's XP earning history
//

import SwiftUI

struct XPHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [XPEvent] = []
    @State private var isLoading = false
    @State private var error: String?

    let totalXP: Int

    private let profileService: any ProfileServiceProtocol = ProfileService.shared

    /// Group events by month for sectioned display
    private var groupedEvents: [(String, [XPEvent])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        let grouped = Dictionary(grouping: events) { event in
            formatter.string(from: event.createdAt)
        }

        return grouped.sorted { lhs, rhs in
            guard let lhsDate = lhs.value.first?.createdAt,
                  let rhsDate = rhs.value.first?.createdAt else { return false }
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(totalXP)")
                        .font(.system(size: 48, weight: .bold))
                    Text("xp_total_earned_label".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding()

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if events.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "bolt.fill",
                        title: "xp_empty_title".localized,
                        message: "xp_empty_message".localized
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(groupedEvents, id: \.0) { month, monthEvents in
                            Section(header: Text(month)) {
                                ForEach(monthEvents) { event in
                                    HStack {
                                        Text("+\(event.amount)")
                                            .font(.naarsHeadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.naarsWarning)
                                            .frame(width: 50, alignment: .leading)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.description ?? (event.sourceType == "ride" ? "xp_source_ride".localized : "xp_source_favor".localized))
                                                .font(.naarsBody)
                                                .lineLimit(1)
                                            Text(event.createdAt.timeAgo)
                                                .font(.naarsCaption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: sourceIcon(for: event.sourceType))
                                            .foregroundColor(.secondary)
                                            .font(.naarsCaption)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("xp_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common_done".localized) { dismiss() }
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            events = try await profileService.fetchUserXPEvents()
        } catch {
            self.error = "xp_load_error".localized
            AppLogger.error("profile", "XP history sheet error: \(error.localizedDescription)")
        }
    }

    private func sourceIcon(for sourceType: String) -> String {
        switch sourceType {
        case "ride_fulfilled": return "car.fill"
        case "favor_fulfilled": return "hand.raised.fill"
        case "ride_requested", "favor_requested": return "plus.circle.fill"
        case "first_ride", "first_favor": return "star.circle.fill"
        case "review_received": return "star.fill"
        default: return "bolt.fill"
        }
    }
}
