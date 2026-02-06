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
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("favor_create_section_title_description".localized) {
                    TextField("favor_create_title_placeholder".localized, text: $viewModel.title)
                        .accessibilityIdentifier("createFavor.title")
                        .accessibilityLabel("Favor title")
                        .accessibilityHint("Enter a short title for this favor")
                    TextField("favor_create_description_placeholder".localized, text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createFavor.description")
                        .accessibilityLabel("Description")
                        .accessibilityHint("Describe what you need help with")
                }
                
                Section("favor_create_section_location_duration".localized) {
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "favor_create_location_placeholder".localized,
                        text: $viewModel.location,
                        icon: "mappin.circle.fill",
                        accessibilityId: "createFavor.location"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                        // viewModel.locationCoordinate = details.coordinate
                    }
                    .accessibilityLabel("Location")
                    .accessibilityHint("Enter where this favor takes place")
                    
                    Picker("favor_create_duration".localized, selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                    .accessibilityIdentifier("createFavor.duration")
                    .accessibilityHint("Select how long this favor will take")
                }
                
                Section("favor_create_section_date_time".localized) {
                    DatePicker("favor_create_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityHint("Select the date for this favor")
                    
                    Toggle("favor_create_specify_time".localized, isOn: $viewModel.hasTime)
                        .accessibilityIdentifier("createFavor.hasTime")
                        .accessibilityHint("Enable to set a specific time for this favor")
                    
                    if viewModel.hasTime {
                        TimePickerView(
                            hour: $viewModel.hour,
                            minute: $viewModel.minute,
                            isAM: $viewModel.isAM
                        )
                        .accessibilityLabel("Favor time")
                        .accessibilityHint("Set the time for this favor")
                    }
                }
                
                Section("favor_create_section_details".localized) {
                    TextField("favor_create_requirements_placeholder".localized, text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("createFavor.requirements")
                        .accessibilityLabel("Requirements")
                        .accessibilityHint("List any special requirements for this favor")
                    
                    TextField("favor_create_gift_placeholder".localized, text: $viewModel.gift)
                        .accessibilityIdentifier("createFavor.gift")
                        .accessibilityLabel("Gift or thank-you")
                        .accessibilityHint("Optionally offer a gift for the helper")
                }
                
                Section("favor_create_section_participants".localized) {
                    Button {
                        showAddParticipants = true
                    } label: {
                        HStack {
                            Text(viewModel.selectedParticipantIds.isEmpty ? "favor_create_add_participants".localized : "favor_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityIdentifier("createFavor.participants")
                    .accessibilityLabel(viewModel.selectedParticipantIds.isEmpty ? "Add participants" : "\(viewModel.selectedParticipantIds.count) participants selected")
                    .accessibilityHint("Double-tap to select participants for this favor")
                    
                    if viewModel.selectedParticipantIds.count >= 5 {
                        Text("favor_create_max_participants".localized)
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
            .navigationTitle("favor_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("favor_create_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("createFavor.cancel")
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Dismiss without creating a favor")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("favor_create_post".localized) {
                        Task {
                            do {
                                let favor = try await viewModel.createFavor()
                                // Call callback with created favor ID before dismissing
                                onFavorCreated?(favor.id)
                                showSuccess = true
                                HapticManager.success()
                                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                                dismiss()
                            } catch {
                                // Error is already set in viewModel
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("createFavor.post")
                    .accessibilityLabel("Post favor")
                    .accessibilityHint("Double-tap to submit this favor request")
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
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    CreateFavorView()
}




