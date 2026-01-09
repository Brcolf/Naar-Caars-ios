//
//  UserSearchView.swift
//  NaarsCars
//
//  View for searching and selecting users
//

import SwiftUI
import Supabase
import PostgREST

/// View for searching and selecting users
struct UserSearchView: View {
    @Binding var selectedUserIds: Set<UUID>
    let excludeUserIds: [UUID] // Users to exclude from search (e.g., already in conversation)
    let onDismiss: () -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [Profile] = []
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search users...")
                    .padding()
                    .onChange(of: searchText) { _, newValue in
                        // Cancel previous search task
                        searchTask?.cancel()
                        
                        // Debounce search - wait 300ms after user stops typing
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                            
                            // Check if task was cancelled
                            guard !Task.isCancelled else { return }
                            
                            await searchUsers(query: newValue)
                        }
                    }
                
                // Results list
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    EmptyStateView(
                        icon: "person.fill.questionmark",
                        title: "No Users Found",
                        message: "Try a different search term"
                    )
                } else if searchResults.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search for Users",
                        message: "Type a name or email to find users"
                    )
                } else {
                    List {
                        ForEach(searchResults) { profile in
                            UserSearchRow(
                                profile: profile,
                                isSelected: selectedUserIds.contains(profile.id),
                                isExcluded: excludeUserIds.contains(profile.id)
                            ) {
                                if selectedUserIds.contains(profile.id) {
                                    selectedUserIds.remove(profile.id)
                                } else if !excludeUserIds.contains(profile.id) {
                                    selectedUserIds.insert(profile.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .disabled(selectedUserIds.isEmpty)
                }
            }
        }
    }
    
    private func searchUsers(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Require at least 2 characters to search
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            // Search profiles by name or email
            // PostgREST .or() syntax: "column.operator.value,column.operator.value"
            // Use * as wildcard for ilike (case-insensitive LIKE)
            // Escape special characters for PostgREST ilike pattern
            // In PostgREST, * is the wildcard for ilike, so we need to escape it if it appears in the query
            let escapedQuery = trimmedQuery.replacingOccurrences(of: "*", with: "\\*")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let searchPattern = "*\(escapedQuery)*"
            
            print("🔍 [UserSearchView] Searching for: '\(trimmedQuery)' (pattern: '\(searchPattern)')")
            
            // Select all fields (Profile model requires all fields)
            // Using .select() without arguments gets all columns, matching other services
            let response = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .or("name.ilike.\(searchPattern),email.ilike.\(searchPattern)")
                .eq("approved", value: true)
                .limit(20)
                .execute()
            
            // Use custom date decoder to handle various date formats
            // Profile model handles snake_case via CodingKeys
            let decoder = JSONDecoder()
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Try ISO8601 with fractional seconds
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                
                // Try ISO8601 without fractional seconds
                dateFormatter.formatOptions = [.withInternetDateTime]
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                
                // Try YYYY-MM-DD format
                let simpleFormatter = DateFormatter()
                simpleFormatter.dateFormat = "yyyy-MM-dd"
                simpleFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = simpleFormatter.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
            }
            
            let profiles: [Profile] = try decoder.decode([Profile].self, from: response.data)
            
            // Filter out excluded users
            searchResults = profiles.filter { !excludeUserIds.contains($0.id) }
            
            print("✅ [UserSearchView] Found \(searchResults.count) users matching '\(trimmedQuery)'")
        } catch {
            print("🔴 [UserSearchView] Search error: \(error)")
            if let postgrestError = error as? PostgrestError {
                print("   PostgREST error code: \(postgrestError.code ?? "none")")
                print("   PostgREST message: \(postgrestError.message ?? "none")")
                print("   PostgREST hint: \(postgrestError.hint ?? "none")")
            }
            self.error = AppError.processingError("Failed to search users: \(error.localizedDescription)")
            searchResults = []
        }
        
        isLoading = false
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
                    size: 50
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    
                    Text(profile.email)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isExcluded {
                    Text("Already added")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.naarsPrimary)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
        }
        .disabled(isExcluded)
        .opacity(isExcluded ? 0.5 : 1.0)
    }
}

/// Search bar component
private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    UserSearchView(
        selectedUserIds: .constant([]),
        excludeUserIds: [],
        onDismiss: {}
    )
}

