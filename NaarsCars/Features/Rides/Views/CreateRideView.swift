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
    @State private var showGuestPrompt = false
    @State private var guestRestrictionReason: GuestRestrictionReason = .postRide
    /// Deferred so LocationService init runs off the first frame while user sets date/time.
    @State private var locationServiceReady = false
    
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
                                SecondaryButton(title: "guest_prompt_log_in".localized) {
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
                    DatePicker("ride_create_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityHint("ride_create_date_hint".localized)
                    
                    TimePickerView(
                        hour: $viewModel.hour,
                        minute: $viewModel.minute,
                        isAM: $viewModel.isAM
                    )
                    .accessibilityLabel("ride_create_time_accessibility".localized)
                    .accessibilityHint("ride_create_time_hint".localized)

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }
                
                Section("ride_create_section_route".localized) {
                    if locationServiceReady {
                        LocationAutocompleteField(
                            label: "",
                            placeholder: "ride_create_pickup_placeholder".localized,
                            text: $viewModel.pickup,
                            icon: "location.circle.fill",
                            accessibilityId: "createRide.pickup"
                        ) { details in
                            // Optional: Store coordinates for future map integration
                            // viewModel.pickupCoordinate = details.coordinate
                        }
                        .accessibilityLabel("ride_create_pickup_placeholder".localized)
                        .accessibilityHint("ride_create_pickup_hint".localized)
                        
                        LocationAutocompleteField(
                            label: "",
                            placeholder: "ride_create_destination_placeholder".localized,
                            text: $viewModel.destination,
                            icon: "mappin.circle.fill",
                            accessibilityId: "createRide.destination"
                        ) { details in
                            // Optional: Store coordinates for future map integration
                            // viewModel.destinationCoordinate = details.coordinate
                        }
                        .accessibilityLabel("ride_create_destination_placeholder".localized)
                        .accessibilityHint("ride_create_destination_hint".localized)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("ride_create_route_loading".localized)
                                .font(.body)
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
                            guestRestrictionReason = .addParticipants
                            showGuestPrompt = true
                        } else {
                            showAddParticipants = true
                        }
                    } label: {
                        HStack {
                            Text(viewModel.selectedParticipantIds.isEmpty ? "ride_create_add_participants".localized : "ride_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityIdentifier("createRide.participants")
                    .accessibilityLabel(viewModel.selectedParticipantIds.isEmpty ? "ride_create_add_participants".localized : "ride_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
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
                        dismiss()
                    }
                    .accessibilityIdentifier("createRide.cancel")
                    .accessibilityLabel("ride_create_cancel".localized)
                    .accessibilityHint("ride_create_cancel_hint".localized)
                }
                
                if !appState.isGuest {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ride_create_post".localized) {
                            Task {
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
                    .disabled(viewModel.isLoading)
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
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    CreateRideView()
}




