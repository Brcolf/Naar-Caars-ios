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
    @StateObject private var viewModel = CreateRideViewModel() // Reuse CreateRideViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    
    init(ride: Ride) {
        self.ride = ride
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    HStack {
                        Text("Time")
                        Spacer()
                        TextField("HH:mm", text: $viewModel.time)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
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
                                _ = try await RideService.shared.updateRide(
                                    id: ride.id,
                                    date: viewModel.date,
                                    time: viewModel.time.isEmpty ? nil : viewModel.time,
                                    pickup: viewModel.pickup.isEmpty ? nil : viewModel.pickup,
                                    destination: viewModel.destination.isEmpty ? nil : viewModel.destination,
                                    seats: viewModel.seats,
                                    notes: viewModel.notes.isEmpty ? nil : viewModel.notes,
                                    gift: viewModel.gift.isEmpty ? nil : viewModel.gift
                                )
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
                viewModel.time = ride.time
                viewModel.pickup = ride.pickup
                viewModel.destination = ride.destination
                viewModel.seats = ride.seats
                viewModel.notes = ride.notes ?? ""
                viewModel.gift = ride.gift ?? ""
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




