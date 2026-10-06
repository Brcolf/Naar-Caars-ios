//
//  CompleteSheet.swift
//  NaarsCars
//
//  Confirmation sheet for completing a request
//

import SwiftUI

/// Confirmation sheet for completing a request
struct CompleteSheet: View {
    let requestType: String
    let requestTitle: String
    /// Runs the completion; the success checkmark and XP toast appear only when it does not throw.
    let onConfirm: () async throws -> Void
    /// The poster is prompted to review their helper after completing; the helper is not.
    var isPoster: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var toastMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsSuccess)
                
                Text("claim_complete_title".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("claim_complete_description".localized)
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.naarsInsetBackground)
                    .cornerRadius(Constants.Radius.sm)
                
                if isPoster {
                    Text("claim_complete_review_hint".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "claim_complete_confirm".localized, action: {
                        guard !isCompleting else { return }
                        isCompleting = true
                        Task {
                            defer { isCompleting = false }
                            do {
                                try await onConfirm()
                                showSuccess = true
                                // Show XP toast after success checkmark appears
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                toastMessage = requestType == "ride" ? "toast_xp_ride".localized : "toast_xp_favor".localized
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }, isLoading: isCompleting)
                    .accessibilityIdentifier("complete.confirm")
                    
                    SecondaryButton(title: "claim_complete_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("complete.cancel")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("claim_complete_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
        .toast(message: $toastMessage, style: .success)
        .successCheckmark(isShowing: $showSuccess)
        .alert("common_error".localized, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common_ok".localized, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: showSuccess) { _, newValue in
            if !newValue {
                dismiss()
            }
        }
    }
}

#Preview {
    CompleteSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}





