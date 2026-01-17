//
//  MKPolyline+Extensions.swift
//  NaarsCars
//
//  Extension to extract coordinates from MKPolyline
//

import MapKit

extension MKPolyline {
    /// Extract coordinates array from MKPolyline
    var coordinates: [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let pointer = UnsafeMutablePointer<CLLocationCoordinate2D>.allocate(capacity: pointCount)
        getCoordinates(pointer, range: NSRange(location: 0, length: pointCount))
        for i in 0..<pointCount {
            coords.append(pointer[i])
        }
        pointer.deallocate()
        return coords
    }
}

