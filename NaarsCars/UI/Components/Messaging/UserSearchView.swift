//
//  UserSearchView.swift
//  NaarsCars
//
//  View for searching and selecting users
//

import SwiftUI

/// View for searching and selecting users
struct UserSearchView: View {
    @Binding var selectedUserIds: Set<UUID>
    let excludeUserIds: [UUID] // Users to exclude from search (e.g., already in conversation)
    let showExistingParticipants: Bool // Whether to show existing participants as selected (non-removable)
    let actionButtonTitle: String // Title for the action button (default: "Done")
    let onDismiss: () -> Void
    
    @State private var searchText = ""
    @StateObject private var viewModel = UserSearchViewModel()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    init(
        selectedUserIds: Binding<Set<UUID>>,
        excludeUserIds: [UUID],
        showExistingParticipants: Bool = true,
        actionButtonTitle: String = "common_done".localized,
        onDismiss: @escaping () -> Void
    ) {
        self._selectedUserIds = selectedUserIds
        self.excludeUserIds = excludeUserIds
        self.showExistingParticipants = showExistingParticipants
        self.actionButtonTitle = actionButtonTitle
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar with auto-focus
                SearchBar(
                    text: $searchText,
                    placeholder: "messaging_search_users_placeholder".localized,
                    isFocused: $isSearchFocused
                )
                .padding()
                .onChange(of: searchText) { _, newValue in
                    viewModel.scheduleSearch(query: newValue, excludeUserIds: excludeUserIds)
                }
                .onAppear {
                    // Auto-focus search field when view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSearchFocused = true
                    }
                }
                
                // Selected users section (always visible at top if any selected or existing participants)
                if !selectedUserIds.isEmpty || (showExistingParticipants && !excludeUserIds.isEmpty) {
                    VStack(alignment: .leading, spacing: 8) {
                        let totalCount = selectedUserIds.count + (showExistingParticipants ? excludeUserIds.count : 0)
                        Text(showExistingParticipants && !excludeUserIds.isEmpty ? "messaging_participants_count".localized(with: totalCount) : "messaging_selected_count".localized(with: selectedUserIds.count))
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // Show existing participants first (non-removable)
                                if showExistingParticipants {
                                    ForEach(excludeUserIds, id: \.self) { userId in
                                        SelectedUserChip(userId: userId, isRemovable: false) {
                                            // No-op for existing participants
                                        }
                                    }
                                }
                                
                                // Show newly selected users (removable)
                                ForEach(Array(selectedUserIds), id: \.self) { userId in
                                    SelectedUserChip(userId: userId, isRemovable: true) {
                                        selectedUserIds.remove(userId)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider()
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }
                
                // Results list
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty && !searchText.isEmpty {
                    EmptyStateView(
                        icon: "person.fill.questionmark",
                        title: "messaging_no_users_found_title".localized,
                        message: "messaging_no_users_found_message".localized
                    )
                } else if viewModel.searchResults.isEmpty && searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "messaging_search_for_users_title".localized,
                        message: selectedUserIds.isEmpty ? "messaging_search_users_hint".localized : "messaging_search_users_hint_selected".localized
                    )
                } else {
                    List {
                        ForEach(viewModel.searchResults) { profile in
                            UserSearchRow(
                                profile: profile,
                                isSelected: selectedUserIds.contains(profile.id),
                                isExcluded: excludeUserIds.contains(profile.id)
                            ) {
                                if selectedUserIds.contains(profile.id) {
                                    selectedUserIds.remove(profile.id)
                                } else if !excludeUserIds.contains(profile.id) {
                                    selectedUserIds.insert(profile.id)
                                    // Clear search after selection for easier multi-select
                                    searchText = ""
                                    viewModel.clearResults()
                                    // Refocus search for next selection
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isSearchFocused = true
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("messaging_select_users_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common_cancel".localized) {
                        AppLogger.info("messaging", "UserSearchView cancel tapped, clearing selections and dismissing")
                        selectedUserIds.removeAll()
                        dismiss()
                        onDismiss()
                    }
                    .accessibilityIdentifier("userSearch.cancel")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(actionButtonTitle) {
                        AppLogger.info("messaging", "UserSearchView \(actionButtonTitle) tapped with \(selectedUserIds.count) selected user(s), dismissing")
                        dismiss()
                        onDismiss()
                    }
                    .disabled(selectedUserIds.isEmpty)
                    .accessibilityIdentifier("userSearch.done")
                }
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

/// Row component for user search results
private struct UserSearchRow: View {
    let profile: Profile
    let isSelected: Bool
    let isExcluded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(
                    imageUrl: profile.avatarUrl,
                    name: profile.name,
                    size: 50,
                    userId: profile.id
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isExcluded {
                    Text("messaging_already_added".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.naarsTitle3)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.naarsTitle3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
        }
        .disabled(isExcluded)
        .opacity(isExcluded ? 0.5 : 1.0)
        // The check mark is the only visual sign of selection; say it to VoiceOver as a trait.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("userSearch.row.\(profile.id.uuidString)")
    }
}

/// Search bar component with focus binding
private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.vertical, 8)
                .accessibilityIdentifier("userSearch.searchField")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("messaging_search_clear_accessibility".localized)
            }
        }
        .padding(.horizontal, 12)
        // At least 44 pt tall, so the clear button gets a full-size target and the field
        // does not change height when the button appears.
        .frame(minHeight: 44)
        .background(Color.naarsCardBackground)
        .cornerRadius(10)
    }
}

/// Selected user chip component
private struct SelectedUserChip: View {
    let userId: UUID
    let isRemovable: Bool
    let onRemove: () -> Void
    
    @State private var profile: Profile?
    
    var body: some View {
        HStack(spacing: 4) {
            if let profile = profile {
                AvatarView(
                    imageUrl: profile.avatarUrl,
                    name: profile.name,
                    size: 32
                )
                
                Text(profile.name)
                    .font(.naarsCaption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
            
            if isRemovable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(
                    profile.map { "messaging_remove_participant_accessibility".localized(with: $0.name) }
                        ?? "common_remove".localized
                )
            }
        }
        // The remove button brings its own 44-pt target, so a removable chip takes its
        // trailing and vertical room from the button; the chip stays 44 pt tall either way.
        .padding(.leading, 8)
        .padding(.trailing, isRemovable ? 0 : 8)
        .padding(.vertical, isRemovable ? 0 : 6)
        .frame(minHeight: 44)
        .background(isRemovable ? Color(.systemGray5) : Color.naarsCardBackground)
        .cornerRadius(16)
        .task {
            await loadProfile()
        }
    }
    
    private func loadProfile() async {
        do {
            profile = try await ProfileService.shared.fetchProfile(userId: userId)
        } catch {
            AppLogger.error("messaging", "Error loading profile for chip: \(error.localizedDescription)")
        }
    }
}

#Preview {
    UserSearchView(
        selectedUserIds: .constant([]),
        excludeUserIds: [],
        onDismiss: {}
    )
}

