//
//  ReportMessageSheet.swift
//  NaarsCars
//
//  Sheet for reporting a message
//

import SwiftUI

/// Sheet for reporting a message
struct ReportMessageSheet: View {
    let message: Message
    let onSubmit: (MessageService.ReportType, String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReportType: MessageService.ReportType = .other
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showBlockConfirmation = false
    @State private var blockError: String?
    
    private var reportTypes: [(type: MessageService.ReportType, title: String, icon: String)] {[
        (.spam, "messaging_report_spam".localized, "exclamationmark.bubble"),
        (.harassment, "messaging_report_harassment".localized, "person.crop.circle.badge.exclamationmark"),
        (.inappropriateContent, "messaging_report_inappropriate_content".localized, "eye.slash"),
        (.scam, "messaging_report_scam".localized, "exclamationmark.shield"),
        (.other, "messaging_report_other".localized, "ellipsis.circle")
    ]}
    
    var body: some View {
        NavigationStack {
            Form {
                // Message preview
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.naarsTitle2)
                            .foregroundColor(.naarsWarning)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("messaging_report_this_message".localized)
                                .font(.naarsHeadline)
                            
                            Text(message.text.isEmpty ? "messaging_media_message".localized : message.text)
                                .font(.naarsSubheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("messaging_message".localized)
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
                } footer: {
                    Text("messaging_provide_additional_context".localized)
                }
                
                // Block user option
                Section {
                    Button {
                        showBlockConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundColor(.red)
                            Text("messaging_block_this_user".localized)
                                .foregroundColor(.red)
                        }
                    }
                } footer: {
                    Text("messaging_block_user_footer".localized)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("messaging_cancel".localized) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("messaging_submit".localized) {
                        isSubmitting = true
                        onSubmit(selectedReportType, description.isEmpty ? nil : description)
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .alert("messaging_block_user".localized, isPresented: $showBlockConfirmation) {
            Button("messaging_block".localized, role: .destructive) {
                Task {
                    guard let currentUserId = AuthService.shared.currentUserId else {
                        blockError = "messaging_must_be_signed_in_to_block".localized
                        return
                    }
                    do {
                        try await MessageService.shared.blockUser(
                            blockerId: currentUserId,
                            blockedId: message.fromId,
                            reason: "Blocked from message report"
                        )
                    } catch {
                        blockError = "messaging_unable_to_block_user".localized
                    }
                }
            }
            Button("messaging_cancel".localized, role: .cancel) {}
        } message: {
            Text("messaging_block_user_footer".localized)
        }
        .alert("messaging_block_failed".localized, isPresented: Binding(
            get: { blockError != nil },
            set: { if !$0 { blockError = nil } }
        )) {
            Button("messaging_ok".localized, role: .cancel) {}
        } message: {
            Text(blockError ?? "")
        }
        .presentationDetents([.medium, .large])
    }
}
