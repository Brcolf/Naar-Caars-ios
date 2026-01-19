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
    var onFavorCreated: ((UUID) -> Void)? = nil
    @State private var showAddParticipants = false
    
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
                    
                    Toggle("Specify Time", isOn: $viewModel.hasTime)
                    
                    if viewModel.hasTime {
                        TimePickerView(
                            hour: $viewModel.hour,
                            minute: $viewModel.minute,
                            isAM: $viewModel.isAM
                        )
                    }
                }
                
                Section("Details") {
                    TextField("Requirements (optional)", text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                    
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
                                let favor = try await viewModel.createFavor()
                                // Call callback with created favor ID before dismissing
                                onFavorCreated?(favor.id)
                                dismiss()
                            } catch {
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
            .trackScreen("CreateFavor")
        }
    }
}

#Preview {
    CreateFavorView()
}




