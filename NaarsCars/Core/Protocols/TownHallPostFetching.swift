//
//  TownHallPostFetching.swift
//  NaarsCars
//

import Foundation

/// The two Town Hall post reads `TownHallSyncEngine` needs, behind a protocol so the
/// engine can be tested with a stub (Architecture rule 5).
protocol TownHallPostFetching: AnyObject {
    /// One page of posts, newest first. A nil `communityId` means "no community filter"
    /// (RLS still returns only the caller's communities). `serverCount` is the number of
    /// rows the server returned before posts by blocked authors were filtered out.
    func fetchPostsPage(limit: Int, offset: Int, communityId: UUID?) async throws -> (posts: [TownHallPost], serverCount: Int)

    /// A single enriched post, or nil when it is not readable (hidden, deleted, in a
    /// community the caller is not in, or by a blocked author). Throws only on a
    /// transport or decoding failure.
    func fetchPost(id: UUID) async throws -> TownHallPost?
}
