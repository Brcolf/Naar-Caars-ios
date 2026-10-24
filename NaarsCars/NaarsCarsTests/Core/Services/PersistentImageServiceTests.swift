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
        // 400x300 for a 100-pixel target: the short side is 100, the long side 134 (aspect kept).
        XCTAssertGreaterThanOrEqual(min(cgImage.width, cgImage.height), 100)
        XCTAssertLessThanOrEqual(cgImage.width, 134)
        XCTAssertLessThan(cgImage.width, 400, "downsampled")

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

    // MARK: - Display-sized decode: the short side is the shown size

    /// A PNG of `width` x `height` pixels (scale 1).
    private static func pngData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Serves `data` for every download, under a stored URL of its own so the disk cache of one
    /// source never answers for another.
    private func serve(_ data: Data, as fileName: String) -> String {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/png"])!
            return (response, data)
        }
        return "https://example.supabase.co/storage/v1/object/public/town-hall-images/C0/\(fileName)"
    }

    private func decodedPixels(_ urlString: String, target: CGFloat) async throws -> (width: Int, height: Int) {
        let loaded = await service.getImage(for: urlString, maxPixelSize: target)
        let cgImage = try XCTUnwrap(loaded?.cgImage)
        return (cgImage.width, cgImage.height)
    }

    /// A tall screenshot shown at the card's width: the width is decoded at the target, not the
    /// long side (a long-side cap decoded 945x2048 at 664x1440 for a 987-pixel card).
    func testGetImage_PortraitFitWidthTarget_DecodesAtLeastTheTargetWide() async throws {
        let url = serve(Self.pngData(width: 150, height: 400), as: "portrait.png")

        let narrow = try await decodedPixels(url, target: 100)
        XCTAssertGreaterThanOrEqual(narrow.width, 100, "the view would stretch a narrower bitmap")
        XCTAssertLessThan(narrow.width, 150, "still downsampled")
        XCTAssertLessThanOrEqual(narrow.height, 400, "the long side never passes the source's")

        let wider = try await decodedPixels(url, target: 120)
        XCTAssertGreaterThanOrEqual(wider.width, 120)
        XCTAssertLessThanOrEqual(wider.height, 400)
        try await waitForCachedFile(named: "portrait.png")
    }

    /// A target above the source's short side gets the source's own size: ImageIO never upscales,
    /// and the long side asked for is capped at the source's.
    func testGetImage_SourceSmallerThanTarget_ReturnsTheSourceSize() async throws {
        let url = serve(Self.pngData(width: 150, height: 400), as: "small-portrait.png")
        let decoded = try await decodedPixels(url, target: 300)
        XCTAssertEqual(decoded.width, 150)
        XCTAssertEqual(decoded.height, 400)

        let tinyURL = serve(Self.pngData(width: 40, height: 30), as: "tiny.png")
        let tiny = try await decodedPixels(tinyURL, target: 100)
        XCTAssertEqual(tiny.width, 40)
        XCTAssertEqual(tiny.height, 30)
        try await waitForCachedFile(named: "small-portrait.png")
        try await waitForCachedFile(named: "tiny.png")
    }

    /// An avatar fills its circle (aspect fill), so the short side covers the circle in either
    /// orientation (a long-side cap gave a 3:4 avatar a short side of 90 for a 120-pixel circle).
    func testGetImage_AvatarFillTarget_ShortSideCoversTheCircle() async throws {
        let portraitURL = serve(Self.pngData(width: 300, height: 400), as: "avatar-portrait.png")
        let portrait = try await decodedPixels(portraitURL, target: 120)
        XCTAssertGreaterThanOrEqual(min(portrait.width, portrait.height), 120)
        XCTAssertLessThan(portrait.width, 300, "still downsampled")

        let landscapeURL = serve(Self.pngData(width: 400, height: 300), as: "avatar-landscape.png")
        let landscape = try await decodedPixels(landscapeURL, target: 120)
        XCTAssertGreaterThanOrEqual(min(landscape.width, landscape.height), 120)
        XCTAssertLessThan(landscape.width, 400, "still downsampled")
        try await waitForCachedFile(named: "avatar-portrait.png")
        try await waitForCachedFile(named: "avatar-landscape.png")
    }

    func testGetImage_ResolvedDownloadLeavesNoURLCacheEntry() async throws {
        _ = await service.getImage(for: storedString)
        let signedURL = await resolver.resolvedURL(for: URL(string: storedString)!)
        XCTAssertNil(URLCache.shared.cachedResponse(for: URLRequest(url: signedURL)))
        XCTAssertNil(service.downloadSession.configuration.urlCache)
        try await waitForCachedFile(named: "A1.jpg")   // let the detached write land before tearDown clears
    }

    /// A Town Hall card inserted while its tab is off screen appears and disappears at once, which
    /// cancels its load before the download (the 5b gate's G1: -999 once per frame). That load must
    /// not count as a failure, or the card shows the error view and starts the next load.
    func testGetImage_FromACancelledTask_IsNotAFailure() async throws {
        let urlString = serve(Self.pngData(width: 1, height: 1), as: "cancelled-load.png")
        let outcome = await Task { () -> CachedImageLoadOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            let image = await service.getImage(for: urlString, maxPixelSize: 100)
            return CachedImageLoadOutcome(gotImage: image != nil, cancelled: Task.isCancelled)
        }.value
        XCTAssertNotEqual(outcome, .failed)
        if outcome == .show {
            try await waitForCachedFile(named: "cancelled-load.png")
        }
    }
}

/// The state rule `CachedAsyncImage` applies when a load returns.
final class CachedImageLoadOutcomeTests: XCTestCase {
    func testCancelledWithoutAnImage_ChangesNothing() {
        XCTAssertEqual(CachedImageLoadOutcome(gotImage: false, cancelled: true), .unchanged)
    }

    func testFinishedWithoutAnImage_IsAFailure() {
        XCTAssertEqual(CachedImageLoadOutcome(gotImage: false, cancelled: false), .failed)
    }

    func testAnImageIsShownEvenWhenTheLoadWasCancelled() {
        XCTAssertEqual(CachedImageLoadOutcome(gotImage: true, cancelled: false), .show)
        XCTAssertEqual(CachedImageLoadOutcome(gotImage: true, cancelled: true), .show)
    }
}
