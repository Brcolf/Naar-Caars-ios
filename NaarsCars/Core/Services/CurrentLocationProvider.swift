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
    /// The timeout of a request that is waiting for the person to answer the system location
    /// prompt. Non-nil only between asking for permission and the answer.
    private var timeoutAwaitingAuthorization: TimeInterval?
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
            // First use: the system prompt is about to appear. The timeout starts when the
            // person answers it (`locationManagerDidChangeAuthorization`). Started here, it
            // ran out two seconds later with the prompt still on screen, and Maps opened over
            // the unanswered question without the location being used.
            lock.lock()
            timeoutAwaitingAuthorization = timeout
            lock.unlock()
            manager.requestWhenInUseAuthorization()
            return
        }
        startLocationRequest(timeout: timeout)
    }

    /// Ask for one fix and arm the timeout. Called once permission is known to be granted.
    private func startLocationRequest(timeout: TimeInterval) {
        manager.requestLocation()

        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(with: nil)
        }
        lock.lock()
        timeoutWorkItem = workItem
        lock.unlock()
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
        timeoutAwaitingAuthorization = nil
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
            // Only a request that was waiting for this answer starts here. This callback also
            // fires when the manager is created, and a request made with permission already
            // granted starts itself in `requestCurrentLocation`.
            lock.lock()
            let pendingTimeout = timeoutAwaitingAuthorization
            timeoutAwaitingAuthorization = nil
            lock.unlock()
            if let pendingTimeout = pendingTimeout {
                startLocationRequest(timeout: pendingTimeout)
            }
        }
    }
}
