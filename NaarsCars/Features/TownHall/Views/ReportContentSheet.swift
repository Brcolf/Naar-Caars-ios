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
}

/// Sheet for reporting user-generated content
struct ReportContentSheet: View {
    let context: ReportContext
    var onReported: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ReportContentViewModel()
    @State private var selectedReportType: MessageService.ReportType = .other
    @State private var description = ""

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
        }
    }

    private var contentTypeLabel: String {
        switch context {
        case .post: return "town_hall_post".localized
        case .comment: return "town_hall_comment".localized
        case .ride: return "report_content_type_ride".localized
        case .favor: return "report_content_type_favor".localized
        case .user: return "report_content_type_user".localized
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
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("messaging_report_title".localized)
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
        .presentationDetents([.medium, .large])
    }

    private func submitReport() async {
        guard await viewModel.submitReport(context: context, type: selectedReportType, description: description) else { return }
        onReported?()
        dismiss()
    }
}
