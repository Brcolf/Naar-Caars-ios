//
//  CommunityReportsView.swift
//  NaarsCars
//
//  One community's reports for its owners and admins: hide, restore and dismiss. No line names
//  or links a reporter (INV-P2).
//

import SwiftUI

private extension CommunityModerationAction {
    var titleKey: String {
        switch self {
        case .hide: return "admin_reports_hide"
        case .restore: return "admin_reports_restore"
        case .dismiss: return "admin_reports_dismiss"
        }
    }

    var confirmationMessageKey: String {
        switch self {
        case .hide: return "admin_reports_hide_confirm_message"
        case .restore: return "admin_reports_restore_confirm_message"
        case .dismiss: return "admin_reports_dismiss_confirm_message"
        }
    }

    var notePlaceholderKey: String {
        self == .hide ? "admin_reports_hide_reason_placeholder" : "admin_reports_optional_note_placeholder"
    }

    var systemImageName: String {
        switch self {
        case .hide: return "eye.slash"
        case .restore: return "eye"
        case .dismiss: return "xmark"
        }
    }

    var requiresNote: Bool { self == .hide }

    var tintColor: Color {
        switch self {
        case .hide: return .naarsError
        case .restore: return .naarsSuccess
        case .dismiss: return .naarsPrimary
        }
    }
}

private extension CommunityReport {
    var targetLabelKey: String {
        switch targetType {
        case "town_hall_post": return "admin_reports_target_post"
        case "town_hall_comment": return "admin_reports_target_comment"
        case "ride": return "admin_reports_target_ride"
        case "favor": return "admin_reports_target_favor"
        default: return "admin_reports_target_user"
        }
    }

    var targetSystemImageName: String {
        switch targetType {
        case "town_hall_post": return "text.bubble"
        case "town_hall_comment": return "text.quote"
        case "ride": return "car.fill"
        case "favor": return "hand.raised.fill"
        default: return "person.fill"
        }
    }

    var reportTypeTint: Color? {
        switch MessageService.ReportType(rawValue: reportType) {
        case .harassment?, .scam?: return .naarsError
        case .spam?: return .naarsWarning
        case .inappropriateContent?, .other?, nil: return nil
        }
    }

    /// What the reporter wrote about the content, when they wrote anything.
    var reporterNote: String? {
        guard let note = description?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note
    }
}

/// The action a person picked on a report, with the note typed in the sheet.
struct PendingCommunityModeration: Identifiable {
    let report: CommunityReport
    let action: CommunityModerationAction
    var note: String = ""

    var id: String { "\(report.reportId.uuidString)-\(action.rawValue)" }
}

/// The community's reports. No NavigationStack: always pushed (Admin panel).
struct CommunityReportsView: View {
    let communityName: String?
    @StateObject private var viewModel: CommunityReportsViewModel
    @State private var pendingAction: PendingCommunityModeration?
    /// A failed send, shown inside the sheet that stays open (the list's banner sits under it).
    @State private var sheetErrorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        communityId: UUID,
        communityName: String?,
        viewModel: @autoclosure @escaping () -> CommunityReportsViewModel? = nil
    ) {
        self.communityName = communityName
        _viewModel = StateObject(wrappedValue: viewModel() ?? CommunityReportsViewModel(communityId: communityId))
    }

    var body: some View {
        Group {
            switch viewModel.access {
            case .notAdmin:
                notAdminState
            case .checking, .allowed:
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_reports_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .onChange(of: viewModel.filter) { _, _ in
            Task { await viewModel.load() }
        }
        .errorBanner(message: $viewModel.actionErrorMessage)
        .sheet(item: $pendingAction, onDismiss: { sheetErrorMessage = nil }) { pending in
            CommunityReportActionSheet(
                pending: pending,
                note: noteBinding,
                isActing: viewModel.actingOnReportId != nil,
                onCancel: { pendingAction = nil },
                onConfirm: confirmPendingAction
            )
            .errorBanner(message: $sheetErrorMessage)
        }
    }

    // MARK: - States

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if let communityName {
                    Text(communityName)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }

                filterBar

                // At accessibility sizes the icon would take a third of the line; the text keeps it.
                Label("community_reports_scope_note".localized, systemImage: "eye.slash")
                    .labelStyle(ScopeNoteLabelStyle(showsIcon: !dynamicTypeSize.isAccessibilitySize))
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .accessibilityIdentifier("community.reports.scopeNote")

                rows
            }
            .padding()
        }
        .refreshable { await viewModel.load() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.Spacing.sm) {
                ForEach(CommunityReportFilter.allCases, id: \.self) { filter in
                    let isSelected = viewModel.filter == filter
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Text(filter.labelKey.localized)
                            .font(.naarsSubheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, Constants.Spacing.ms)
                            .padding(.vertical, Constants.Spacing.sm)
                            .background(Capsule().fill(isSelected ? Color.naarsPrimary : Color.naarsCardBackground))
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter.labelKey.localized)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("community.reports.filter.\(filter)")
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.reports.isEmpty {
            if viewModel.isLoading || (viewModel.access == .checking && viewModel.loadError == nil) {
                skeleton
            } else if let loadError = viewModel.loadError {
                ErrorView(error: loadError) {
                    Task { await viewModel.load() }
                }
            } else {
                EmptyStateView(
                    icon: "checkmark.shield",
                    title: "community_reports_empty_title".localized,
                    message: "community_reports_empty_body".localized
                )
                .accessibilityIdentifier("community.reports.empty")
            }
        } else {
            ForEach(viewModel.reports) { report in
                CommunityReportCard(
                    report: report,
                    actions: CommunityReportActions.available(for: report),
                    isActionDisabled: viewModel.actingOnReportId != nil,
                    onAction: { action in
                        pendingAction = PendingCommunityModeration(report: report, action: action)
                    }
                )
            }
        }
    }

    private var notAdminState: some View {
        VStack(spacing: Constants.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("community_pending_not_admin".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("community.reports.notAdmin")
    }

    private var skeleton: some View {
        VStack(spacing: Constants.Spacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    SkeletonRectangle(width: 120, height: 16)
                    SkeletonRectangle(width: 240, height: 14)
                    SkeletonRectangle(width: 180, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
        .disabled(true)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private var noteBinding: Binding<String> {
        Binding(
            get: { pendingAction?.note ?? "" },
            set: { newValue in
                guard var current = pendingAction else { return }
                current.note = newValue
                pendingAction = current
            }
        )
    }

    private func confirmPendingAction() {
        // Copy the state before the Task reads it.
        guard let pending = pendingAction else { return }
        sheetErrorMessage = nil
        Task {
            let outcome = await viewModel.moderate(pending.report, action: pending.action, reason: pending.note)
            if outcome == .failed {
                // Nothing reached the server: the sheet stays open with the note as typed, and the
                // failure is shown in the sheet instead of under it.
                sheetErrorMessage = viewModel.actionErrorMessage
                viewModel.actionErrorMessage = nil
                return
            }
            // Success or refusal, the sheet closes: a refusal is shown in the list's banner and
            // the reload has removed the refused button.
            pendingAction = nil
        }
    }
}

private struct ScopeNoteLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.Spacing.sm) {
            if showsIcon { configuration.icon }
            configuration.title
        }
    }
}

// MARK: - Card

private struct CommunityReportCard: View {
    let report: CommunityReport
    let actions: [CommunityModerationAction]
    let isActionDisabled: Bool
    let onAction: (CommunityModerationAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            header
            details

            if let note = report.reporterNote {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("admin_reports_reporter_note".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Text(note)
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

            Text(report.createdAt.timeAgo)
                .font(.naarsCaption)
                .foregroundColor(.secondary)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("community.reports.card")
    }

    /// At accessibility sizes the type chip and count move under the target label.
    @ViewBuilder
    private var header: some View {
        let target = Label(report.targetLabelKey.localized, systemImage: report.targetSystemImageName)
            .font(.naarsSubheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
        let tags = HStack(spacing: Constants.Spacing.sm) {
            NaarsChip(text: report.reportTypeLabel, tint: report.reportTypeTint)
            if report.reportCount > 1 {
                NotificationBadge(count: report.reportCount)
                    .accessibilityLabel(String(format: "community_reports_count_accessibility".localized, report.reportCount))
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                target
                tags
            }
        } else {
            HStack(alignment: .center, spacing: Constants.Spacing.sm) {
                target
                Spacer(minLength: Constants.Spacing.xs)
                tags
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if report.isPersonReport {
            Text("admin_reports_reported_member".localized(
                with: report.reportedUserName ?? report.contentPreview ?? "common_unknown".localized
            ))
            .font(.naarsBody)
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            if let preview = report.contentPreview, !preview.isEmpty {
                Text(preview)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            if let author = report.authorName, !author.isEmpty {
                Text("admin_reports_content_author".localized(with: author))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if report.platformHandled {
            Label("community_reports_platform_handled".localized, systemImage: "checkmark.shield")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("community.reports.platformHandled")
        } else {
            if report.contentHidden && !report.canRestore {
                Label("community_reports_restore_platform_only".localized, systemImage: "eye.slash")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("community.reports.restorePlatformOnly")
            }
            if actions.isEmpty {
                Text(report.status == "action_taken"
                     ? "admin_reports_action_taken".localized
                     : "admin_reports_dismissed".localized)
                    .font(.naarsCaption)
                    .foregroundColor(report.status == "action_taken" ? .naarsError : .naarsSuccess)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Constants.Spacing.ms) { actionButtons }
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) { actionButtons }
                }
                .padding(.top, Constants.Spacing.xs)
            }
        }
    }

    private var actionButtons: some View {
        ForEach(actions, id: \.self) { action in
            Button { onAction(action) } label: {
                Label(action.titleKey.localized, systemImage: action.systemImageName)
            }
            .buttonStyle(.bordered)
            .tint(action.tintColor)
            .fontWeight(action == .dismiss ? .regular : .semibold)
            .controlSize(.small)
            .disabled(isActionDisabled)
            .accessibilityLabel(action.titleKey.localized)
            .accessibilityIdentifier("community.reports.action.\(action.rawValue)")
        }
    }
}

// MARK: - Action sheet

/// The confirmation for one action: the confirmation text, a note (required for Hide) and, under
/// Hide or a person report's Dismiss, one line about what follows.
struct CommunityReportActionSheet: View {
    let pending: PendingCommunityModeration
    @Binding var note: String
    let isActing: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var action: CommunityModerationAction { pending.action }

    private var canConfirm: Bool {
        !isActing && (!action.requiresNote || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(action.confirmationMessageKey.localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField(action.notePlaceholderKey.localized, text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(isActing)
                        .accessibilityLabel("admin_reports_note_title".localized)
                        .accessibilityIdentifier("community.reports.note")
                } header: {
                    Text("admin_reports_note_title".localized)
                } footer: {
                    if action == .hide {
                        Text("community_reports_hide_author_told".localized)
                    } else if action == .dismiss && pending.report.isPersonReport {
                        Text("community_reports_person_dismiss_hint".localized)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .navigationTitle(action.titleKey.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized, action: onCancel)
                        .disabled(isActing)
                        .accessibilityLabel("common_cancel".localized)
                        .accessibilityIdentifier("community.reports.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action.titleKey.localized, action: onConfirm)
                        .disabled(!canConfirm)
                        .accessibilityLabel(action.titleKey.localized)
                        .accessibilityIdentifier("community.reports.confirm")
                }
            }
        }
        .interactiveDismissDisabled(isActing)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
enum CommunityReportsPreview {
    /// Ballard (owned) by default; `role` replaces the caller's role there.
    static func viewModel(
        role: CommunityRole = .owner,
        reports: [CommunityReport] = PreviewAdminService.sampleReports,
        filter: CommunityReportFilter = .all
    ) -> CommunityReportsViewModel {
        let community = PreviewCommunityService()
        let context = CommunityContext(
            service: community,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { false }
        )
        let ballard = PreviewCommunityService.sampleMemberships[1]
        let row = CommunityMembership(
            communityId: ballard.communityId, name: ballard.name, description: ballard.description,
            role: role, status: ballard.status, isPrimary: ballard.isPrimary, joinPolicy: ballard.joinPolicy,
            isPublic: ballard.isPublic, isDefault: ballard.isDefault, membersCanInvite: ballard.membersCanInvite,
            timezone: ballard.timezone, canInvite: ballard.canInvite, memberCount: ballard.memberCount,
            pendingCount: ballard.pendingCount, notificationsMuted: ballard.notificationsMuted,
            mutedUntil: ballard.mutedUntil, joinedAt: ballard.joinedAt, activatedAt: ballard.activatedAt
        )
        context.debugSetMemberships([PreviewCommunityService.sampleMemberships[0], row])
        let admin = PreviewAdminService()
        admin.reports = reports
        let vm = CommunityReportsViewModel(communityId: row.communityId, adminService: admin, communityContext: context)
        vm.filter = filter
        return vm
    }

    static var communityId: UUID { PreviewCommunityService.sampleMemberships[1].communityId }
    static var communityName: String { PreviewCommunityService.sampleMemberships[1].name }
}

#Preview("Reports, all") {
    NavigationStack {
        CommunityReportsView(
            communityId: CommunityReportsPreview.communityId,
            communityName: CommunityReportsPreview.communityName,
            viewModel: CommunityReportsPreview.viewModel()
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        CommunityReportsView(
            communityId: CommunityReportsPreview.communityId,
            communityName: CommunityReportsPreview.communityName,
            viewModel: CommunityReportsPreview.viewModel(reports: [])
        )
    }
}

#Preview("Not admin") {
    NavigationStack {
        CommunityReportsView(
            communityId: CommunityReportsPreview.communityId,
            communityName: CommunityReportsPreview.communityName,
            viewModel: CommunityReportsPreview.viewModel(role: .member)
        )
    }
}

#Preview("Hide sheet") {
    @Previewable @State var note = ""
    CommunityReportActionSheet(
        pending: PendingCommunityModeration(report: PreviewAdminService.sampleReports[0], action: .hide),
        note: $note,
        isActing: false,
        onCancel: {},
        onConfirm: {}
    )
}
#endif
