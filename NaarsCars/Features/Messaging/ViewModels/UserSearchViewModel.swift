//
//  UserSearchViewModel.swift
//  NaarsCars
//
//  View model for the user search/selection sheet (debounced member search)
//

import Foundation
import PostgREST
internal import Combine

/// Debounced member search on behalf of UserSearchView
@MainActor
final class UserSearchViewModel: ObservableObject {
    @Published var searchResults: [Profile] = []
    @Published var isLoading = false
    @Published var error: AppError?

    private let profileService: any ProfileServiceProtocol
    private let messageService: any MessageServiceProtocol
    private var searchTask: Task<Void, Never>?

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.profileService = profileService
        self.messageService = messageService
    }

    /// Debounced entry point for the search field's onChange
    func scheduleSearch(query: String, excludeUserIds: [UUID]) {
        // Cancel previous search task
        searchTask?.cancel()

        // Debounce search - wait after user stops typing
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.debounceNanoseconds)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            await self?.searchUsers(query: query, excludeUserIds: excludeUserIds)
        }
    }

    /// Clear the current results (e.g. after a selection)
    func clearResults() {
        searchResults = []
    }

    /// Cancel any pending or in-flight search
    func stop() {
        searchTask?.cancel()
        searchTask = nil
    }

    func searchUsers(query: String, excludeUserIds: [UUID]) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Require at least 2 characters to search
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            return
        }

        isLoading = true
        error = nil

        do {
            let profiles = try await profileService.searchPublicProfiles(
                query: trimmedQuery,
                limit: Constants.PageSizes.userSearch
            )

            // Filter out excluded and blocked users
            searchResults = profiles.filter { !excludeUserIds.contains($0.id) && !messageService.isBlocked($0.id) }

            AppLogger.info("messaging", "UserSearchViewModel found \(searchResults.count) users matching '\(trimmedQuery)'")
        } catch {
            AppLogger.error("messaging", "UserSearchViewModel search error: \(error)")
            if let postgrestError = error as? PostgrestError {
                AppLogger.error("messaging", "PostgREST error - code: \(postgrestError.code ?? "none"), message: \(postgrestError.message), hint: \(postgrestError.hint ?? "none")")
            }
            self.error = AppError.processingError("Failed to search users: \(error.localizedDescription)")
            searchResults = []
        }

        isLoading = false
    }
}
