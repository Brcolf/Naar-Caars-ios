//
//  PersistentImageServiceTests.swift
//  NaarsCarsTests
//
//  The image cache downloads from the resolved (signed) URL, keys its disk cache on the
//  stored URL's file name, and leaves nothing in URLCache.
//

import XCTest
import UIKit
@testable import NaarsCars

/// Returns `<stored>?token=t` and counts calls.
final class StubStorageURLResolver: StorageURLResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedCount
    }

    func resolvedURL(for storedURL: URL) async -> URL {
        lock.lock(); storedCount += 1; lock.unlock()
        var components = URLComponents(url: storedURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: "t")]
        return components.url!
    }

    func reset() async {}
}

final class PersistentImageServiceTests: XCTestCase {
    private var service: PersistentImageService { PersistentImageService.shared }
    private var resolver: StubStorageURLResolver!
    private let storedString = "https://example.supabase.co/storage/v1/object/public/message-images/C0/A1.jpg"

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PersistentImageCache", isDirectory: true)
    }

    private static let pngData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()

    /// 400x300 pixels (scale 1), larger than the display-sized request below.
    private static let largePNGData: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format)
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
    }()

    override func setUp() {
        super.setUp()
        service.clearCache()
        CommunityServiceURLProtocol.reset()
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/png"])!
            return (response, PersistentImageServiceTests.pngData)
        }
        resolver = StubStorageURLResolver()
        service.urlResolver = resolver
        service.downloadSession = URLSession.makeSignedStorageDownloadSession(protocolClasses: [CommunityServiceURLProtocol.self])
    }

    override func tearDown() {
        service.urlResolver = StorageURLSigner.shared
        service.downloadSession = .signedStorageDownload
        CommunityServiceURLProtocol.reset()
        service.clearCache()
        resolver = nil
        super.tearDown()
    }

    /// The disk write is a detached task; poll for the file every 20 ms for up to 2 s.
    private func waitForCachedFile(named name: String) async throws {
        let path = cacheDirectory.appendingPathComponent(name).path
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: path) {
            if Date() > deadline {
                XCTFail("\(name) never reached the disk cache")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testGetImage_DownloadsFromTheResolvedURL() async throws {
        let image = await service.getImage(for: storedString)
        XCTAssertNotNil(image)
        let request = try XCTUnwrap(CommunityServiceURLProtocol.recorded.last)
        XCTAssertEqual(request.query["token"], "t")
        XCTAssertTrue(request.path.hasSuffix("/message-images/C0/A1.jpg"))
        XCTAssertEqual(resolver.callCount, 1)
        try await waitForCachedFile(named: "A1.jpg")   // let the detached write land before tearDown clears
    }

    func testGetImage_CachesUnderTheStoredNameNotTheSignedOne() async throws {
        _ = await service.getImage(for: storedString)
        try await waitForCachedFile(named: "A1.jpg")
        let names = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        XCTAssertTrue(names.contains("A1.jpg"))
        XCTAssertFalse(names.contains { $0.contains("token") }, "\(names)")
    }

    func testGetImage_DiskHitDoesNotResolve() async throws {
        _ = await service.getImage(for: storedString)
        try await waitForCachedFile(named: "A1.jpg")
        let requestsAfterFirst = CommunityServiceURLProtocol.recorded.count

        let second = await service.getImage(for: storedString)
        XCTAssertNotNil(second)
        XCTAssertEqual(resolver.callCount, 1)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, requestsAfterFirst)
    }

    func testGetImage_DisplaySizedRequestIsDownsampledAndReused() async throws {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/png"])!
            return (response, PersistentImageServiceTests.largePNGData)
        }
        let firstImage = await service.getImage(for: storedString, maxPixelSize: 100)
        let first = try XCTUnwrap(firstImage)
        let cgImage = try XCTUnwrap(first.cgImage)
        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 100)
        XCTAssertEqual(cgImage.width, 100)   // 400x300 -> 100x75, aspect kept

        try await waitForCachedFile(named: "A1.jpg")
        let requestsAfterFirst = CommunityServiceURLProtocol.recorded.count
        let second = await service.getImage(for: storedString, maxPixelSize: 100)
        XCTAssertTrue(first === second, "the same URL and size should come from the memory cache")
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, requestsAfterFirst)

        // The full-size path is unchanged: a new, full-size image from the disk cache.
        let full = await service.getImage(for: storedString)
        XCTAssertEqual(full?.cgImage?.width, 400)
        XCTAssertFalse(full === first)
    }

    func testGetImage_ResolvedDownloadLeavesNoURLCacheEntry() async throws {
        _ = await service.getImage(for: storedString)
        let signedURL = await resolver.resolvedURL(for: URL(string: storedString)!)
        XCTAssertNil(URLCache.shared.cachedResponse(for: URLRequest(url: signedURL)))
        XCTAssertNil(service.downloadSession.configuration.urlCache)
        try await waitForCachedFile(named: "A1.jpg")   // let the detached write land before tearDown clears
    }
}
