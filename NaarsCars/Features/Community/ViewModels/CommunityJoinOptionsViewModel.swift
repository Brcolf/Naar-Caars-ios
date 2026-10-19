//
//  CommunityJoinOptionsViewModel.swift
//  NaarsCars
//
//  Loads the public communities a person can ask to join
//

internal import Combine
import Foundation

@MainActor
final class CommunityJoinOptionsViewModel: ObservableObject {
    @Published private(set) var publicCommunities: [PublicCommunity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let service: any CommunityServiceProtocol
    /// Only the newest load writes its result. The view loads from `.task(id: excludedCommunityIds)`,
    /// which cancels a load and starts the next at once when the ids change (the memberships arrive
    /// after the Join sheet opened); a guard on `isLoading` used to drop that next load.
    private var loadGeneration = 0

    init(service: any CommunityServiceProtocol = CommunityService.shared) {
        self.service = service
    }

    /// Lists public communities except `excluded` (the ones the person is already in or waiting for).
    func load(excluding excluded: Set<UUID>) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let all = try await service.fetchPublicCommunities()
            guard generation == loadGeneration else { return }
            publicCommunities = all.filter { !excluded.contains($0.id) }
        } catch {
            // A cancelled request is not a failure the person can act on: a newer load replaced this
            // one, or the view went away and loads again when it is back (the rule of 8ee7da4). Seen on
            // device at the Phase 4 gate as "Couldn't load public communities." after a cold-start link.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            guard generation == loadGeneration else { return }
            AppLogger.error("community", "fetchPublicCommunities failed: \(error)")
            publicCommunities = []
            errorMessage = "community_join_public_load_failed".localized
        }
        isLoading = false
        hasLoaded = true
    }
}
