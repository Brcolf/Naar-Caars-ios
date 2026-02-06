//
//  AdminInviteView.swift
//  NaarsCars
//
//  View for admins to generate regular or bulk invite codes
//

import SwiftUI
internal import Combine

/// View for admins to generate invite codes (regular or bulk)
struct AdminInviteView: View {
    @StateObject private var viewModel = AdminInviteViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showBulkInviteSheet = false
    @State private var showRegularInviteWorkflow = false
    @State private var generatedCode: InviteCode?
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.naarsPrimary)
                        
                        Text("admin_generate_invite_code".localized)
                            .font(.naarsTitle2)
                            .fontWeight(.semibold)
                        
                        Text("admin_invite_create_code".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Options
                    VStack(spacing: 16) {
                        // Regular Invite (with statement)
                        Button(action: {
                            showRegularInviteWorkflow = true
                        }) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.naarsTitle2)
                                        .foregroundColor(.naarsPrimary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("admin_invite_regular".localized)
                                            .font(.naarsHeadline)
                                        
                                        Text("admin_invite_regular_desc".localized)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.naarsBackgroundSecondary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("admin.invite.regular")
                        
                        // Bulk Invite
                        Button(action: {
                            showBulkInviteSheet = true
                        }) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .font(.naarsTitle2)
                                        .foregroundColor(.naarsPrimary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("admin_invite_bulk".localized)
                                            .font(.naarsHeadline)
                                        
                                        Text("admin_invite_bulk_desc".localized)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.naarsBackgroundSecondary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("admin.invite.bulk")
                    }
                    .padding(.horizontal)
                    
                    // Generated Code Display
                    if let code = generatedCode {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("admin_invite_generated_code".localized)
                                .font(.naarsHeadline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatCode(code.code))
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("admin.invite.code")
                                
                                if code.isBulk {
                                    if let expiresAt = code.expiresAt {
                                        Text("Expires: \(expiresAt.dateString) at \(expiresAt.timeString)")
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        UIPasteboard.general.string = code.code
                                        let generator = UINotificationFeedbackGenerator()
                                        generator.notificationOccurred(.success)
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.on.doc")
                                            Text("admin_invite_copy".localized)
                                        }
                                        .font(.naarsCaption)
                                        .foregroundColor(.naarsPrimary)
                                    }
                                    .accessibilityIdentifier("admin.invite.copy")
                                    
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("admin_invite_share".localized)
                                        }
                                        .font(.naarsCaption)
                                        .foregroundColor(.naarsPrimary)
                                    }
                                    .accessibilityIdentifier("admin.invite.share")
                                }
                            }
                            .padding()
                            .background(Color.naarsCardBackground)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("admin_invite_codes".localized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRegularInviteWorkflow) {
                if let userId = AuthService.shared.currentUserId {
                    InvitationWorkflowView(userId: userId) { code in
                        generatedCode = code
                        showRegularInviteWorkflow = false
                    }
                }
            }
            .sheet(isPresented: $showBulkInviteSheet) {
                BulkInviteSheet(
                    onCodeGenerated: { code in
                        generatedCode = code
                        showBulkInviteSheet = false
                    }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                if let code = generatedCode {
                    ShareSheet(items: [generateShareMessage(code.code, isBulk: code.isBulk)])
                }
            }
        }
    }
    
    private func formatCode(_ code: String) -> String {
        InviteCodeFormatter.formatCode(code)
    }
    
    private func generateShareMessage(_ code: String, isBulk: Bool) -> String {
        if isBulk {
            return InviteCodeFormatter.generateBulkShareMessage(code)
        } else {
            return InviteCodeFormatter.generateShareMessage(code)
        }
    }
}

/// Sheet for generating bulk invite codes
private struct BulkInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    let onCodeGenerated: (InviteCode) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.naarsPrimary)
                    
                    Text("admin_invite_bulk_code".localized)
                        .font(.naarsTitle2)
                        .fontWeight(.semibold)
                    
                    Text("admin_invite_bulk_code_desc".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                PrimaryButton(
                    title: "admin_invite_generate_bulk".localized,
                    action: {
                        Task {
                            await generateBulkCode()
                        }
                    },
                    isLoading: isGenerating
                )
            .accessibilityIdentifier("admin.bulk.generate")
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("admin_invite_bulk".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("admin.bulk.cancel")
                }
            }
        }
    }
    
    private func generateBulkCode() async {
        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "admin_invite_not_signed_in".localized
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let code = try await InviteService.shared.generateBulkInviteCode(userId: userId)
            onCodeGenerated(code)
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? "admin_invite_bulk_failed".localized
        }
        
        isGenerating = false
    }
}

/// ViewModel for admin invite view
@MainActor
final class AdminInviteViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: AppError?
}

#Preview {
    AdminInviteView()
}

