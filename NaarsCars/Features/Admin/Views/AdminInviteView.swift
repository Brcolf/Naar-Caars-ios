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
                        
                        Text("Generate Invite Code")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Create a code to invite new members")
                            .font(.subheadline)
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
                                        .font(.title2)
                                        .foregroundColor(.naarsPrimary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Regular Invite")
                                            .font(.headline)
                                        
                                        Text("Single-use code with invitation statement")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
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
                                        .font(.title2)
                                        .foregroundColor(.naarsPrimary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Bulk Invite")
                                            .font(.headline)
                                        
                                        Text("Multi-use code (expires in 48 hours)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
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
                            Text("Generated Code")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatCode(code.code))
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("admin.invite.code")
                                
                                if code.isBulk {
                                    if let expiresAt = code.expiresAt {
                                        Text("Expires: \(expiresAt.dateString) at \(expiresAt.timeString)")
                                            .font(.caption)
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
                                            Text("Copy")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    }
                                    .accessibilityIdentifier("admin.invite.copy")
                                    
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    }
                                    .accessibilityIdentifier("admin.invite.share")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Invite Codes")
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
        let chars = Array(code)
        if code.count == 10 {
            return "\(String(chars[0...3])) · \(String(chars[4...7])) · \(String(chars[8...9]))"
        } else if code.count == 8 {
            return "\(String(chars[0...3])) · \(String(chars[4...7]))"
        }
        return code
    }
    
    private func generateShareMessage(_ code: String, isBulk: Bool) -> String {
        let deepLink = "https://naarscars.com/signup?code=\(code)"
        let appStoreLink = "https://apps.apple.com/app/naars-cars" // TODO: Replace with actual link
        
        if isBulk {
            return """
            Join Naar's Cars! 🚗
            
            Sign up here: \(deepLink)
            
            Or download the app and enter code: \(code)
            \(appStoreLink)
            
            This code can be used by multiple people and expires in 48 hours.
            """
        } else {
            return """
            Join me on Naar's Cars! 🚗
            
            Sign up here: \(deepLink)
            
            Or download the app and enter code: \(code)
            \(appStoreLink)
            """
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
                    
                    Text("Bulk Invite Code")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("This code can be used by multiple people and will expire in 48 hours")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                PrimaryButton(
                    title: "Generate Bulk Code",
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
            .navigationTitle("Bulk Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("admin.bulk.cancel")
                }
            }
        }
    }
    
    private func generateBulkCode() async {
        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "Not signed in"
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let code = try await InviteService.shared.generateBulkInviteCode(userId: userId)
            onCodeGenerated(code)
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? "Failed to generate bulk code"
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

