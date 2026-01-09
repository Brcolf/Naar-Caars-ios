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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Title & Description") {
                    TextField("Title", text: $viewModel.title)
                    TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Location & Duration") {
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "Location",
                        text: $viewModel.location,
                        icon: "mappin.circle.fill"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                        // viewModel.locationCoordinate = details.coordinate
                    }
                    
                    Picker("Duration", selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                }
                
                Section("Date & Time") {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    HStack {
                        Text("Time (optional)")
                        Spacer()
                        TextField("HH:mm", text: $viewModel.time)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Details") {
                    TextField("Requirements (optional)", text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                    
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
            .navigationTitle("Create Favor Request")
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
                                _ = try await viewModel.createFavor()
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
    CreateFavorView()
}




