//
//  CreateRideView.swift
//  NaarsCars
//
//  View for creating a new ride request
//

import SwiftUI

/// View for creating a new ride request
struct CreateRideView: View {
    @StateObject private var viewModel = CreateRideViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    var onRideCreated: ((UUID) -> Void)? = nil
    @State private var showAddParticipants = false
    @State private var showSuccess = false
    @State private var showErrorAlert = false
    @State private var guestPromptReason: GuestRestrictionReason?
    /// Deferred so LocationService init runs off the first frame while user sets date/time.
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

                            Text(GuestRestrictionReason.postRide.title)
                                .font(.naarsTitle2)
                                .multilineTextAlignment(.center)

                            Text(GuestRestrictionReason.postRide.message)
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

                Section("ride_create_section_date_time".localized) {
                    // Past days are not offered; they used to be selectable and rejected on Post.
                    DatePicker(
                        "ride_create_date".localized,
                        selection: $viewModel.date,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                        .datePickerStyle(.compact)
                        .accessibilityHint("ride_create_date_hint".localized)

                    // The time label goes into the picker, which names each of its three menus.
                    // Set on the picker from here it replaced all three names and values.
                    TimePickerView(
                        hour: $viewModel.hour,
                        minute: $viewModel.minute,
                        isAM: $viewModel.isAM,
                        accessibilityTitle: "ride_create_time_accessibility".localized
                    )

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }
                
                Section("ride_create_section_route".localized) {
                    if locationServiceReady {
                        LocationAutocompleteField(
                            label: "",
                            placeholder: "ride_create_pickup_placeholder".localized,
                            text: $viewModel.pickup,
                            icon: "location.circle.fill",
                            accessibilityId: "createRide.pickup",
                            accessibilityHintText: "ride_create_pickup_hint".localized
                        ) { details in
                            // Optional: Store coordinates for future map integration
                            // viewModel.pickupCoordinate = details.coordinate
                        }

                        LocationAutocompleteField(
                            label: "",
                            placeholder: "ride_create_destination_placeholder".localized,
                            text: $viewModel.destination,
                            icon: "mappin.circle.fill",
                            accessibilityId: "createRide.destination",
                            accessibilityHintText: "ride_create_destination_hint".localized
                        ) { details in
                            // Optional: Store coordinates for future map integration
                            // viewModel.destinationCoordinate = details.coordinate
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("ride_create_route_loading".localized)
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("ride_create_route_loading_accessibility".localized)
                    }
                }
                
                Section("ride_create_section_details".localized) {
                    Stepper("ride_create_seats_count".localized(with: viewModel.seats), value: $viewModel.seats, in: 1...7)
                        .accessibilityLabel("ride_create_seats_accessibility".localized(with: viewModel.seats))
                        .accessibilityHint("ride_create_seats_hint".localized)
                    
                    TextField("ride_create_notes_placeholder".localized, text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createRide.notes")
                        .accessibilityLabel("ride_create_notes_accessibility".localized)
                        .accessibilityHint("ride_create_notes_hint".localized)
                    
                    TextField("ride_create_gift_placeholder".localized, text: $viewModel.gift)
                        .accessibilityIdentifier("createRide.gift")
                        .accessibilityLabel("ride_create_gift_accessibility".localized)
                        .accessibilityHint("ride_create_gift_hint".localized)
                }
                
                Section("ride_create_section_participants".localized) {
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
                    .accessibilityIdentifier("createRide.participants")
                    .accessibilityLabel(participantsButtonTitle)
                    .accessibilityHint("ride_create_participants_hint".localized)
                    
                    if viewModel.selectedParticipantIds.count >= 5 {
                        Text("ride_create_max_participants".localized)
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
                // Initialize LocationService off the first frame so date/time section stays responsive.
                Task { @MainActor in
                    _ = LocationService.shared
                    locationServiceReady = true
                }
            }
            .navigationTitle("ride_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ride_create_cancel".localized) {
                        // Ask before throwing away a filled-in form.
                        if viewModel.hasUnsavedChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("createRide.cancel")
                    .accessibilityLabel("ride_create_cancel".localized)
                    .accessibilityHint("ride_create_cancel_hint".localized)
                }

                if !appState.isGuest {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ride_create_post".localized) {
                        // A time earlier today is usually a slip (AM left in place of PM), but
                        // it can be meant, so ask instead of refusing.
                        if viewModel.isEventTimeInPast {
                            showPastTimeConfirmation = true
                        } else {
                            submitRide()
                        }
                    }
                    .disabled(viewModel.isLoading || !viewModel.hasRequiredFields)
                    .accessibilityIdentifier("createRide.post")
                    .accessibilityLabel("ride_create_post_accessibility".localized)
                    .accessibilityHint("ride_create_post_hint".localized)
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
            .trackScreen("CreateRide")
            .alert("common_error".localized, isPresented: $showErrorAlert) {
                Button("common_ok".localized, role: .cancel) {
                    showErrorAlert = false
                }
            } message: {
                Text(viewModel.error ?? "common_unexpected_error".localized)
            }
            .alert("request_time_passed_title".localized, isPresented: $showPastTimeConfirmation) {
                Button("request_time_passed_post_anyway".localized) {
                    submitRide()
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
        // in flight: a swipe mid-request still created the ride, and its id was then consumed
        // by the next, unrelated dismissal of this sheet.
        .interactiveDismissDisabled(viewModel.isLoading || viewModel.hasUnsavedChanges)
    }

    private var participantsButtonTitle: String {
        let count = viewModel.selectedParticipantIds.count
        if count == 0 {
            return "ride_create_add_participants".localized
        }
        // Two keys chosen here; the catalog has no plural variants ("1 Participant(s) Selected").
        return (count == 1 ? "request_participants_selected_one" : "request_participants_selected_other")
            .localized(with: count)
    }

    private func submitRide() {
        Task {
            // A second tap that was already queued when the first one started.
            guard !viewModel.isLoading else { return }
            do {
                AppLogger.info("rides", "[CreateRideView] Starting ride creation...")
                let ride = try await viewModel.createRide()
                AppLogger.info("rides", "[CreateRideView] Ride created successfully: \(ride.id)")
                // Call callback with created ride ID before dismissing
                onRideCreated?(ride.id)
                showSuccess = true
                HapticManager.success()
                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                dismiss()
            } catch {
                AppLogger.error("rides", "[CreateRideView] Error creating ride: \(error.localizedDescription)")
                AppLogger.error("rides", "[CreateRideView] Error details: \(error)")
                showErrorAlert = true
            }
        }
    }
}

#Preview {
    CreateRideView()
}




