//
//  RequestPin.swift
//  NaarsCars
//
//  Custom map pin for displaying ride and favor requests
//

import SwiftUI
import MapKit

/// Custom map pin for requests
struct RequestPin: View {
    let request: MapRequest
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Pin head
                ZStack {
                    Circle()
                        .fill(request.type.pinColor)
                        .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                        .shadow(color: .black.opacity(0.3), radius: isSelected ? 4 : 2, x: 0, y: 2)
                    
                    Image(systemName: request.type.iconName)
                        .font(.system(size: isSelected ? 20 : 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Pin tail (triangle)
                Triangle()
                    .fill(request.type.pinColor)
                    .frame(width: 12, height: 8)
                    .offset(y: -2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

/// Triangle shape for pin tail
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
        
        HStack(spacing: 40) {
            RequestPin(
                request: MapRequest(
                    id: UUID(),
                    type: .ride,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                    title: "Ride Request",
                    subtitle: "Jan 5"
                ),
                isSelected: false
            ) {
                AppLogger.info("map", "Tapped ride pin")
            }
            
            RequestPin(
                request: MapRequest(
                    id: UUID(),
                    type: .favor,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                    title: "Favor Request",
                    subtitle: "Capitol Hill"
                ),
                isSelected: true
            ) {
                AppLogger.info("map", "Tapped favor pin")
            }
        }
    }
    .padding()
}


