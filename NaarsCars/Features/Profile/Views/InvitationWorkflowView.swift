//
//  InvitationWorkflowView.swift
//  NaarsCars
//
//  Popup workflow for generating invite codes
//  Asks "Who are you inviting and why?"
//

import SwiftUI

/// Popup workflow for generating an invite code
/// Asks user to provide statement about who they're inviting and why
/// After generation, shows code with share options
struct InvitationWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteStatement: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var generatedCode: InviteCode?
    @State private var showCopiedToast = false
    @State private var showShareSheet = false
    @State private var showSuccess = false
    
    let userId: UUID
    let onCodeGenerated: (InviteCode) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let code = generatedCode {
                        // Show generated code with share options
                        codeGeneratedView(code: code)
                    } else {
                        // Show input form
                        inputFormView
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common_done".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("invite.done")
                }
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
    
    // MARK: - Input Form View
    
    private var inputFormView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.naarsPrimary)
                
                Text("invite_create".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("invite_tell_us".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Statement input
            VStack(alignment: .leading, spacing: 8) {
                Text("invite_who_and_why".localized)
                    .font(.naarsHeadline)
                
                TextEditor(text: $inviteStatement)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.naarsCardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(inviteStatement.isEmpty ? Color.clear : Color.naarsPrimary, lineWidth: 1)
                    )
                    .accessibilityIdentifier("invite.statement")
                
                Text("\(inviteStatement.count) / 500")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .padding(.horizontal)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                PrimaryButton(
                    title: "invite_generate_code".localized,
                    action: {
                        Task {
                            await generateCode()
                        }
                    },
                    isLoading: isGenerating
                )
                .disabled(inviteStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .accessibilityIdentifier("invite.generate")
                .padding(.horizontal)
                
                Button("common_cancel".localized) {
                    dismiss()
                }
                .foregroundColor(.secondary)
                .accessibilityIdentifier("invite.cancel")
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Code Generated View
    
    private func codeGeneratedView(code: InviteCode) -> some View {
        VStack(spacing: 24) {
            // Success header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("invite_code_generated".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("invite_share_prompt".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Code display
            VStack(spacing: 16) {
                Text("invite_your_code".localized)
                    .font(.naarsHeadline)
                
                Text(formatCode(code.code))
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.naarsCardBackground)
                    .cornerRadius(12)
                    .accessibilityIdentifier("invite.generatedCode")
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        copyCode(code.code)
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("invite_copy".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsCardBackground)
                        .foregroundColor(.naarsPrimary)
                        .cornerRadius(12)
                    }
                    .accessibilityIdentifier("invite.copy")
                    
                    Button(action: {
                        showShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("invite_share".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibilityIdentifier("invite.share")
                }
            }
            .padding()
            .background(Color.naarsBackgroundSecondary)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareMessage(code.code)])
        }
        .overlay(
            Group {
                if showCopiedToast {
                    VStack {
                        Text("invite_copied".localized)
                            .font(.naarsCaption)
                            .padding(12)
                            .background(Color(.systemGray))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding()
                    .transition(.opacity)
                }
            },
            alignment: .top
        )
        .onChange(of: showCopiedToast) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            }
        }
    }
    
    private func generateCode() async {
        let trimmed = inviteStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = "invite_statement_required".localized
            return
        }
        
        guard trimmed.count <= 500 else {
            errorMessage = "invite_statement_too_long".localized
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let code = try await InviteService.shared.generateInviteCode(
                userId: userId,
                inviteStatement: trimmed
            )
            
            // Success - show code with share options
            generatedCode = code
            showSuccess = true
            HapticManager.success()
            onCodeGenerated(code)
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? "invite_generate_failed".localized
        }
        
        isGenerating = false
    }
    
    // MARK: - Helper Methods
    
    private func formatCode(_ code: String) -> String {
        InviteCodeFormatter.formatCode(code)
    }
    
    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        withAnimation {
            showCopiedToast = true
        }
    }
    
    private func generateShareMessage(_ code: String) -> String {
        InviteCodeFormatter.generateShareMessage(code)
    }
}

#Preview {
    InvitationWorkflowView(
        userId: UUID(),
        onCodeGenerated: { _ in }
    )
}

