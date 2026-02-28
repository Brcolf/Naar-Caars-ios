//
//  CurrentLocationProvider.swift
//  NaarsCars
//
//  One-shot current location with timeout; supports stop() for lifecycle cleanup.
//

import Foundation
import CoreLocation

/// Lightweight one-shot location provider for "When In Use" permission and a single location fix.
/// Call `stop()` from onDisappear (or when cancelling) to avoid completion firing after view is gone.
final class CurrentLocationProvider: NSObject, @unchecked Sendable {

    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private let lock = NSLock()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Request current location; completion is called exactly once with a coordinate or nil (timeout/denied/error/stopped).
    /// Call from main thread. Does not block UI.
    func requestCurrentLocation(timeout: TimeInterval, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        lock.lock()
        guard self.completion == nil else {
            lock.unlock()
            completion(nil)
            return
        }
        self.completion = completion
        lock.unlock()

        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            finish(with: nil)
            return
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.requestLocation()

        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(with: nil)
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    /// Cancel the request and call completion with nil if not yet completed. Call from onDisappear so the awaiting caller can resume and exit.
    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
        finish(with: nil)
    }

    /// Call completion at most once and clean up.
    private func finish(with coordinate: CLLocationCoordinate2D?) {
        lock.lock()
        let block = completion
        completion = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        lock.unlock()
        manager.stopUpdatingLocation()
        if let block = block {
            DispatchQueue.main.async { block(coordinate) }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension CurrentLocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        finish(with: coord)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            finish(with: nil)
            return
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
}
