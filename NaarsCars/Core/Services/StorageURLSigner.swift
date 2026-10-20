//
//  StorageURLSigner.swift
//  NaarsCars
//

import Foundation
import Supabase

/// Turns a stored public URL of a signed bucket into a short-lived signed URL, in memory only.
/// What the database and SwiftData store does not change: they keep the public URL the upload returned.
/// While the buckets are still public, a signing failure falls back to the stored URL.
actor StorageURLSigner: StorageURLResolving {
    static let shared = StorageURLSigner()

    /// The buckets 5b makes private. "audio-messages" joins only through Task 8 (D-1). Avatars are never signed.
    static let signedBuckets: Set<String> = ["message-images", "group-images", "town-hall-images", "review-images"]

    private struct Entry {
        let url: URL
        let expiry: Date
    }

    private let signer: any StorageObjectSigning
    private var expectedHost: String?
    private let now: @Sendable () -> Date
    private let lifetime: Int
    private let renewMargin: TimeInterval
    private let maxEntries: Int

    private var cache: [StoredObjectReference: Entry] = [:]
    private var inFlight: [StoredObjectReference: Task<URL?, Never>] = [:]
    /// Bumped by reset(), so a sign that was in flight across a reset is not cached.
    private var generation = 0

    init(signer: any StorageObjectSigning = SupabaseStorageSigner(),
         expectedHost: String? = nil,
         now: @escaping @Sendable () -> Date = Date.init,
         lifetime: Int = Constants.Storage.signedURLLifetime,
         renewMargin: TimeInterval = Constants.Storage.signedURLRenewMargin,
         maxEntries: Int = Constants.Storage.signedURLCacheMaxEntries) {
        self.signer = signer
        self.expectedHost = expectedHost
        self.now = now
        self.lifetime = lifetime
        self.renewMargin = renewMargin
        self.maxEntries = max(1, maxEntries)
    }

    func resolvedURL(for storedURL: URL) async -> URL {
        let host = await hostToMatch()
        guard let host,
              let reference = StoredObjectReference.parse(storedURL, expectedHost: host),
              Self.signedBuckets.contains(reference.bucket) else {
            return storedURL
        }

        if let entry = cache[reference], now() < entry.expiry.addingTimeInterval(-renewMargin) {
            return entry.url
        }

        if let pending = inFlight[reference] {
            return await pending.value ?? storedURL
        }

        let signer = self.signer
        let lifetime = self.lifetime
        let issuedAt = now()
        let task = Task<URL?, Never> {
            do {
                return try await signer.signedURL(bucket: reference.bucket, path: reference.path, expiresIn: lifetime)
            } catch {
                // Bucket, domain and code only: never the URL, the path or the error text.
                let ns = error as NSError
                AppLogger.warning("images", "Signing failed for \(reference.bucket): \(ns.domain) \(ns.code)")
                return nil
            }
        }
        inFlight[reference] = task
        let generationAtStart = generation

        let signed = await task.value

        if generation == generationAtStart {
            inFlight[reference] = nil
            if let signed {
                store(Entry(url: signed, expiry: issuedAt.addingTimeInterval(TimeInterval(lifetime))), for: reference)
            }
        }
        return signed ?? storedURL
    }

    func reset() {
        cache.removeAll()
        inFlight.removeAll()
        generation += 1
    }

    // MARK: - Private

    private func store(_ entry: Entry, for reference: StoredObjectReference) {
        if cache[reference] == nil, cache.count >= maxEntries,
           let earliest = cache.min(by: { $0.value.expiry < $1.value.expiry })?.key {
            cache[earliest] = nil
        }
        cache[reference] = entry
    }

    /// The project's storage host, read once from the Supabase client (the host getPublicURL wrote into stored URLs).
    private func hostToMatch() async -> String? {
        if let expectedHost { return expectedHost }
        let host = await MainActor.run { SupabaseService.shared.client.storage.configuration.url.host }
        expectedHost = host
        return host
    }
}

/// Signs through the app's Supabase client (the caller's own access applies).
struct SupabaseStorageSigner: StorageObjectSigning {
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        let client = await MainActor.run { SupabaseService.shared.client }
        return try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: expiresIn)
    }
}

extension URLSession {
    /// The only session that downloads a stored object of a signed bucket. Ephemeral, urlCache = nil,
    /// requestCachePolicy = .reloadIgnoringLocalCacheData: a signed URL (and its token) never reaches URLCache's disk store.
    static let signedStorageDownload: URLSession = makeSignedStorageDownloadSession()

    /// protocolClasses is for tests only (a custom session does not reliably pick up URLProtocol.registerClass).
    static func makeSignedStorageDownloadSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        return URLSession(configuration: configuration)
    }
}
