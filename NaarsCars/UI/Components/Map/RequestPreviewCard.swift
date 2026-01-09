//
//  RequestPreviewCard.swift
//  NaarsCars
//
//  Bottom sheet preview card for selected map request
//

import SwiftUI
import CoreLocation

/// Bottom sheet preview card shown when tapping a map pin
struct RequestPreviewCard: View {
    let request: MapRequest
    let onClose: () -> Void
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Handle bar for dragging
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            
            // Content
            HStack(alignment: .top, spacing: 12) {
                // Type icon
                Circle()
                    .fill(request.type.pinColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: request.type.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(request.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // View details button
            Button(action: onViewDetails) {
                Text("View Details")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -4)
    }
}

// MARK: - View Extension for Rounded Corners

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        
        VStack {
            Spacer()
            
            RequestPreviewCard(
                request: MapRequest(
                    id: UUID(),
                    type: .ride,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                    title: "Capitol Hill → Seattle-Tacoma Airport",
                    subtitle: "Mon, Jan 6"
                ),
                onClose: {
                    print("Close tapped")
                },
                onViewDetails: {
                    print("View details tapped")
                }
            )
        }
    }
}

