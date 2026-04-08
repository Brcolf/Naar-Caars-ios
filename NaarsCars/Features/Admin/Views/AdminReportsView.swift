//
//  AdminReportsView.swift
//  NaarsCars
//
//  Admin view for reviewing and acting on content reports
//

import SwiftUI

private enum ModerationAction: String, Identifiable, CaseIterable {
    case hide
    case restore
    case dismiss

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .hide:
            return "admin_reports_hide"
        case .restore:
            return "admin_reports_restore"
        case .dismiss:
            return "admin_reports_dismiss"
        }
    }

    var confirmationMessageKey: String {
        switch self {
        case .hide:
            return "admin_reports_hide_confirm_message"
        case .restore:
            return "admin_reports_restore_confirm_message"
        case .dismiss:
            return "admin_reports_dismiss_confirm_message"
        }
    }

    var notePlaceholderKey: String {
        switch self {
        case .hide:
            return "admin_reports_hide_reason_placeholder"
        case .restore, .dismiss:
            return "admin_reports_optional_note_placeholder"
        }
    }

    var systemImageName: String {
        switch self {
        case .hide:
            return "eye.slash"
        case .restore:
            return "eye"
        case .dismiss:
            return "xmark"
        }
    }

    var requiresNote: Bool {
        self == .hide
    }

    var isProminent: Bool {
        self != .dismiss
    }

    var tintColor: Color? {
        switch self {
        case .hide:
            return .red
        case .restore:
            return .green
        case .dismiss:
            return nil
        }
    }

    var localizedTitle: String {
        titleKey.localized
    }
}

private struct PendingModerationAction: Identifiable {
    let report: AdminReport
    let action: ModerationAction
    var note: String = ""

    var id: String { "\(report.reportId.uuidString)-\(action.rawValue)" }
}

@MainActor
struct AdminReportsView: View {
    @State private var reports: [AdminReport] = []
    @State private var isLoading = false
    @State private var selectedFilter: String? = "pending"
    @State private var pendingAction: PendingModerationAction?
    @State private var isSubmittingAction = false
    @State private var errorAlertMessage: String?

    private let filters: [(labelKey: String, value: String?)] = [
        ("admin_reports_filter_all", nil),
        ("admin_reports_filter_pending", "pending"),
        ("admin_reports_filter_resolved", "action_taken"),
        ("admin_reports_filter_dismissed", "dismissed")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.labelKey) { filter in
                        Button(filter.labelKey.localized) {
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
                ContentUnavailableView(
                    "admin_reports_empty_title".localized,
                    systemImage: "checkmark.shield",
                    description: Text("admin_reports_empty_message".localized)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(reports) { report in
                        ReportCardView(
                            report: report,
                            actions: availableActions(for: report),
                            isActionDisabled: isSubmittingAction,
                            onAction: { action in
                                pendingAction = PendingModerationAction(report: report, action: action)
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadReports() }
            }
        }
        .navigationTitle("admin_reports_title".localized)
        .task { await loadReports() }
        .sheet(item: $pendingAction) { action in
            NavigationStack {
                Form {
                    Section {
                        Text(action.action.confirmationMessageKey.localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }

                    Section("admin_reports_note_title".localized) {
                        TextField(
                            action.action.notePlaceholderKey.localized,
                            text: noteBinding(for: action),
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .disabled(isSubmittingAction)
                    }
                }
                .navigationTitle(action.action.localizedTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) {
                            pendingAction = nil
                        }
                        .disabled(isSubmittingAction)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action.action.localizedTitle) {
                            Task { await submitPendingAction() }
                        }
                        .disabled(
                            isSubmittingAction ||
                            (currentPendingAction(from: action).action.requiresNote &&
                             trimmedNote(for: currentPendingAction(from: action)).isEmpty)
                        )
                    }
                }
            }
            .interactiveDismissDisabled(isSubmittingAction)
            .presentationDetents([.medium])
        }
        .alert("common_error".localized, isPresented: Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(errorAlertMessage ?? "")
        }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await AdminModerationService.shared.fetchReports(status: selectedFilter)
        } catch {
            errorAlertMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitPendingAction() async {
        guard let pendingAction else { return }

        let note = trimmedNote(for: pendingAction)
        guard !pendingAction.action.requiresNote || !note.isEmpty else {
            return
        }

        isSubmittingAction = true
        do {
            try await AdminModerationService.shared.moderateContent(
                reportId: pendingAction.report.reportId,
                action: pendingAction.action.rawValue,
                notes: note.isEmpty ? nil : note
            )
            self.pendingAction = nil
            await loadReports()
        } catch {
            errorAlertMessage = error.localizedDescription
        }
        isSubmittingAction = false
    }

    private func availableActions(for report: AdminReport) -> [ModerationAction] {
        switch report.status {
        case "pending":
            return report.contentHidden ? [.hide, .restore] : [.hide, .dismiss]
        case "dismissed", "action_taken":
            return report.contentHidden ? [.restore] : [.hide]
        default:
            return []
        }
    }

    private func noteBinding(for fallbackAction: PendingModerationAction) -> Binding<String> {
        Binding(
            get: { currentPendingAction(from: fallbackAction).note },
            set: { newValue in
                guard var currentAction = pendingAction else { return }
                currentAction.note = newValue
                pendingAction = currentAction
            }
        )
    }

    private func currentPendingAction(from fallbackAction: PendingModerationAction) -> PendingModerationAction {
        pendingAction ?? fallbackAction
    }

    private func trimmedNote(for action: PendingModerationAction) -> String {
        action.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReportCardView: View {
    let report: AdminReport
    let actions: [ModerationAction]
    let isActionDisabled: Bool
    let onAction: (ModerationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(report.contentTypeLocalizationKey.localized, systemImage: report.contentTypeSystemImageName)
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
                    Text("admin_reports_reported_by".localized(with: name))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(report.createdAt, style: .relative)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            if report.contentHidden && report.status == "pending" {
                Label("admin_reports_auto_hidden".localized, systemImage: "eye.slash")
                    .font(.naarsCaption)
                    .foregroundColor(.orange)
            }

            if !actions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(actions) { action in
                        actionButton(for: action)
                    }
                }
                .padding(.top, 4)
            } else {
                Text(report.status == "action_taken" ? "admin_reports_action_taken".localized : "admin_reports_dismissed".localized)
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

    @ViewBuilder
    private func actionButton(for action: ModerationAction) -> some View {
        if action.isProminent {
            Button(action: { onAction(action) }) {
                Label(action.localizedTitle, systemImage: action.systemImageName)
            }
            .buttonStyle(.borderedProminent)
            .tint(action.tintColor ?? .accentColor)
            .controlSize(.small)
            .disabled(isActionDisabled)
        } else {
            Button(action: { onAction(action) }) {
                Label(action.localizedTitle, systemImage: action.systemImageName)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isActionDisabled)
        }
    }
}
