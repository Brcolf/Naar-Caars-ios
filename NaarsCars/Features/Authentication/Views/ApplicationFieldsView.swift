//
//  ApplicationFieldsView.swift
//  NaarsCars
//
//  Post-auth application step — collects info for admin review
//

import SwiftUI
import Supabase
import os

/// Collects application fields after authentication, before pending review.
/// Shown when a user has authenticated but not yet submitted their application
/// (application_complete == false). Blocks access to the app until submitted.
struct ApplicationFieldsView: View {
    @State private var heardAbout: String = ""
    @State private var joinReason: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case heardAbout, joinReason }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.naarsPrimary)

                    Text("application_title".localized)
                        .font(.naarsTitle2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("application_subtitle".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 20)

                // Form fields
                VStack(alignment: .leading, spacing: 20) {
                    // How did you hear about Naar's Cars?
                    VStack(alignment: .leading, spacing: 8) {
                        Text("application_heard_about_label".localized)
                            .font(.naarsHeadline)

                        TextField(
                            "application_heard_about_placeholder".localized,
                            text: $heardAbout,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .heardAbout)
                        .accessibilityIdentifier("application.heardAbout")
                    }

                    // Why would you like to join?
                    VStack(alignment: .leading, spacing: 8) {
                        Text("application_join_reason_label".localized)
                            .font(.naarsHeadline)

                        TextField(
                            "application_join_reason_placeholder".localized,
                            text: $joinReason,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .joinReason)
                        .accessibilityIdentifier("application.joinReason")
                    }

                    // Helper text
                    Text("application_helper_text".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .padding(.horizontal)
                }

                // Submit button
                PrimaryButton(
                    title: "application_submit_button".localized,
                    action: {
                        Task {
                            await submitApplication()
                        }
                    },
                    isLoading: isSubmitting,
                    isDisabled: isSubmitting || heardAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || joinReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .padding(.horizontal)
                .accessibilityIdentifier("application.submit")

                // Sign out option
                Button(action: {
                    Task {
                        try? await AuthService.shared.signOut()
                        await AppLaunchManager.shared.performCriticalLaunch()
                    }
                }) {
                    Text("application_sign_out".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .accessibilityIdentifier("application.signOut")
                .padding(.bottom, 32)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("application_nav_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { focusedField = .heardAbout } label: { Image(systemName: "chevron.up") }
                    .disabled(focusedField == .heardAbout)
                Button { focusedField = .joinReason } label: { Image(systemName: "chevron.down") }
                    .disabled(focusedField == .joinReason)
                Spacer()
                Button("common_done".localized) { focusedField = nil }
            }
        }
        .trackScreen("ApplicationFields")
    }

    private func submitApplication() async {
        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "application_error_not_signed_in".localized
            return
        }

        let trimmedHeardAbout = heardAbout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJoinReason = joinReason.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHeardAbout.isEmpty, !trimmedJoinReason.isEmpty else {
            errorMessage = "application_error_fields_required".localized
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            try await SupabaseService.shared.client
                .from("profiles")
                .update([
                    "heard_about": AnyCodable(trimmedHeardAbout),
                    "join_reason": AnyCodable(trimmedJoinReason),
                    "application_complete": AnyCodable(true),
                    "application_submitted_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
                ])
                .eq("id", value: userId.uuidString)
                .execute()

            HapticManager.success()

            // Transition to pending approval
            AppLaunchManager.shared.state = .ready(.pendingApproval)
        } catch {
            AppLogger.auth.error("Failed to submit application: \(error.localizedDescription)")
            errorMessage = "application_error_submit_failed".localized
            isSubmitting = false
        }
    }
}

#Preview {
    NavigationStack {
        ApplicationFieldsView()
    }
}
