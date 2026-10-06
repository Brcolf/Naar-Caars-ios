//
//  MapSnapshotCache.swift
//  NaarsCars
//
//  Cache for map snapshot images used in location messages
//

import SwiftUI
import MapKit

final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private let cache: NSCache<NSString, UIImage>
    
    private init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50           // Max 50 snapshots
        cache.totalCostLimit = 20 * 1024 * 1024  // ~20MB
    }
    
    /// - Parameter style: the appearance to render the map in. Part of the cache key: a
    ///   snapshot is a bitmap, so one taken in light mode stayed light after a switch to dark
    ///   (and the reverse) until the cache was evicted.
    func snapshot(for coordinate: CLLocationCoordinate2D, style: UIUserInterfaceStyle = .unspecified) async -> UIImage? {
        let key = "\(coordinate.latitude),\(coordinate.longitude),\(style.rawValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        if style != .unspecified {
            options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        }
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 200, height: 120)
        options.scale = UITraitCollection.current.displayScale
        options.mapType = .standard
        
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            cache.setObject(snapshot.image, forKey: key)
            return snapshot.image
        } catch {
            return nil
        }
    }
}
