//
//  CreateFavorView.swift
//  NaarsCars
//
//  View for creating a new favor request
//

import SwiftUI

/// View for creating a new favor request
struct CreateFavorView: View {
    @StateObject private var viewModel = CreateFavorViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    var onFavorCreated: ((UUID) -> Void)? = nil
    @State private var showAddParticipants = false
    @State private var showSuccess = false
    @State private var showErrorAlert = false
    @State private var guestPromptReason: GuestRestrictionReason?
    /// Deferred so LocationService init runs off the first frame while user fills title/description.
    @State private var locationServiceReady = false
    @State private var showDiscardConfirmation = false
    @State private var showPastTimeConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if appState.isGuest {
                    Section {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 24)

                            Image(systemName: "lock.shield")
                                .font(.system(size: 48))
                                .foregroundColor(.naarsPrimary.opacity(0.6))

                            Text(GuestRestrictionReason.postFavor.title)
                                .font(.naarsTitle2)
                                .multilineTextAlignment(.center)

                            Text(GuestRestrictionReason.postFavor.message)
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            VStack(spacing: 12) {
                                PrimaryButton(title: "guest_prompt_sign_up".localized) {
                                    appState.isGuestMode = false
                                    AppLaunchManager.shared.exitGuestMode()
                                }
                                SecondaryButton(title: "auth_sign_in_button".localized) {
                                    // Welcome continues to the sign-in form for this choice
                                    WelcomeEntryRoute.opensSignIn = true
                                    appState.isGuestMode = false
                                    AppLaunchManager.shared.exitGuestMode()
                                }
                            }
                            .padding(.horizontal, 32)

                            Spacer().frame(height: 24)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {

                Section("favor_create_section_title_description".localized) {
                    TextField("favor_create_title_placeholder".localized, text: $viewModel.title)
                        .accessibilityIdentifier("createFavor.title")
                        .accessibilityLabel("favor_create_title_accessibility".localized)
                        .accessibilityHint("favor_create_title_hint".localized)
                    TextField("favor_create_description_placeholder".localized, text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createFavor.description")
                        .accessibilityLabel("favor_create_description_accessibility".localized)
                        .accessibilityHint("favor_create_description_hint".localized)
                }
                
                Section("favor_create_section_location_duration".localized) {
                    if locationServiceReady {
                        LocationAutocompleteField(
                            label: "",
                            placeholder: "favor_create_location_placeholder".localized,
                            text: $viewModel.location,
                            icon: "mappin.circle.fill",
                            accessibilityId: "createFavor.location",
                            accessibilityHintText: "favor_create_location_hint".localized
                        ) { details in
                            // Optional: Store coordinates for future map integration
                            // viewModel.locationCoordinate = details.coordinate
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("favor_create_location_loading".localized)
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("favor_create_location_loading_accessibility".localized)
                    }
                    
                    Picker("favor_create_duration".localized, selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                    .accessibilityIdentifier("createFavor.duration")
                    .accessibilityHint("favor_create_duration_hint".localized)
                }
                
                Section("favor_create_section_date_time".localized) {
                    // Past days are not offered; they used to be selectable and rejected on Post.
                    DatePicker(
                        "favor_create_date".localized,
                        selection: $viewModel.date,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                        .datePickerStyle(.compact)
                        .accessibilityHint("favor_create_date_hint".localized)

                    Toggle("favor_create_specify_time".localized, isOn: $viewModel.hasTime)
                        .accessibilityIdentifier("createFavor.hasTime")
                        .accessibilityHint("favor_create_time_toggle_hint".localized)

                    if viewModel.hasTime {
                        // The time label goes into the picker, which names each of its three
                        // menus. Set on the picker from here it replaced all three names and values.
                        TimePickerView(
                            hour: $viewModel.hour,
                            minute: $viewModel.minute,
                            isAM: $viewModel.isAM,
                            accessibilityTitle: "favor_create_time_accessibility".localized
                        )
                    }

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }
                
                Section("favor_create_section_details".localized) {
                    TextField("favor_create_requirements_placeholder".localized, text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("createFavor.requirements")
                        .accessibilityLabel("favor_create_requirements_accessibility".localized)
                        .accessibilityHint("favor_create_requirements_hint".localized)
                    
                    TextField("favor_create_gift_placeholder".localized, text: $viewModel.gift)
                        .accessibilityIdentifier("createFavor.gift")
                        .accessibilityLabel("favor_create_gift_accessibility".localized)
                        .accessibilityHint("favor_create_gift_hint".localized)
                }
                
                Section("favor_create_section_participants".localized) {
                    Button {
                        if appState.isGuest {
                            guestPromptReason = .addParticipants
                        } else {
                            showAddParticipants = true
                        }
                    } label: {
                        HStack {
                            Text(participantsButtonTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityIdentifier("createFavor.participants")
                    .accessibilityLabel(participantsButtonTitle)
                    .accessibilityHint("favor_create_participants_hint".localized)
                    
                    if viewModel.selectedParticipantIds.count >= 5 {
                        Text("favor_create_max_participants".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
                } // end else (authenticated form sections)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // Initialize LocationService off the first frame so title/description section stays responsive.
                Task { @MainActor in
                    _ = LocationService.shared
                    locationServiceReady = true
                }
            }
            .navigationTitle("favor_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("favor_create_cancel".localized) {
                        // Ask before throwing away a filled-in form.
                        if viewModel.hasUnsavedChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("createFavor.cancel")
                    .accessibilityLabel("favor_create_cancel".localized)
                    .accessibilityHint("favor_create_cancel_hint".localized)
                }

                if !appState.isGuest {
                ToolbarItem(placement: .confirmationAction) {
                    Button("favor_create_post".localized) {
                        // A time earlier today is usually a slip (AM left in place of PM), but
                        // it can be meant, so ask instead of refusing.
                        if viewModel.isEventTimeInPast {
                            showPastTimeConfirmation = true
                        } else {
                            submitFavor()
                        }
                    }
                    .disabled(viewModel.isLoading || !viewModel.hasRequiredFields)
                    .accessibilityIdentifier("createFavor.post")
                    .accessibilityLabel("favor_create_post_accessibility".localized)
                    .accessibilityHint("favor_create_post_hint".localized)
                }
                }
            }
            .sheet(isPresented: $showAddParticipants) {
                UserSearchView(
                    selectedUserIds: $viewModel.selectedParticipantIds,
                    excludeUserIds: [AuthService.shared.currentUserId].compactMap { $0 },
                    onDismiss: {
                        showAddParticipants = false
                    }
                )
            }
            .trackScreen("CreateFavor")
            .alert("common_error".localized, isPresented: $showErrorAlert) {
                Button("common_ok".localized, role: .cancel) {
                    showErrorAlert = false
                }
            } message: {
                Text(viewModel.error ?? "common_unexpected_error".localized)
            }
            .alert("request_time_passed_title".localized, isPresented: $showPastTimeConfirmation) {
                Button("request_time_passed_post_anyway".localized) {
                    submitFavor()
                }
                Button("request_time_passed_change".localized, role: .cancel) {}
            } message: {
                Text("request_time_passed_message".localized)
            }
            .confirmationDialog(
                "common_discard_changes_title".localized,
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("common_discard".localized, role: .destructive) {
                    dismiss()
                }
                Button("common_keep_editing".localized, role: .cancel) {}
            } message: {
                Text("request_form_discard_message".localized)
            }
        }
        .successCheckmark(isShowing: $showSuccess)
        // No swipe-to-dismiss with something typed (Cancel asks first) or while the request is
        // in flight: a swipe mid-request still created the favor, and its id was then consumed
        // by the next, unrelated dismissal of this sheet.
        .interactiveDismissDisabled(viewModel.isLoading || viewModel.hasUnsavedChanges)
    }

    private var participantsButtonTitle: String {
        let count = viewModel.selectedParticipantIds.count
        if count == 0 {
            return "favor_create_add_participants".localized
        }
        // Two keys chosen here; the catalog has no plural variants ("1 Participant(s) Selected").
        return (count == 1 ? "request_participants_selected_one" : "request_participants_selected_other")
            .localized(with: count)
    }

    private func submitFavor() {
        Task {
            // A second tap that was already queued when the first one started.
            guard !viewModel.isLoading else { return }
            do {
                let favor = try await viewModel.createFavor()
                onFavorCreated?(favor.id)
                showSuccess = true
                HapticManager.success()
                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                dismiss()
            } catch {
                showErrorAlert = true
            }
        }
    }
}

#Preview {
    CreateFavorView()
}




