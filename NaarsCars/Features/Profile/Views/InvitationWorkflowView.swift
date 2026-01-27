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
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("invite.done")
                }
            }
        }
    }
    
    // MARK: - Input Form View
    
    private var inputFormView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.naarsPrimary)
                
                Text("Create Invite")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Tell us about who you're inviting")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Statement input
            VStack(alignment: .leading, spacing: 8) {
                Text("Who are you inviting and why?")
                    .font(.headline)
                
                TextEditor(text: $inviteStatement)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(inviteStatement.isEmpty ? Color.clear : Color.naarsPrimary, lineWidth: 1)
                    )
                    .accessibilityIdentifier("invite.statement")
                
                Text("\(inviteStatement.count) / 500")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                PrimaryButton(
                    title: "Generate Invite Code",
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
                
                Button("Cancel") {
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
                
                Text("Invite Code Generated!")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Share this code with someone you'd like to invite")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Code display
            VStack(spacing: 16) {
                Text("Your Invite Code")
                    .font(.headline)
                
                Text(formatCode(code.code))
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .accessibilityIdentifier("invite.generatedCode")
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        copyCode(code.code)
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    .accessibilityIdentifier("invite.copy")
                    
                    Button(action: {
                        showShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
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
            .background(Color(.systemBackground))
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
                        Text("Copied!")
                            .font(.caption)
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
            errorMessage = "Please provide a statement about who you're inviting"
            return
        }
        
        guard trimmed.count <= 500 else {
            errorMessage = "Statement must be 500 characters or less"
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
            onCodeGenerated(code)
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? "Failed to generate invite code"
        }
        
        isGenerating = false
    }
    
    // MARK: - Helper Methods
    
    private func formatCode(_ code: String) -> String {
        let chars = Array(code)
        if code.count == 10 {
            return "\(String(chars[0...3])) · \(String(chars[4...7])) · \(String(chars[8...9]))"
        } else if code.count == 8 {
            return "\(String(chars[0...3])) · \(String(chars[4...7]))"
        }
        return code
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
        let deepLink = "https://naarscars.com/signup?code=\(code)"
        let appStoreLink = "https://apps.apple.com/app/naars-cars"
        
        return """
        Join me on Naar's Cars! 🚗
        
        Sign up here: \(deepLink)
        
        Or download the app and enter code: \(code)
        \(appStoreLink)
        """
    }
}

#Preview {
    InvitationWorkflowView(
        userId: UUID(),
        onCodeGenerated: { _ in }
    )
}

