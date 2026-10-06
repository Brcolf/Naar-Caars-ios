//
//  EditRideView.swift
//  NaarsCars
//
//  View for editing an existing ride request
//

import SwiftUI

/// View for editing an existing ride request
struct EditRideView: View {
    let ride: Ride
    var onSaved: (() -> Void)? = nil
    @StateObject private var viewModel = CreateRideViewModel() // Reuse CreateRideViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var showSuccess = false
    @State private var showDiscardConfirmation = false

    init(ride: Ride, onSaved: (() -> Void)? = nil) {
        self.ride = ride
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("ride_edit_date_time".localized) {
                    DatePicker("ride_edit_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    TimePickerView(
                        hour: $viewModel.hour,
                        minute: $viewModel.minute,
                        isAM: $viewModel.isAM,
                        accessibilityTitle: "ride_create_time_accessibility".localized
                    )

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }

                Section("ride_edit_route".localized) {
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "ride_edit_pickup_location".localized,
                        text: $viewModel.pickup,
                        icon: "location.circle.fill",
                        accessibilityId: "editRide.pickup"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                    }
                    
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "ride_edit_destination".localized,
                        text: $viewModel.destination,
                        icon: "mappin.circle.fill",
                        accessibilityId: "editRide.destination"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                    }
                }
                
                Section("ride_edit_details".localized) {
                    Stepper("ride_edit_seats".localized(with: viewModel.seats), value: $viewModel.seats, in: 1...7)
                    
                    TextField("ride_edit_notes".localized, text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("ride_edit_gift".localized, text: $viewModel.gift)
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("ride_edit_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) {
                        // Ask before throwing away edits.
                        if viewModel.hasUnsavedChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("common_save".localized) {
                        Task {
                            // A second tap that was already queued when the first one started;
                            // Save used to send the update once per tap.
                            guard !viewModel.isLoading else { return }
                            error = nil
                            do {
                                try await viewModel.updateRide(id: ride.id)
                                // Notify parent to refresh before dismissing
                                onSaved?()
                                showSuccess = true
                                HapticManager.success()
                                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                // Pre-populate form with existing ride data
                viewModel.populate(from: ride)
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
        // No swipe-to-dismiss with unsaved edits (Cancel asks first) or while saving.
        .interactiveDismissDisabled(viewModel.isLoading || viewModel.hasUnsavedChanges)
    }
}

#Preview {
    EditRideView(ride: Ride(
        userId: UUID(),
        date: Date(),
        time: "14:30:00",
        pickup: "123 Main St",
        destination: "Airport",
        seats: 2,
        notes: "Need help with luggage",
        status: .open
    ))
}





