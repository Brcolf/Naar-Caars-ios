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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    TimePickerView(
                        hour: $viewModel.hour,
                        minute: $viewModel.minute,
                        isAM: $viewModel.isAM
                    )
                }
                
                Section("Route") {
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "Pickup Location",
                        text: $viewModel.pickup,
                        icon: "location.circle.fill"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                        // viewModel.pickupCoordinate = details.coordinate
                    }
                    
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "Destination",
                        text: $viewModel.destination,
                        icon: "mappin.circle.fill"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                        // viewModel.destinationCoordinate = details.coordinate
                    }
                }
                
                Section("Details") {
                    Stepper("Seats: \(viewModel.seats)", value: $viewModel.seats, in: 1...7)
                    
                    TextField("Notes (optional)", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Gift/Compensation (optional)", text: $viewModel.gift)
                }
                
                Section("Participants (Optional)") {
                    Button {
                        showAddParticipants = true
                    } label: {
                        HStack {
                            Text(viewModel.selectedParticipantIds.isEmpty ? "Add Participants" : "\(viewModel.selectedParticipantIds.count) Participant\(viewModel.selectedParticipantIds.count == 1 ? "" : "s") Selected")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    
                    if viewModel.selectedParticipantIds.count >= 5 {
                        Text("Maximum 5 participants")
                            .font(.caption)
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
            .navigationTitle("Create Ride Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            do {
                                print("🔍 [CreateRideView] Starting ride creation...")
                                let ride = try await viewModel.createRide()
                                print("✅ [CreateRideView] Ride created successfully: \(ride.id)")
                                // Call callback with created ride ID before dismissing
                                onRideCreated?(ride.id)
                                dismiss()
                            } catch {
                                print("🔴 [CreateRideView] Error creating ride: \(error.localizedDescription)")
                                print("🔴 [CreateRideView] Error details: \(error)")
                                // Error is already set in viewModel
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
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
        }
    }
}

#Preview {
    CreateRideView()
}




