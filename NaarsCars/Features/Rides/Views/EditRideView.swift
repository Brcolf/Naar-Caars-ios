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
                        isAM: $viewModel.isAM
                    )
                }
                
                Section("ride_edit_route".localized) {
                    TextField("ride_edit_pickup_location".localized, text: $viewModel.pickup)
                    TextField("ride_edit_destination".localized, text: $viewModel.destination)
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
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("common_save".localized) {
                        Task {
                            do {
                                // Format time from hour/minute/isAM
                                let formattedTime = viewModel.formatTime(hour: viewModel.hour, minute: viewModel.minute, isAM: viewModel.isAM)
                                
                                _ = try await RideService.shared.updateRide(
                                    id: ride.id,
                                    date: viewModel.date,
                                    time: formattedTime,
                                    pickup: viewModel.pickup.isEmpty ? nil : viewModel.pickup,
                                    destination: viewModel.destination.isEmpty ? nil : viewModel.destination,
                                    seats: viewModel.seats,
                                    notes: viewModel.notes.isEmpty ? nil : viewModel.notes,
                                    gift: viewModel.gift.isEmpty ? nil : viewModel.gift
                                )
                                // Notify parent to refresh before dismissing
                                onSaved?()
                                showSuccess = true
                                HapticManager.success()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    dismiss()
                                }
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
                viewModel.date = ride.date
                viewModel.pickup = ride.pickup
                viewModel.destination = ride.destination
                viewModel.seats = ride.seats
                viewModel.notes = ride.notes ?? ""
                viewModel.gift = ride.gift ?? ""
                
                // Parse existing time
                if let parsedTime = viewModel.parseTime(ride.time) {
                    viewModel.hour = parsedTime.hour
                    viewModel.minute = parsedTime.minute
                    viewModel.isAM = parsedTime.isAM
                }
            }
        }
        .successCheckmark(isShowing: $showSuccess)
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





