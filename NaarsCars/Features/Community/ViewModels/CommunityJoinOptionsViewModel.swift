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

    init(service: any CommunityServiceProtocol = CommunityService.shared) {
        self.service = service
    }

    /// Lists public communities except `excluded` (the ones the person is already in or waiting for).
    func load(excluding excluded: Set<UUID>) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        errorMessage = nil
        do {
            let all = try await service.fetchPublicCommunities()
            publicCommunities = all.filter { !excluded.contains($0.id) }
        } catch {
            AppLogger.error("community", "fetchPublicCommunities failed: \(error)")
            publicCommunities = []
            errorMessage = "community_join_public_load_failed".localized
        }
    }
}
