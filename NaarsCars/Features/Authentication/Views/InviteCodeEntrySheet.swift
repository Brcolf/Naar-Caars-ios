//
//  InviteCodeEntrySheet.swift
//  NaarsCars
//
//  Signed-out entry of an invite code, kept on the device until it is used after sign-in
//

import SwiftUI

/// One field and Save. No network: a signed-out person cannot look a code up (spec §3.5,
/// `validate_community_invite` is authenticated only), so the code is checked after sign-in.
struct InviteCodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var isFieldFocused: Bool

    private let store: PendingInviteStore
    private let onSaved: () -> Void

    init(store: PendingInviteStore = PendingInviteStore(), onSaved: @escaping () -> Void) {
        self.store = store
        self.onSaved = onSaved
    }

    private var isWellFormed: Bool {
        CommunityInviteCode.isWellFormed(CommunityInviteCode.normalize(code))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("community_join_code_placeholder".localized, text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .submitLabel(.done)
                        .focused($isFieldFocused)
                        .onSubmit(save)
                        .accessibilityLabel("community_invite_entry_title".localized)
                        .accessibilityIdentifier("welcome.inviteCode.field")
                } footer: {
                    Text("community_invite_entry_footer".localized)
                }

                Section {
                    PrimaryButton(
                        title: "community_invite_entry_save".localized,
                        action: save,
                        isDisabled: !isWellFormed
                    )
                    .accessibilityIdentifier("welcome.inviteCode.save")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .navigationTitle("community_invite_entry_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) { dismiss() }
                        .accessibilityIdentifier("welcome.inviteCode.cancel")
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }

    private func save() {
        guard isWellFormed else { return }
        store.save(code)
        onSaved()
        dismiss()
    }
}

#if DEBUG
#Preview {
    InviteCodeEntrySheet(
        store: PendingInviteStore(defaults: UserDefaults(suiteName: "preview.pendingInvite")!),
        onSaved: {}
    )
}
#endif
