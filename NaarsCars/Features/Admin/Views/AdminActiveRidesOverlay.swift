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
                        Text("No active requests")
                            .font(.naarsHeadline)
                        Text("All rides and favors have been completed")
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                // Type badge
                                Text(request.isRide ? "Ride" : "Favor")
                                    .font(.naarsCaption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(request.isRide ? Color.naarsPrimary : Color.orange)
                                    .cornerRadius(4)

                                Text(request.posterName ?? "Unknown")
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
                                        .font(.caption2)
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
            .navigationTitle("Active Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
            self.error = "Failed to load data"
            AppLogger.error("admin", "Active requests overlay error: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = switch status {
        case "open": ("Open", .naarsSuccess)
        case "pending": ("Pending", .naarsWarning)
        case "confirmed": ("Claimed", .naarsPrimary)
        default: (status.capitalized, .gray)
        }

        Text(text)
            .font(.naarsCaption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
