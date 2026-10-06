//
//  EditFavorView.swift
//  NaarsCars
//
//  View for editing an existing favor request
//

import SwiftUI

/// View for editing an existing favor request
struct EditFavorView: View {
    let favor: Favor
    var onSaved: (() -> Void)? = nil
    @StateObject private var viewModel = CreateFavorViewModel() // Reuse CreateFavorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var showSuccess = false
    @State private var showDiscardConfirmation = false

    init(favor: Favor, onSaved: (() -> Void)? = nil) {
        self.favor = favor
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("favor_edit_title_description".localized) {
                    TextField("favor_edit_title_field".localized, text: $viewModel.title)
                    TextField("favor_edit_description".localized, text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("favor_edit_location_duration".localized) {
                    LocationAutocompleteField(
                        label: "",
                        placeholder: "favor_edit_location".localized,
                        text: $viewModel.location,
                        icon: "mappin.circle.fill",
                        accessibilityId: "editFavor.location"
                    ) { details in
                        // Optional: Store coordinates for future map integration
                    }
                    
                    Picker("favor_edit_duration".localized, selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                }
                
                Section("favor_edit_date_time".localized) {
                    DatePicker("favor_edit_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    Toggle("favor_edit_specify_time".localized, isOn: $viewModel.hasTime)
                    
                    if viewModel.hasTime {
                        TimePickerView(
                            hour: $viewModel.hour,
                            minute: $viewModel.minute,
                            isAM: $viewModel.isAM,
                            accessibilityTitle: "favor_create_time_accessibility".localized
                        )
                    }

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }
                
                Section("favor_edit_details".localized) {
                    TextField("favor_edit_requirements".localized, text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                    
                    TextField("favor_edit_gift".localized, text: $viewModel.gift)
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
            .navigationTitle("favor_edit_title".localized)
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
                                try await viewModel.updateFavor(id: favor.id)
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
                // Pre-populate form with existing favor data
                viewModel.populate(from: favor)
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
    EditFavorView(favor: Favor(
        userId: UUID(),
        title: "Help moving",
        location: "123 Main St",
        duration: .coupleHours,
        date: Date(),
        status: .open
    ))
}





