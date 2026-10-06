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
            return .naarsError
        case .restore:
            return .naarsSuccess
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
    @StateObject private var viewModel = AdminReportsViewModel()
    @State private var selectedFilter: String? = "pending"
    @State private var pendingAction: PendingModerationAction?
    @State private var profileUserId: UUID?

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
                            Task { await viewModel.loadReports(status: selectedFilter) }
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

            if viewModel.isLoading && viewModel.reports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.reports.isEmpty {
                ContentUnavailableView(
                    "admin_reports_empty_title".localized,
                    systemImage: "checkmark.shield",
                    description: Text("admin_reports_empty_message".localized)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.reports) { report in
                        ReportCardView(
                            report: report,
                            actions: availableActions(for: report),
                            isActionDisabled: viewModel.isSubmittingAction,
                            onAction: { action in
                                pendingAction = PendingModerationAction(report: report, action: action)
                            },
                            onViewProfile: { profileUserId = report.reportedUserId }
                        )
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.loadReports(status: selectedFilter) }
            }
        }
        .navigationTitle("admin_reports_title".localized)
        .navigationDestination(item: $profileUserId) { userId in
            PublicProfileView(userId: userId)
        }
        .task { await viewModel.loadReports(status: selectedFilter) }
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
                        .disabled(viewModel.isSubmittingAction)
                    }
                }
                .navigationTitle(action.action.localizedTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) {
                            pendingAction = nil
                        }
                        .disabled(viewModel.isSubmittingAction)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action.action.localizedTitle) {
                            Task { await submitPendingAction() }
                        }
                        .disabled(
                            viewModel.isSubmittingAction ||
                            (currentPendingAction(from: action).action.requiresNote &&
                             trimmedNote(for: currentPendingAction(from: action)).isEmpty)
                        )
                    }
                }
                // A failed action has to be reported here: an alert on the screen underneath
                // cannot present while this sheet is up.
                .alert("common_error".localized, isPresented: errorAlertBinding(sheetPresented: true)) {
                    Button("common_ok".localized, role: .cancel) {}
                } message: {
                    Text(viewModel.errorAlertMessage ?? "")
                }
            }
            .interactiveDismissDisabled(viewModel.isSubmittingAction)
            .presentationDetents([.medium])
        }
        .alert("common_error".localized, isPresented: errorAlertBinding(sheetPresented: false)) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(viewModel.errorAlertMessage ?? "")
        }
    }

    /// One error message, two places it can be shown: inside the action sheet while it is up,
    /// on the list otherwise. Only the matching alert presents, so it is never shown twice.
    private func errorAlertBinding(sheetPresented: Bool) -> Binding<Bool> {
        Binding(
            get: { viewModel.errorAlertMessage != nil && (pendingAction != nil) == sheetPresented },
            set: { if !$0 { viewModel.errorAlertMessage = nil } }
        )
    }

    private func submitPendingAction() async {
        guard let pendingAction else { return }

        let note = trimmedNote(for: pendingAction)
        guard !pendingAction.action.requiresNote || !note.isEmpty else {
            return
        }

        await viewModel.moderate(
            reportId: pendingAction.report.reportId,
            action: pendingAction.action.rawValue,
            notes: note.isEmpty ? nil : note,
            reloadStatus: selectedFilter,
            onModerated: { self.pendingAction = nil }
        )
    }

    private func availableActions(for report: AdminReport) -> [ModerationAction] {
        // A report about a member has no content to hide or restore, and the server rejects
        // everything except Dismiss for it. Restricting the member is done from their profile
        // in All Members.
        if report.targetType == "user" {
            return report.status == "pending" ? [.dismiss] : []
        }
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
    let onViewProfile: () -> Void

    /// What the reporter wrote, when they wrote anything
    private var reporterNote: String? {
        guard let note = report.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

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
                        .background(Color.naarsError.opacity(0.15))
                        .foregroundColor(.naarsError)
                        .clipShape(Capsule())
                }
            }

            if report.targetType == "user" {
                // The server sends the member's name as the "preview" of a member report;
                // label it so it does not read as a stray grey name.
                Text("admin_reports_reported_member".localized(
                    with: report.reportedUserName ?? report.contentPreview ?? "common_unknown".localized
                ))
                .font(.naarsBody)
                .foregroundColor(.primary)
            } else {
                if let preview = report.contentPreview {
                    Text(preview)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                if let author = report.reportedUserName, !author.isEmpty {
                    Text("admin_reports_content_author".localized(with: author))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }

            if let reporterNote {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("admin_reports_reporter_note".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Text(reporterNote)
                        .font(.naarsSubheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Constants.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.naarsInsetBackground)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.sm))
                .accessibilityElement(children: .combine)
            }

            if report.reportedUserId != nil {
                Button(action: onViewProfile) {
                    Label("admin_view_profile".localized, systemImage: "person.crop.circle")
                        .font(.naarsSubheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(Color.naarsPrimary)
            }

            HStack {
                if let name = report.reporterName {
                    Text("admin_reports_reported_by".localized(with: name))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(report.createdAt.timeAgo)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            if report.contentHidden && report.status == "pending" {
                Label("admin_reports_auto_hidden".localized, systemImage: "eye.slash")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsWarning)
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
                    .foregroundColor(report.status == "action_taken" ? .naarsError : .naarsSuccess)
            }
        }
        .padding(.vertical, 6)
    }

    private var reportTypeBadgeColor: Color {
        switch report.reportType {
        case "harassment": return .naarsError
        case "spam": return .naarsWarning
        case "inappropriate_content": return .purple
        case "scam": return .naarsError
        default: return .secondary
        }
    }

    @ViewBuilder
    private func actionButton(for action: ModerationAction) -> some View {
        if action.isProminent {
            Button(action: { onAction(action) }) {
                Label(action.localizedTitle, systemImage: action.systemImageName)
            }
            .buttonStyle(.bordered)
            .tint(action.tintColor ?? .naarsPrimary)
            .fontWeight(.semibold)
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
