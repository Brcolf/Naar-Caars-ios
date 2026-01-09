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
                                _ = try await viewModel.createRide()
                                dismiss()
                            } catch {
                                // Error is already set in viewModel
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }
}

#Preview {
    CreateRideView()
}




