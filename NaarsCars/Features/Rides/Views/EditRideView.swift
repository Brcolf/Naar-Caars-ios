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
    
    init(ride: Ride, onSaved: (() -> Void)? = nil) {
        self.ride = ride
        self.onSaved = onSaved
    }
    
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
                    TextField("Pickup Location", text: $viewModel.pickup)
                    TextField("Destination", text: $viewModel.destination)
                }
                
                Section("Details") {
                    Stepper("Seats: \(viewModel.seats)", value: $viewModel.seats, in: 1...7)
                    
                    TextField("Notes (optional)", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Gift/Compensation (optional)", text: $viewModel.gift)
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
            .navigationTitle("Edit Ride Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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





