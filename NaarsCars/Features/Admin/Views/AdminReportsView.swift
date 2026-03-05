//
//  AdminReportsView.swift
//  NaarsCars
//
//  Admin view for reviewing and acting on content reports
//

import SwiftUI

@MainActor
struct AdminReportsView: View {
    @State private var reports: [AdminReport] = []
    @State private var isLoading = false
    @State private var selectedFilter: String? = "pending"
    @State private var error: String?

    private let filters: [(label: String, value: String?)] = [
        ("All", nil),
        ("Pending", "pending"),
        ("Resolved", "action_taken"),
        ("Dismissed", "dismissed")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.label) { filter in
                        Button(filter.label) {
                            selectedFilter = filter.value
                            Task { await loadReports() }
                        }
                        .font(.naarsSubheadline)
                        .fontWeight(selectedFilter == filter.value ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selectedFilter == filter.value ? Color.naarsPrimary : Color(.systemGray5))
                        )
                        .foregroundColor(selectedFilter == filter.value ? .white : .primary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if isLoading && reports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reports.isEmpty {
                ContentUnavailableView("No Reports", systemImage: "checkmark.shield", description: Text("No reports to review"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(reports) { report in
                        ReportCardView(report: report, onAction: { action in
                            Task { await handleAction(action, report: report) }
                        })
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadReports() }
            }
        }
        .navigationTitle("Reports")
        .task { await loadReports() }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await AdminModerationService.shared.fetchReports(status: selectedFilter)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func handleAction(_ action: String, report: AdminReport) async {
        do {
            try await AdminModerationService.shared.moderateContent(reportId: report.reportId, action: action)
            await loadReports()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReportCardView: View {
    let report: AdminReport
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(report.contentTypeLabel, systemImage: report.isPost ? "text.bubble" : "text.quote")
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(report.reportTypeDisplay)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(reportTypeBadgeColor.opacity(0.15))
                    .foregroundColor(reportTypeBadgeColor)
                    .clipShape(Capsule())

                if report.reportCount > 1 {
                    Text("\(report.reportCount)")
                        .font(.naarsCaption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            if let preview = report.contentPreview {
                Text(preview)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack {
                if let name = report.reporterName {
                    Text("Reported by \(name)")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(report.createdAt, style: .relative)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            if report.contentHidden && report.status == "pending" {
                Label("Auto-hidden", systemImage: "eye.slash")
                    .font(.naarsCaption)
                    .foregroundColor(.orange)
            }

            if report.status == "pending" {
                HStack(spacing: 12) {
                    if !report.contentHidden {
                        Button(action: { onAction("hide") }) {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Button(action: { onAction("restore") }) {
                            Label("Restore", systemImage: "eye")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }

                    Button(action: { onAction("dismiss") }) {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            } else {
                Text(report.status == "action_taken" ? "Action taken" : "Dismissed")
                    .font(.naarsCaption)
                    .foregroundColor(report.status == "action_taken" ? .red : .green)
            }
        }
        .padding(.vertical, 6)
    }

    private var reportTypeBadgeColor: Color {
        switch report.reportType {
        case "harassment": return .red
        case "spam": return .orange
        case "inappropriate_content": return .purple
        case "scam": return .red
        default: return .secondary
        }
    }
}
