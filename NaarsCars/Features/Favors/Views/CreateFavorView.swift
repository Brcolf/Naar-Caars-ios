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
    @Environment(AppState.self) private var appState
    var onFavorCreated: ((UUID) -> Void)? = nil
    @State private var showAddParticipants = false
    @State private var showSuccess = false
    @State private var showErrorAlert = false
    @State private var showGuestPrompt = false
    @State private var guestRestrictionReason: GuestRestrictionReason = .postFavor
    /// Deferred so LocationService init runs off the first frame while user fills title/description.
    @State private var locationServiceReady = false
    
    var body: some View {
        NavigationStack {
            Form {
                if appState.isGuest {
                    Section {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 24)

                            Image(systemName: "lock.shield")
                                .font(.system(size: 48))
                                .foregroundColor(.naarsPrimary.opacity(0.6))

                            Text(GuestRestrictionReason.postFavor.title)
                                .font(.naarsTitle2)
                                .multilineTextAlignment(.center)

                            Text(GuestRestrictionReason.postFavor.message)
                                .font(.naarsBody)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            VStack(spacing: 12) {
                                PrimaryButton(title: "guest_prompt_sign_up".localized) {
                                    appState.isGuestMode = false
                                    AppLaunchManager.shared.exitGuestMode()
                                }
                                SecondaryButton(title: "guest_prompt_log_in".localized) {
                                    appState.isGuestMode = false
                                    AppLaunchManager.shared.exitGuestMode()
                                }
                            }
                            .padding(.horizontal, 32)

                            Spacer().frame(height: 24)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {

                Section("favor_create_section_title_description".localized) {
                    TextField("favor_create_title_placeholder".localized, text: $viewModel.title)
                        .accessibilityIdentifier("createFavor.title")
                        .accessibilityLabel("favor_create_title_accessibility".localized)
                        .accessibilityHint("favor_create_title_hint".localized)
                    TextField("favor_create_description_placeholder".localized, text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createFavor.description")
                        .accessibilityLabel("favor_create_description_accessibility".localized)
                        .accessibilityHint("favor_create_description_hint".localized)
                }
                
                Section("favor_create_section_location_duration".localized) {
                    if locationServiceReady {
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
                        .accessibilityLabel("favor_create_location_placeholder".localized)
                        .accessibilityHint("favor_create_location_hint".localized)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("favor_create_location_loading".localized)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("favor_create_location_loading_accessibility".localized)
                    }
                    
                    Picker("favor_create_duration".localized, selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                    .accessibilityIdentifier("createFavor.duration")
                    .accessibilityHint("favor_create_duration_hint".localized)
                }
                
                Section("favor_create_section_date_time".localized) {
                    DatePicker("favor_create_date".localized, selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityHint("favor_create_date_hint".localized)
                    
                    Toggle("favor_create_specify_time".localized, isOn: $viewModel.hasTime)
                        .accessibilityIdentifier("createFavor.hasTime")
                        .accessibilityHint("favor_create_time_toggle_hint".localized)
                    
                    if viewModel.hasTime {
                        TimePickerView(
                            hour: $viewModel.hour,
                            minute: $viewModel.minute,
                            isAM: $viewModel.isAM
                        )
                        .accessibilityLabel("favor_create_time_accessibility".localized)
                        .accessibilityHint("favor_create_time_hint".localized)
                    }

                    TimeZonePicker(selectedTimezone: $viewModel.timezone)
                }
                
                Section("favor_create_section_details".localized) {
                    TextField("favor_create_requirements_placeholder".localized, text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("createFavor.requirements")
                        .accessibilityLabel("favor_create_requirements_accessibility".localized)
                        .accessibilityHint("favor_create_requirements_hint".localized)
                    
                    TextField("favor_create_gift_placeholder".localized, text: $viewModel.gift)
                        .accessibilityIdentifier("createFavor.gift")
                        .accessibilityLabel("favor_create_gift_accessibility".localized)
                        .accessibilityHint("favor_create_gift_hint".localized)
                }
                
                Section("favor_create_section_participants".localized) {
                    Button {
                        if appState.isGuest {
                            guestRestrictionReason = .addParticipants
                            showGuestPrompt = true
                        } else {
                            showAddParticipants = true
                        }
                    } label: {
                        HStack {
                            Text(viewModel.selectedParticipantIds.isEmpty ? "favor_create_add_participants".localized : "favor_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityIdentifier("createFavor.participants")
                    .accessibilityLabel(viewModel.selectedParticipantIds.isEmpty ? "favor_create_add_participants".localized : "favor_create_participants_selected".localized(with: viewModel.selectedParticipantIds.count))
                    .accessibilityHint("favor_create_participants_hint".localized)
                    
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
                } // end else (authenticated form sections)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // Initialize LocationService off the first frame so title/description section stays responsive.
                Task { @MainActor in
                    _ = LocationService.shared
                    locationServiceReady = true
                }
            }
            .navigationTitle("favor_create_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("favor_create_cancel".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("createFavor.cancel")
                    .accessibilityLabel("favor_create_cancel".localized)
                    .accessibilityHint("favor_create_cancel_hint".localized)
                }
                
                if !appState.isGuest {
                ToolbarItem(placement: .confirmationAction) {
                    Button("favor_create_post".localized) {
                            Task {
                                do {
                                    let favor = try await viewModel.createFavor()
                                    onFavorCreated?(favor.id)
                                    showSuccess = true
                                    HapticManager.success()
                                    try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                                    dismiss()
                                } catch {
                                    showErrorAlert = true
                                }
                            }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("createFavor.post")
                    .accessibilityLabel("favor_create_post_accessibility".localized)
                    .accessibilityHint("favor_create_post_hint".localized)
                }
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
            .alert("common_error".localized, isPresented: $showErrorAlert) {
                Button("common_ok".localized, role: .cancel) {
                    showErrorAlert = false
                }
            } message: {
                Text(viewModel.error ?? "common_unexpected_error".localized)
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    CreateFavorView()
}




