//
//  CommunityReportsViewModel.swift
//  NaarsCars
//
//  One community's reports for its owners and admins: hide, restore and dismiss, and never the
//  reporter (INV-P2: CommunityReport has no reporter field)
//

internal import Combine
import Foundation

/// The status filter of the community reports list. Labels reuse `admin_reports_filter_*`.
enum CommunityReportFilter: CaseIterable, Hashable {
    case pending, all, resolved, dismissed

    /// The `p_status` sent to `get_community_reports`; nil = every status.
    var status: String? {
        switch self {
        case .pending: return "pending"
        case .all: return nil
        case .resolved: return "action_taken"
        case .dismissed: return "dismissed"
        }
    }

    var labelKey: String {
        switch self {
        case .pending: return "admin_reports_filter_pending"
        case .all: return "admin_reports_filter_all"
        case .resolved: return "admin_reports_filter_resolved"
        case .dismissed: return "admin_reports_filter_dismissed"
        }
    }
}

/// What the client offers on a community report. The server decides every action; this only
/// chooses what to show and never offers what the server refuses.
enum CommunityReportActions {
    /// Mirrors moderate_community_content (20261018_0001 block 4, D-S7), not AdminReportsView: a
    /// community admin may not hide hidden content, may restore only when the server says so, and
    /// may not hide or dismiss a report a platform admin reviewed. Pure; tested as a table.
    /// Order: hide, restore, dismiss.
    static func available(for report: CommunityReport) -> [CommunityModerationAction] {
        let canDismiss = report.status == "pending" && !report.platformHandled
        if report.isPersonReport {
            return canDismiss ? [.dismiss] : []
        }
        var actions: [CommunityModerationAction] = []
        if !report.contentHidden && !report.platformHandled {
            actions.append(.hide)
        }
        if report.contentHidden && report.canRestore {
            actions.append(.restore)
        }
        if canDismiss {
            actions.append(.dismiss)
        }
        return actions
    }
}

extension CommunityReport {
    /// The report type in the person's language, through the six-locale keys the report sheets
    /// already use. An unknown or empty value reads as "Other"; never the raw server value.
    var reportTypeLabel: String {
        switch MessageService.ReportType(rawValue: reportType) {
        case .spam?: return "messaging_report_spam".localized
        case .harassment?: return "messaging_report_harassment".localized
        case .inappropriateContent?: return "messaging_report_inappropriate_content".localized
        case .scam?: return "messaging_report_scam".localized
        case .other?, nil: return "messaging_report_other".localized
        }
    }

    /// The row after a successful action, for the local update before the reload.
    func applying(_ action: CommunityModerationAction) -> CommunityReport {
        var newStatus = status
        var newHidden = contentHidden
        var newCanRestore = canRestore
        switch action {
        case .hide:
            newStatus = "action_taken"
            newHidden = true
            newCanRestore = true
        case .restore:
            newHidden = false
            newCanRestore = false
        case .dismiss:
            newStatus = "dismissed"
        }
        return CommunityReport(
            reportId: reportId,
            targetType: targetType,
            reportedUserId: reportedUserId,
            reportedUserName: reportedUserName,
            authorId: authorId,
            authorName: authorName,
            reportedPostId: reportedPostId,
            reportedCommentId: reportedCommentId,
            reportedRideId: reportedRideId,
            reportedFavorId: reportedFavorId,
            townHallPostId: townHallPostId,
            reportType: reportType,
            description: description,
            status: newStatus,
            createdAt: createdAt,
            reviewedAt: reviewedAt,
            contentPreview: contentPreview,
            contentHidden: newHidden,
            reportCount: reportCount,
            canRestore: newCanRestore,
            platformHandled: platformHandled
        )
    }
}

@MainActor
final class CommunityReportsViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }

    @Published private(set) var access: Access = .checking
    @Published private(set) var reports: [CommunityReport] = []
    /// Changing the filter clears the rows; the view then calls `load()`.
    @Published var filter: CommunityReportFilter = .pending {
        didSet {
            guard filter != oldValue else { return }
            reports = []
            loadError = nil
        }
    }
    @Published private(set) var isLoading = false
    /// Shown full screen only while `reports` is empty.
    @Published var loadError: String?
    /// Shown in the error banner.
    @Published var actionErrorMessage: String?
    @Published private(set) var actingOnReportId: UUID?

    let communityId: UUID

    private let adminService: any AdminServiceProtocol
    private let communityContext: CommunityContext
    /// Only the newest load writes its result (a filter switch or pull-to-refresh can overlap one).
    private var loadGeneration = 0

    init(
        communityId: UUID,
        adminService: any AdminServiceProtocol = AdminService.shared,
        communityContext: CommunityContext? = nil
    ) {
        self.communityId = communityId
        self.adminService = adminService
        self.communityContext = communityContext ?? .shared
    }

    // MARK: - Load

    func load() async {
        await reload(reportingErrors: true)
    }

    /// `reportingErrors` is false for the reload after an action: its failure changes nothing shown.
    private func reload(reportingErrors: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedFilter = filter
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        if reportingErrors { loadError = nil }

        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }

        guard communityContext.isAdmin(of: communityId) else {
            guard generation == loadGeneration else { return }
            access = .notAdmin
            reports = []
            return
        }
        access = .allowed

        do {
            let rows = try await adminService.fetchCommunityReports(
                communityId: communityId,
                status: requestedFilter.status
            )
            guard generation == loadGeneration, requestedFilter == filter else { return }
            reports = rows
            loadError = nil
        } catch let refusal as CommunityRPCError where refusal.code == nil {
            // The server's unauthorized answer carries no code: the caller's role is gone.
            AppLogger.warning("community", "get_community_reports refused: \(refusal.serverMessage)")
            guard generation == loadGeneration else { return }
            access = .notAdmin
            reports = []
        } catch {
            AppLogger.error("community", "fetchCommunityReports(\(requestedFilter)) failed: \(error)")
            guard reportingErrors, generation == loadGeneration, requestedFilter == filter else { return }
            if reports.isEmpty {
                loadError = "common_load_error".localized
            } else {
                actionErrorMessage = "common_load_error".localized
            }
        }
    }

    // MARK: - Moderate

    /// One action at a time, held through the follow-up reload. A success changes the row before
    /// the reload, so a reload that fails cannot bring back a button for an action that worked.
    @discardableResult
    func moderate(_ report: CommunityReport, action: CommunityModerationAction, reason: String?) async -> Bool {
        guard actingOnReportId == nil, CommunityReportActions.available(for: report).contains(action) else {
            return false
        }
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note: String? = trimmed.isEmpty ? nil : trimmed
        if action == .hide && note == nil { return false }

        actingOnReportId = report.id
        defer { actingOnReportId = nil }
        actionErrorMessage = nil

        do {
            try await adminService.moderateCommunityContent(reportId: report.reportId, action: action, reason: note)
        } catch let refusal as CommunityRPCError {
            // Every refusal reads the same, including the codes this build does not know
            // (platform_handled, already_hidden, not_hidden, platform_hidden, already_closed);
            // the reload's fresh flags remove the refused button.
            AppLogger.warning("community", "moderate_community_content(\(action)) refused: \(refusal.serverMessage)")
            actionErrorMessage = "community_reports_action_failed".localized
            await reload(reportingErrors: false)
            return false
        } catch {
            AppLogger.error("community", "moderate_community_content(\(action)) failed: \(error)")
            actionErrorMessage = "community_error_generic".localized
            return false
        }

        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = reports[index].applying(action)
        }
        HapticManager.success()
        await reload(reportingErrors: false)
        return true
    }
}
