//
//  AdminActiveRidesOverlay.swift
//  NaarsCars
//
//  Overlay listing all unfinished rides and favors
//

import SwiftUI

struct AdminActiveRidesOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [ActiveRequestRow] = []
    @State private var isLoading = false
    @State private var error: String?

    private let adminService = AdminService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    Text(error)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.naarsSuccess)
                        Text("admin_no_active_requests".localized)
                            .font(.naarsHeadline)
                        Text("admin_all_completed".localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                // Type badge. A tinted chip, not white text on the accent: the
                                // accents turn light in dark mode and white text on them was unreadable.
                                NaarsChip(
                                    text: request.isRide ? "common_ride".localized : "common_favor".localized,
                                    tint: request.isRide ? Color.rideAccent : Color.favorAccent
                                )

                                Text(request.posterName ?? "common_unknown".localized)
                                    .font(.naarsHeadline)
                                if let claimer = request.claimerName {
                                    Image(systemName: "arrow.right")
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                    Text(claimer)
                                        .font(.naarsHeadline)
                                }
                                Spacer()
                                statusBadge(request.status)
                            }

                            // Title/route info
                            if request.isRide {
                                HStack(spacing: 4) {
                                    Text(request.title)
                                    Image(systemName: "arrow.right")
                                        .font(.naarsCaption2)
                                    Text(request.subtitle ?? "")
                                }
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            } else {
                                Text(request.title)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Text(formatDate(request.date))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("admin_active_requests_title".localized)
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
            requests = try await adminService.fetchActiveRequests()
        } catch {
            self.error = "common_load_error".localized
            AppLogger.error("admin", "Active requests overlay error: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = switch status {
        case "open": ("admin_status_open".localized, .naarsSuccess)
        case "pending": ("admin_status_pending".localized, .naarsWarning)
        case "confirmed": ("admin_status_claimed".localized, .naarsPrimary)
        default: (status.capitalized, .naarsTextSecondary)
        }

        NaarsChip(text: text, tint: color)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
