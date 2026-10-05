//
//  ApplicationFieldsView.swift
//  NaarsCars
//
//  Post-auth application step — collects info for admin review
//

import SwiftUI
import os

/// Collects application fields after authentication, before pending review.
/// Shown when a user has authenticated but not yet submitted their application
/// (application_complete == false). Blocks access to the app until submitted.
struct ApplicationFieldsView: View {
    @StateObject private var viewModel = ApplicationFieldsViewModel()
    @State private var heardAbout: String = ""
    @State private var joinReason: String = ""
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
                        HStack {
                            Text("application_heard_about_label".localized)
                                .font(.naarsHeadline)
                            Spacer()
                            Text("\(heardAbout.count)/500")
                                .font(.naarsCaption)
                                .foregroundColor(heardAbout.count > 500 ? .naarsError : .secondary)
                        }

                        TextField(
                            "application_heard_about_placeholder".localized,
                            text: $heardAbout,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .heardAbout)
                        .accessibilityIdentifier("application.heardAbout")
                        .onChange(of: heardAbout) { _, newValue in
                            if newValue.count > 500 {
                                heardAbout = String(newValue.prefix(500))
                            }
                        }
                    }

                    // Why would you like to join?
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("application_join_reason_label".localized)
                                .font(.naarsHeadline)
                            Spacer()
                            Text("\(joinReason.count)/500")
                                .font(.naarsCaption)
                                .foregroundColor(joinReason.count > 500 ? .naarsError : .secondary)
                        }

                        TextField(
                            "application_join_reason_placeholder".localized,
                            text: $joinReason,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .joinReason)
                        .accessibilityIdentifier("application.joinReason")
                        .onChange(of: joinReason) { _, newValue in
                            if newValue.count > 500 {
                                joinReason = String(newValue.prefix(500))
                            }
                        }
                    }

                    // Helper text
                    Text("application_helper_text".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Error
                if let errorMessage = viewModel.errorMessage {
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
                    isLoading: viewModel.isSubmitting,
                    isDisabled: viewModel.isSubmitting || heardAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || joinReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard await viewModel.submitApplication(heardAbout: heardAbout, joinReason: joinReason) else { return }

        HapticManager.success()

        // Transition to pending approval
        AppLaunchManager.shared.state = .ready(.pendingApproval)
    }
}

#Preview {
    NavigationStack {
        ApplicationFieldsView()
    }
}
