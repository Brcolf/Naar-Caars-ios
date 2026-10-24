//
//  BroadcastView.swift
//  NaarsCars
//
//  View for sending an announcement to one community
//

import SwiftUI

/// View for sending an announcement to one community. It cannot open without a community: the
/// admin panel passes its `broadcastTarget`.
struct BroadcastView: View {
    @StateObject private var viewModel: BroadcastViewModel
    @State private var showingConfirmation = false
    @State private var showSuccess = false
    @State private var showingDiscardConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(
        communityId: UUID,
        communityName: String,
        viewModel: @autoclosure @escaping () -> BroadcastViewModel? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel()
            ?? BroadcastViewModel(communityId: communityId, communityName: communityName))
    }

    /// Something has been typed that leaving the screen would throw away
    private var hasDraft: Bool {
        !viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // No NavigationStack here: the admin panel pushes this screen onto the Profile tab's
    // stack. A stack of its own drew a second navigation bar and a second Back button.
    var body: some View {
        Form {
            Section {
                TextField("admin_broadcast_title".localized, text: $viewModel.title)
                    .font(.naarsBody)

                TextEditor(text: $viewModel.message)
                    .frame(minHeight: 150)
                    .font(.naarsBody)
                    .overlay(alignment: .topLeading) {
                        // TextEditor has no placeholder of its own; without one the body
                        // was an unlabeled blank area under the title.
                        if viewModel.message.isEmpty {
                            Text("messaging_message".localized)
                                .font(.naarsBody)
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("messaging_message".localized)
            } header: {
                Text("admin_announcement".localized)
            } footer: {
                Text("admin_broadcast_community_footer".localized(with: viewModel.communityName))
            }

            Section {
                Toggle("admin_pin_toggle".localized, isOn: $viewModel.pinToNotifications)
                    .font(.naarsBody)
            } footer: {
                Text("admin_pin_footer_members".localized)
            }

            Section {
                Button(action: {
                    showingConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("admin_send_announcement".localized)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                .foregroundColor(
                    (viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                    ? .secondary
                    : .white
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    (viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                    ? Color.naarsDivider
                    : Color.naarsPrimary
                )
                .cornerRadius(Constants.Radius.sm)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .accessibilityIdentifier("admin.broadcast.error")
                }
            }

        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("admin_send_announcement".localized)
        .navigationBarTitleDisplayMode(.inline)
        // With a draft typed (or a send in flight) the system Back button and the back swipe
        // would discard it without asking, so they give way to a Cancel that asks first.
        .navigationBarBackButtonHidden(hasDraft || viewModel.isLoading)
        .toolbar {
            if hasDraft || viewModel.isLoading {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("admin.broadcast.cancel")
                }
            }
        }
        .confirmationDialog(
            "common_discard_changes_title".localized,
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("common_discard".localized, role: .destructive) {
                dismiss()
            }
            Button("common_keep_editing".localized, role: .cancel) {}
        } message: {
            Text("admin_broadcast_discard_message".localized)
        }
        .alert("admin_send_announcement".localized, isPresented: $showingConfirmation) {
            Button("common_cancel".localized, role: .cancel) {}
            Button("admin_send".localized, role: .none) {
                Task {
                    await viewModel.sendBroadcast()
                }
            }
        } message: {
            Text("admin_broadcast_community_confirmation".localized(with: viewModel.communityName))
        }
        .onChange(of: viewModel.successMessage) { _, newValue in
            if newValue != nil {
                showSuccess = true
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#if DEBUG
#Preview("In a community") {
    NavigationStack {
        BroadcastView(
            communityId: UUID(uuidString: "C0000000-0000-4000-8000-0000000000A1")!,
            communityName: "Ballard Neighbors",
            viewModel: BroadcastViewModel(
                communityId: UUID(uuidString: "C0000000-0000-4000-8000-0000000000A1")!,
                communityName: "Ballard Neighbors",
                adminService: PreviewAdminService()
            )
        )
    }
}

#Preview("Daily limit") {
    let communityId = UUID(uuidString: "C0000000-0000-4000-8000-0000000000A1")!
    let service = PreviewAdminService()
    service.broadcastError = AdminServiceError.broadcastDailyLimit
    let viewModel = BroadcastViewModel(
        communityId: communityId,
        communityName: "Ballard Neighbors",
        adminService: service
    )
    viewModel.title = "Street fair on Saturday"
    viewModel.message = "Come by the corner of 22nd and Market from 10 to 4."
    return NavigationStack {
        BroadcastView(communityId: communityId, communityName: "Ballard Neighbors", viewModel: viewModel)
            .task { await viewModel.sendBroadcast() }
    }
}
#endif
