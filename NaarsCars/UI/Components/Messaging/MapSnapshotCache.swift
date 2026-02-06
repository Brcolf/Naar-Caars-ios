//
//  MapSnapshotCache.swift
//  NaarsCars
//
//  Cache for map snapshot images used in location messages
//

import SwiftUI
import MapKit

@MainActor
final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {}
    
    func snapshot(for coordinate: CLLocationCoordinate2D) async -> UIImage? {
        let key = "\(coordinate.latitude),\(coordinate.longitude)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 200, height: 120)
        options.scale = UIScreen.main.scale
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
