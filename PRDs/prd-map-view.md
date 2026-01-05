# PRD: Map View for Requests

## Document Information
- **Feature Name**: Map View for Requests
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-ride-requests.md`, `prd-location-autocomplete.md`
- **Estimated Effort**: 1-1.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines a map view feature that displays ride and favor requests geographically. Users can see where requests are located and browse the community's needs visually.

### Why does this matter?
- **Visual discovery**: See requests near you at a glance
- **Route planning**: Visualize pickup/destination for rides
- **Proximity awareness**: Find requests along your commute
- **Engagement**: Maps are intuitive and engaging
- **Decision making**: Easier to decide which requests to help with

### What problem does it solve?
- Hard to visualize where requests are located from text alone
- Can't easily find requests near current location
- No sense of distance/proximity from list view
- Missed opportunities to help on existing routes

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Display requests on map | Pins show request locations |
| Filter by request type | Toggle rides/favors |
| Tap to view details | Bottom sheet shows request info |
| Show user location | Blue dot on map |
| Toggle list/map view | Seamless switching |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| MAP-01 | User | See requests on a map | I understand where they are |
| MAP-02 | User | See my location on the map | I know what's near me |
| MAP-03 | User | Filter by type | I focus on rides or favors |
| MAP-04 | User | Tap a pin for details | I learn more about a request |
| MAP-05 | User | Switch between map and list | I use my preferred view |
| MAP-06 | User | See route for rides | I understand the trip |

---

## 4. Functional Requirements

### 4.1 Map Framework Choice

**Requirement MAP-FR-001**: Use MapKit (Apple Maps) for the map view:

```swift
import MapKit
import SwiftUI
```

**Rationale:**
- Native iOS framework (no additional dependencies)
- Free to use (unlike Google Maps SDK)
- Good performance and familiar UX
- Integrates well with SwiftUI

### 4.2 Map View Models

**Requirement MAP-FR-002**: Define map-related models:

```swift
// Core/Models/MapModels.swift
import MapKit

/// Represents a mappable request (ride or favor)
struct MapRequest: Identifiable {
    let id: UUID
    let type: RequestType
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let request: Any  // Ride or Favor
    
    enum RequestType {
        case ride
        case favor
        
        var pinColor: Color {
            switch self {
            case .ride: return .naarsPrimary
            case .favor: return .naarsAccent
            }
        }
        
        var iconName: String {
            switch self {
            case .ride: return "car.fill"
            case .favor: return "wrench.fill"
            }
        }
    }
}

/// Route between two points (for rides)
struct MapRoute: Identifiable {
    let id = UUID()
    let pickup: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    var polyline: MKPolyline?
}
```

### 4.3 Map Service

**Requirement MAP-FR-003**: Create MapService for geocoding and routing:

```swift
// Core/Services/MapService.swift
import MapKit

final class MapService {
    static let shared = MapService()
    private init() {}
    
    /// Convert address string to coordinates
    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(address)
        
        guard let location = placemarks.first?.location?.coordinate else {
            throw MapError.geocodingFailed
        }
        
        return location
    }
    
    /// Calculate route between two points
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        
        guard let route = response.routes.first else {
            throw MapError.routeNotFound
        }
        
        return route
    }
    
    /// Convert requests to map annotations
    func createMapRequests(rides: [Ride], favors: [Favor]) async -> [MapRequest] {
        var mapRequests: [MapRequest] = []
        
        // Process rides (use pickup location)
        for ride in rides where ride.status == .open {
            if let coordinate = try? await geocode(address: ride.pickup) {
                mapRequests.append(MapRequest(
                    id: ride.id,
                    type: .ride,
                    coordinate: coordinate,
                    title: "\(ride.pickup) â†’ \(ride.destination)",
                    subtitle: ride.date.localizedShortDate,
                    request: ride
                ))
            }
        }
        
        // Process favors
        for favor in favors where favor.status == .open {
            if let coordinate = try? await geocode(address: favor.location) {
                mapRequests.append(MapRequest(
                    id: favor.id,
                    type: .favor,
                    coordinate: coordinate,
                    title: favor.title,
                    subtitle: favor.location,
                    request: favor
                ))
            }
        }
        
        return mapRequests
    }
}

enum MapError: LocalizedError {
    case geocodingFailed
    case routeNotFound
    
    var errorDescription: String? {
        switch self {
        case .geocodingFailed: return "Could not find location"
        case .routeNotFound: return "Could not calculate route"
        }
    }
}
```

### 4.4 Map View

**Requirement MAP-FR-004**: Main map view implementation:

```swift
// Features/Dashboard/Views/RequestMapView.swift
import SwiftUI
import MapKit

struct RequestMapView: View {
    @StateObject private var viewModel = RequestMapViewModel()
    @State private var selectedRequest: MapRequest?
    @State private var showFilters = false
    
    // Seattle center
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
    )
    
    var body: some View {
        ZStack(alignment: .top) {
            // Map
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: viewModel.filteredRequests) { request in
                MapAnnotation(coordinate: request.coordinate) {
                    RequestPin(request: request, isSelected: selectedRequest?.id == request.id) {
                        selectedRequest = request
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            
            // Filter bar
            VStack {
                FilterBar(
                    showRides: $viewModel.showRides,
                    showFavors: $viewModel.showFavors,
                    requestCount: viewModel.filteredRequests.count
                )
                .padding()
                
                Spacer()
            }
            
            // Bottom sheet for selected request
            if let request = selectedRequest {
                VStack {
                    Spacer()
                    RequestPreviewCard(
                        request: request,
                        onClose: { selectedRequest = nil },
                        onViewDetails: { navigateToDetails(request) }
                    )
                }
                .transition(.move(edge: .bottom))
            }
        }
        .task {
            await viewModel.loadRequests()
        }
    }
    
    private func navigateToDetails(_ request: MapRequest) {
        // Navigation handled by parent
    }
}

// MARK: - View Model

@MainActor
final class RequestMapViewModel: ObservableObject {
    @Published var mapRequests: [MapRequest] = []
    @Published var showRides = true
    @Published var showFavors = true
    @Published var isLoading = false
    
    var filteredRequests: [MapRequest] {
        mapRequests.filter { request in
            switch request.type {
            case .ride: return showRides
            case .favor: return showFavors
            }
        }
    }
    
    func loadRequests() async {
        isLoading = true
        
        do {
            let rides = try await RideService.shared.fetchRides(status: .open)
            let favors = try await FavorService.shared.fetchFavors(status: .open)
            
            mapRequests = await MapService.shared.createMapRequests(
                rides: rides,
                favors: favors
            )
        } catch {
            // Handle error
        }
        
        isLoading = false
    }
}
```

### 4.5 Custom Map Pin

**Requirement MAP-FR-005**: Custom pin design:

```swift
// UI/Components/Map/RequestPin.swift
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
                    
                    Image(systemName: request.type.iconName)
                        .font(.system(size: isSelected ? 20 : 16))
                        .foregroundColor(.white)
                }
                .shadow(radius: isSelected ? 4 : 2)
                
                // Pin tail
                Triangle()
                    .fill(request.type.pinColor)
                    .frame(width: 12, height: 8)
                    .offset(y: -2)
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

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
```

### 4.6 Filter Bar

**Requirement MAP-FR-006**: Filter controls:

```swift
// UI/Components/Map/FilterBar.swift
struct FilterBar: View {
    @Binding var showRides: Bool
    @Binding var showFavors: Bool
    let requestCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            FilterChip(
                title: "Rides",
                icon: "car.fill",
                isSelected: showRides,
                color: .naarsPrimary
            ) {
                showRides.toggle()
            }
            
            FilterChip(
                title: "Favors",
                icon: "wrench.fill",
                isSelected: showFavors,
                color: .naarsAccent
            ) {
                showFavors.toggle()
            }
            
            Spacer()
            
            Text("\(requestCount) requests")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
        }
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}
```

### 4.7 Request Preview Card

**Requirement MAP-FR-007**: Bottom sheet preview:

```swift
// UI/Components/Map/RequestPreviewCard.swift
struct RequestPreviewCard: View {
    let request: MapRequest
    let onClose: () -> Void
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Handle bar
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
            
            // Content
            HStack(alignment: .top, spacing: 12) {
                // Type icon
                Circle()
                    .fill(request.type.pinColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: request.type.iconName)
                            .foregroundColor(.white)
                    }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.headline)
                        .lineLimit(2)
                    
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
            
            // View details button
            Button(action: onViewDetails) {
                Text("View Details")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }
}
```

### 4.8 List/Map Toggle

**Requirement MAP-FR-008**: Toggle between views in dashboard:

```swift
// In DashboardView
@State private var viewMode: ViewMode = .list

enum ViewMode {
    case list
    case map
}

var body: some View {
    VStack(spacing: 0) {
        // View mode toggle
        Picker("View", selection: $viewMode) {
            Image(systemName: "list.bullet")
                .tag(ViewMode.list)
            Image(systemName: "map")
                .tag(ViewMode.map)
        }
        .pickerStyle(.segmented)
        .padding()
        
        // Content
        Group {
            switch viewMode {
            case .list:
                RequestListView()
            case .map:
                RequestMapView()
            }
        }
    }
}
```

### 4.9 Wireframe

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Requests                    [+]   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”           â”‚
â”‚   â”‚ â˜° List   â”‚ ðŸ—º Map  â”‚  â† Toggle  â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜           â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â” â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”  12 requestsâ”‚
â”‚   â”‚ðŸš—Rides â”‚ â”‚ðŸ› Favorsâ”‚             â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”˜ â””â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â† Filters  â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚         [Map View]          â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚    ðŸ“        ðŸ“             â”‚   â”‚
â”‚   â”‚        ðŸ“                   â”‚   â”‚
â”‚   â”‚              ðŸ”µ â† You       â”‚   â”‚
â”‚   â”‚    ðŸ“    ðŸ“                 â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ â•â•â•â•                        â”‚   â”‚
â”‚   â”‚ ðŸš— Capitol Hill â†’ SEA       â”‚   â”‚
â”‚   â”‚    Mon, Jan 6               â”‚   â”‚
â”‚   â”‚ â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚   â”‚
â”‚   â”‚ â”‚    View Details       â”‚   â”‚   â”‚
â”‚   â”‚ â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚         â†‘ Selected request card     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## 5. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Turn-by-turn navigation | Use Apple/Google Maps apps |
| Real-time location tracking | Privacy concerns |
| Heat maps | Complexity vs value |
| Clustering pins | Not enough density |
| Offline maps | Storage concerns |

---

## 6. Technical Considerations

### Geocoding Caching

- Cache geocoded coordinates in Supabase
- Only geocode once per unique address
- Fall back to text if geocoding fails

### Performance

- Limit visible pins (50 max)
- Load pins lazily as map moves
- Use background queue for geocoding

### Location Permission

```xml
<!-- Info.plist -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Naar's Cars shows your location on the map to help you find nearby requests.</string>
```

---

## 7. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-ride-requests.md`
- `prd-favor-requests.md`
- `prd-location-autocomplete.md` (for stored coordinates)

### Frameworks
- MapKit (native)
- CoreLocation

---

## 8. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Map displays | Loads within 2s | Visual test |
| Pins show | All open requests appear | Count vs list |
| User location | Blue dot visible | Enable location |
| Tap pin | Preview appears | Tap and verify |
| Filter works | Pins update | Toggle and count |

---

## 9. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Show route preview? | **Future** | Add in v2 |
| Save preferred view? | **Yes** | Remember list/map choice |
| Google Maps option? | **No** | Apple Maps sufficient |

---

*End of PRD: Map View for Requests*
