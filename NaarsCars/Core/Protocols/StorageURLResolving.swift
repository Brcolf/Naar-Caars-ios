//
//  StorageURLResolving.swift
//  NaarsCars
//

import Foundation

/// Signs one storage object. The production conformer calls supabase-swift's createSignedURL.
protocol StorageObjectSigning: Sendable {
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL
}

/// Turns a stored URL into the URL to download from. Never fails: a URL it does not sign,
/// or cannot sign, comes back unchanged.
/// The returned URL may carry a token: it is never persisted or logged.
protocol StorageURLResolving: AnyObject, Sendable {
    func resolvedURL(for storedURL: URL) async -> URL
    func reset() async
}

/// A stored public URL of this project, split into bucket and object path. Query and fragment are ignored.
struct StoredObjectReference: Hashable, Sendable {
    let bucket: String
    let path: String

    private static let publicPrefix = "/storage/v1/object/public/"

    /// Nil unless host == expectedHost and the path is /storage/v1/object/public/<bucket>/<path…>
    /// with a non-empty bucket and path.
    static func parse(_ url: URL, expectedHost: String) -> StoredObjectReference? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              host.caseInsensitiveCompare(expectedHost) == .orderedSame else {
            return nil
        }
        let fullPath = components.path
        guard fullPath.hasPrefix(publicPrefix) else { return nil }
        let rest = fullPath.dropFirst(publicPrefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let bucket = String(rest[..<slash])
        let path = String(rest[rest.index(after: slash)...])
        guard !bucket.isEmpty, !path.isEmpty else { return nil }
        return StoredObjectReference(bucket: bucket, path: path)
    }
}
