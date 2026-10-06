//
//  ReportContentSheet.swift
//  NaarsCars
//
//  Sheet for reporting user-generated content (posts, comments, rides, favors)
//

import SwiftUI

/// Context for what is being reported
enum ReportContext {
    case post(id: UUID, authorId: UUID, preview: String)
    case comment(id: UUID, authorId: UUID, preview: String)
    case ride(id: UUID, authorId: UUID, preview: String)
    case favor(id: UUID, authorId: UUID, preview: String)
    case user(id: UUID, name: String)
    /// A review. `authorId` is the reviewer.
    case review(id: UUID, authorId: UUID, preview: String)
}

/// Sheet for reporting user-generated content
struct ReportContentSheet: View {
    let context: ReportContext
    var onReported: (() -> Void)?
    /// Called with the author's ID as the sheet closes, when the user blocked them from here.
    var onBlocked: ((UUID) -> Void)?
    /// Sent to the moderators after the typed description, for a report whose target the server
    /// has no column for (a request question is filed against the person who asked it, and
    /// this carries the question). Not shown in the sheet.
    var contextNote: String? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ReportContentViewModel()
    @State private var selectedReportType: MessageService.ReportType = .other
    @State private var description = ""
    @State private var showBlockConfirmation = false

    private var reportTypes: [(type: MessageService.ReportType, title: String, icon: String)] {[
        (.spam, "messaging_report_spam".localized, "exclamationmark.bubble"),
        (.harassment, "messaging_report_harassment".localized, "person.crop.circle.badge.exclamationmark"),
        (.inappropriateContent, "messaging_report_inappropriate_content".localized, "eye.slash"),
        (.scam, "messaging_report_scam".localized, "exclamationmark.shield"),
        (.other, "messaging_report_other".localized, "ellipsis.circle")
    ]}

    private var contentPreview: String {
        switch context {
        case .post(_, _, let preview): return preview
        case .comment(_, _, let preview): return preview
        case .ride(_, _, let preview): return preview
        case .favor(_, _, let preview): return preview
        case .user(_, let name): return name
        case .review(_, _, let preview): return preview
        }
    }

    private var contentTypeLabel: String {
        switch context {
        case .post: return "town_hall_post".localized
        case .comment: return "town_hall_comment".localized
        case .ride: return "report_content_type_ride".localized
        case .favor: return "report_content_type_favor".localized
        case .user: return "report_content_type_user".localized
        case .review: return "townhall_badge_review".localized
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Content preview
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.naarsTitle2)
                            .foregroundColor(.naarsWarning)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("report_this_content".localized)
                                .font(.naarsHeadline)

                            Text(contentPreview)
                                .font(.naarsSubheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(contentTypeLabel)
                }

                // Report type selection
                Section {
                    ForEach(reportTypes, id: \.type.rawValue) { reportType in
                        Button {
                            selectedReportType = reportType.type
                        } label: {
                            HStack {
                                Image(systemName: reportType.icon)
                                    .foregroundColor(.naarsPrimary)
                                    .frame(width: 24)

                                Text(reportType.title)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedReportType == reportType.type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.naarsPrimary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("messaging_reason".localized)
                }

                // Additional details
                Section {
                    TextField("messaging_additional_details_optional".localized, text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("messaging_description".localized)
                }

                // Block the author (same option as the message report sheet)
                if let authorId = viewModel.blockableAuthorId(for: context) {
                    Section {
                        if viewModel.blockedAuthorId == authorId {
                            Label("profile_user_blocked".localized, systemImage: "hand.raised.fill")
                                .foregroundColor(.secondary)
                        } else {
                            Button {
                                showBlockConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .foregroundColor(.naarsError)
                                    Text("messaging_block_this_user".localized)
                                        .foregroundColor(.naarsError)
                                }
                            }
                            .disabled(viewModel.isBlocking)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("report_content_title".localized(with: contentTypeLabel))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("messaging_submit".localized) {
                        Task { await submitReport() }
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
            .alert("report_failed".localized, isPresented: Binding(
                get: { viewModel.submitError != nil },
                set: { if !$0 { viewModel.submitError = nil } }
            )) {
                Button("messaging_ok".localized, role: .cancel) {}
            } message: {
                Text(viewModel.submitError ?? "")
            }
        }
        .alert("profile_block_user".localized, isPresented: $showBlockConfirmation) {
            Button("profile_block_confirm".localized, role: .destructive) {
                guard let authorId = viewModel.blockableAuthorId(for: context) else { return }
                Task { await viewModel.blockAuthor(authorId) }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            Text("profile_block_confirmation_message".localized)
        }
        .alert("messaging_block_failed".localized, isPresented: Binding(
            get: { viewModel.blockError != nil },
            set: { if !$0 { viewModel.blockError = nil } }
        )) {
            Button("messaging_ok".localized, role: .cancel) {}
        } message: {
            Text(viewModel.blockError ?? "")
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            // Tell the presenter only as the sheet closes: removing the blocked author's content
            // removes the card or row that presents this sheet, which would dismiss it mid-use.
            if let blockedAuthorId = viewModel.blockedAuthorId {
                onBlocked?(blockedAuthorId)
            }
        }
    }

    private func submitReport() async {
        var details = description
        if let contextNote, !contextNote.isEmpty {
            details = details.isEmpty ? contextNote : "\(details)\n\n\(contextNote)"
        }
        guard await viewModel.submitReport(context: context, type: selectedReportType, description: details) else { return }
        onReported?()
        dismiss()
    }
}
