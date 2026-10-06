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
    // Sign-out and delete-account actions, shared with the pending-review and restricted screens
    @StateObject private var accountViewModel = BannedAccountViewModel()
    @State private var name: String = ""
    @State private var heardAbout: String = ""
    @State private var joinReason: String = ""
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case name, heardAbout, joinReason }

    /// Fields in tab order. Name is only on the form when the profile has none.
    private var fieldOrder: [Field] {
        viewModel.needsName ? [.name, .heardAbout, .joinReason] : [.heardAbout, .joinReason]
    }

    private var isSubmitDisabled: Bool {
        viewModel.isSubmitting
            || accountViewModel.isDeletingAccount
            || (viewModel.needsName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || heardAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || joinReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                    // Name. Only asked when the profile has none: a repeat Sign in with Apple
                    // authorization does not return it, and admins would review "Apple User".
                    if viewModel.needsName {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("application_name_label".localized)
                                .font(.naarsHeadline)

                            TextField("application_name_placeholder".localized, text: $name)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .heardAbout }
                                .accessibilityLabel("application_name_label".localized)
                                .accessibilityIdentifier("application.name")
                                .onChange(of: name) { _, _ in
                                    if viewModel.nameError != nil { viewModel.nameError = nil }
                                }

                            if let nameError = viewModel.nameError {
                                Text(nameError)
                                    .font(.naarsCaption)
                                    .foregroundColor(.naarsError)
                                    .accessibilityLabel("app_error_format".localized(with: nameError))
                            }
                        }
                    }

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
                    isDisabled: isSubmitDisabled
                )
                .padding(.horizontal)
                .accessibilityIdentifier("application.submit")

                VStack(spacing: 0) {
                    // Sign out option
                    AccountTextAction(
                        title: "application_sign_out".localized,
                        isBusy: accountViewModel.isSigningOut
                    ) {
                        Task { await accountViewModel.signOut() }
                    }
                    .disabled(viewModel.isSubmitting || accountViewModel.isDeletingAccount)
                    .accessibilityIdentifier("application.signOut")

                    // Delete Account. Low emphasis, but it has to be here: the account
                    // already exists and Settings is out of reach until an admin approves
                    // it (Guideline 5.1.1(v)).
                    AccountTextAction(
                        title: "profile_delete_account".localized,
                        isDestructive: true,
                        isBusy: accountViewModel.isDeletingAccount
                    ) {
                        focusedField = nil
                        showDeleteConfirmation = true
                    }
                    .disabled(viewModel.isSubmitting || accountViewModel.isSigningOut)
                    .accessibilityIdentifier("application.deleteAccount")
                }
                .padding(.bottom, 32)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("application_nav_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { moveFocus(forward: false) } label: { Image(systemName: "chevron.up") }
                    .disabled(focusedField == fieldOrder.first)
                    .accessibilityLabel("auth_keyboard_previous_field".localized)
                Button { moveFocus(forward: true) } label: { Image(systemName: "chevron.down") }
                    .disabled(focusedField == fieldOrder.last)
                    .accessibilityLabel("auth_keyboard_next_field".localized)
                Spacer()
                Button("common_done".localized) { focusedField = nil }
            }
        }
        .accountDeletionFlow(
            isConfirming: $showDeleteConfirmation,
            viewModel: accountViewModel,
            message: "account_delete_pre_approval_message".localized
        )
        .task {
            await viewModel.loadNameRequirement()
        }
        .trackScreen("ApplicationFields")
    }

    private func moveFocus(forward: Bool) {
        let fields = fieldOrder
        guard let current = focusedField, let index = fields.firstIndex(of: current) else { return }
        let next = forward ? index + 1 : index - 1
        if fields.indices.contains(next) {
            focusedField = fields[next]
        }
    }

    private func submitApplication() async {
        guard await viewModel.submitApplication(name: name, heardAbout: heardAbout, joinReason: joinReason) else { return }

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
