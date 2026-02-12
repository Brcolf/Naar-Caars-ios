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
    var onRideCreated: ((UUID) -> Void)? = nil
    @State private var showAddParticipants = false
    @State private var showSuccess = false
    @State private var showErrorAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("ride_create_section_date_time".localized) {
                    DatePicker("ride_create_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityHint("Select the date for this ride")
                    
                    TimePickerView(
                        hour: $viewModel.hour,
                        minute: $viewModel.minute,
                        isAM: $viewModel.isAM
                    )
                    .accessibilityLabel("Ride time")
                    .accessibilityHint("Set the departure time")
                }
                
                Section("ride_create_section_route".localized) {
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
                    .accessibilityLabel("Pickup location")
                    .accessibilityHint("Enter the pickup address")
                    
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
                    .accessibilityLabel("Destination")
                    .accessibilityHint("Enter the destination address")
                }
                
                Section("ride_create_section_details".localized) {
                    Stepper("ride_create_seats_count".localized(with: viewModel.seats), value: $viewModel.seats, in: 1...7)
                        .accessibilityLabel("Available seats, currently \(viewModel.seats)")
                        .accessibilityHint("Adjust the number of available seats")
                    
                    TextField("ride_create_notes_placeholder".localized, text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createRide.notes")
                        .accessibilityLabel("Notes")
                        .accessibilityHint("Add optional notes about this ride")
                    
                    TextField("ride_create_gift_placeholder".localized, text: $viewModel.gift)
                        .accessibilityIdentifier("createRide.gift")
                        .accessibilityLabel("Gift or thank-you")
                        .accessibilityHint("Optionally offer a gift for the driver")
                }
                
                Section("ride_create_section_participants".localized) {
                    Button {
                        showAddParticipants = true
                    } label: {
                        HStack {
                            Text(viewModel.selectedParticipantIds.isEmpty ? "ride_create_add_participants".localized : "ride_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityIdentifier("createRide.participants")
                    .accessibilityLabel(viewModel.selectedParticipantIds.isEmpty ? "Add participants" : "\(viewModel.selectedParticipantIds.count) participants selected")
                    .accessibilityHint("Double-tap to select participants for this ride")
                    
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
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("ride_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ride_create_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("createRide.cancel")
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Dismiss without creating a ride")
                }
                
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
                    .accessibilityLabel("Post ride")
                    .accessibilityHint("Double-tap to submit this ride request")
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
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    showErrorAlert = false
                }
            } message: {
                Text(viewModel.error ?? "An unexpected error occurred.")
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    CreateRideView()
}




