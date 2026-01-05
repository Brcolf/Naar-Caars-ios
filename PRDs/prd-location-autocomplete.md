# PRD: Location Autocomplete

## Document Information
- **Feature Name**: Location Autocomplete
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-ride-requests.md`, `prd-favor-requests.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines location autocomplete functionality for the Naar's Cars iOS app using Google Places API. Location autocomplete helps users quickly and accurately enter pickup/destination addresses.

### Why does this matter?
- **Accuracy**: Prevents typos and incorrect addresses
- **Speed**: Faster than typing full addresses
- **Consistency**: Standardized address formats
- **User experience**: Familiar pattern from ride-sharing apps

### What problem does it solve?
- Typos in manually entered addresses
- Ambiguous location names
- User frustration with long address entry

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Autocomplete for addresses | Suggestions appear while typing |
| Seattle-area bias | Local results prioritized |
| Recent locations | Show user's recent picks |
| Fallback to manual | Can still type custom text |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| LOC-01 | User | See suggestions as I type | I can quickly find my address |
| LOC-02 | User | Select from recent locations | I don't retype common places |
| LOC-03 | User | See Seattle results first | Local results are more relevant |
| LOC-04 | User | Enter custom text | I can use landmarks or descriptions |

---

## 4. Functional Requirements

### 4.1 Google Places Setup

**Requirement LOCA-FR-001**: Add Google Places SDK via SPM or CocoaPods.

**Requirement LOCA-FR-002**: Configure API key in app initialization:

```swift
import GooglePlaces

// In App init or AppDelegate
GMSPlacesClient.provideAPIKey(Secrets.googlePlacesAPIKey)
```

### 4.2 Location Service

**Requirement LOCA-FR-003**: LocationService for place search:

```swift
// Core/Services/LocationService.swift
import Foundation
import GooglePlaces

final class LocationService: ObservableObject {
    static let shared = LocationService()
    
    private let placesClient = GMSPlacesClient.shared()
    
    @Published var recentLocations: [SavedLocation] = []
    
    // Seattle bounds for biasing results
    private let seattleBounds = GMSCoordinateBounds(
        coordinate: CLLocationCoordinate2D(latitude: 47.4, longitude: -122.5),
        coordinate: CLLocationCoordinate2D(latitude: 47.8, longitude: -122.1)
    )
    
    private init() {
        loadRecentLocations()
    }
    
    /// Search for place predictions
    func searchPlaces(query: String) async throws -> [PlacePrediction] {
        guard !query.isEmpty else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            let filter = GMSAutocompleteFilter()
            filter.types = ["address", "establishment", "geocode"]
            filter.locationBias = GMSPlaceRectangularLocationOption(seattleBounds)
            
            placesClient.findAutocompletePredictions(
                fromQuery: query,
                filter: filter,
                sessionToken: nil
            ) { results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let predictions = (results ?? []).map { prediction in
                    PlacePrediction(
                        placeID: prediction.placeID,
                        primaryText: prediction.attributedPrimaryText.string,
                        secondaryText: prediction.attributedSecondaryText?.string ?? "",
                        fullText: prediction.attributedFullText.string
                    )
                }
                
                continuation.resume(returning: predictions)
            }
        }
    }
    
    /// Get full place details
    func getPlaceDetails(placeID: String) async throws -> PlaceDetails {
        return try await withCheckedThrowingContinuation { continuation in
            let fields: GMSPlaceField = [.name, .formattedAddress, .coordinate]
            
            placesClient.fetchPlace(
                fromPlaceID: placeID,
                placeFields: fields,
                sessionToken: nil
            ) { place, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let place = place else {
                    continuation.resume(throwing: LocationError.notFound)
                    return
                }
                
                let details = PlaceDetails(
                    placeID: placeID,
                    name: place.name ?? "",
                    address: place.formattedAddress ?? "",
                    coordinate: place.coordinate
                )
                
                continuation.resume(returning: details)
            }
        }
    }
    
    /// Save location to recents
    func saveRecentLocation(_ location: SavedLocation) {
        recentLocations.removeAll { $0.placeID == location.placeID }
        recentLocations.insert(location, at: 0)
        if recentLocations.count > 10 {
            recentLocations = Array(recentLocations.prefix(10))
        }
        persistRecentLocations()
    }
    
    private func loadRecentLocations() {
        guard let data = UserDefaults.standard.data(forKey: "recent_locations"),
              let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return
        }
        recentLocations = locations
    }
    
    private func persistRecentLocations() {
        guard let data = try? JSONEncoder().encode(recentLocations) else { return }
        UserDefaults.standard.set(data, forKey: "recent_locations")
    }
}

// MARK: - Models

struct PlacePrediction: Identifiable {
    let placeID: String
    let primaryText: String
    let secondaryText: String
    let fullText: String
    
    var id: String { placeID }
}

struct PlaceDetails {
    let placeID: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

struct SavedLocation: Codable, Identifiable {
    let placeID: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    
    var id: String { placeID }
}

enum LocationError: LocalizedError {
    case notFound
    var errorDescription: String? { "Location not found" }
}
```

### 4.3 Autocomplete UI Component

**Requirement LOCA-FR-004**: Reusable autocomplete field:

```swift
// UI/Components/Inputs/LocationAutocompleteField.swift
import SwiftUI

struct LocationAutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var onSelect: ((PlaceDetails) -> Void)?
    
    @State private var predictions: [PlacePrediction] = []
    @State private var isSearching = false
    @State private var showDropdown = false
    @FocusState private var isFocused: Bool
    
    private let locationService = LocationService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Input
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        Task { await search(query: newValue) }
                    }
                
                if isSearching {
                    ProgressView().scaleEffect(0.8)
                } else if !text.isEmpty {
                    Button { clearField() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            
            // Dropdown
            if showDropdown && isFocused {
                VStack(spacing: 0) {
                    // Recent locations
                    if text.isEmpty && !locationService.recentLocations.isEmpty {
                        Section {
                            ForEach(locationService.recentLocations) { location in
                                RecentLocationRow(location: location) {
                                    selectRecent(location)
                                }
                            }
                        } header: {
                            SectionHeader(title: "Recent")
                        }
                    }
                    
                    // Search predictions
                    if !predictions.isEmpty {
                        ForEach(predictions) { prediction in
                            PredictionRow(prediction: prediction) {
                                Task { await selectPrediction(prediction) }
                            }
                            Divider()
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 4)
            }
        }
        .onChange(of: isFocused) { _, focused in
            showDropdown = focused
        }
    }
    
    private func search(query: String) async {
        guard query.count >= 2 else {
            predictions = []
            return
        }
        
        isSearching = true
        do {
            predictions = try await locationService.searchPlaces(query: query)
        } catch {
            predictions = []
        }
        isSearching = false
    }
    
    private func selectPrediction(_ prediction: PlacePrediction) async {
        do {
            let details = try await locationService.getPlaceDetails(placeID: prediction.placeID)
            text = details.name.isEmpty ? details.address : details.name
            
            // Save to recents
            let saved = SavedLocation(
                placeID: details.placeID,
                name: details.name,
                address: details.address,
                latitude: details.coordinate.latitude,
                longitude: details.coordinate.longitude
            )
            locationService.saveRecentLocation(saved)
            
            onSelect?(details)
            isFocused = false
        } catch {
            // Use prediction text as fallback
            text = prediction.primaryText
            isFocused = false
        }
    }
    
    private func selectRecent(_ location: SavedLocation) {
        text = location.name.isEmpty ? location.address : location.name
        isFocused = false
    }
    
    private func clearField() {
        text = ""
        predictions = []
    }
}

struct PredictionRow: View {
    let prediction: PlacePrediction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "mappin.circle")
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(prediction.primaryText)
                        .foregroundColor(.primary)
                    Text(prediction.secondaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
    }
}

struct RecentLocationRow: View {
    let location: SavedLocation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading) {
                    Text(location.name.isEmpty ? location.address : location.name)
                        .foregroundColor(.primary)
                    if !location.name.isEmpty {
                        Text(location.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
    }
}
```

### 4.4 Integration in Ride/Favor Forms

**Requirement LOCA-FR-005**: Update ride creation form:

```swift
// In CreateRideView
LocationAutocompleteField(
    label: "Pickup Location",
    placeholder: "Where should they pick you up?",
    text: $viewModel.pickup,
    icon: "location.circle"
) { details in
    viewModel.pickupCoordinate = details.coordinate
}

LocationAutocompleteField(
    label: "Destination",
    placeholder: "Where are you going?",
    text: $viewModel.destination,
    icon: "mappin.circle"
) { details in
    viewModel.destinationCoordinate = details.coordinate
}
```

### 4.5 Wireframe

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Pickup Location                   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ RECENT                      â”‚   â”‚
â”‚   â”‚ ðŸ• Seattle-Tacoma Airport   â”‚   â”‚
â”‚   â”‚    SEA, SeaTac, WA          â”‚   â”‚
â”‚   â”‚ ðŸ• University of Washington â”‚   â”‚
â”‚   â”‚    Seattle, WA              â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill             â”‚   â”‚
â”‚   â”‚    Seattle, WA              â”‚   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill Station     â”‚   â”‚
â”‚   â”‚    Seattle, WA              â”‚   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill Light Rail  â”‚   â”‚
â”‚   â”‚    Seattle, WA              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Destination                       â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸŽ¯ Where are you going?     â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## 5. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Full address validation | Autocomplete is sufficient |
| Geocoding without Google | Use Google for consistency |
| Offline autocomplete | Requires too much data |
| International locations | Seattle-focused app |

---

## 6. Technical Considerations

### API Costs

Google Places API pricing (as of 2024):
- Autocomplete: $2.83 per 1000 requests
- Place Details: $17 per 1000 requests

**Optimization strategies:**
- Debounce search (300ms delay)
- Minimum 2 characters before search
- Cache recent locations locally
- Use session tokens to reduce costs

### Info.plist

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Naar's Cars uses your location to suggest nearby places.</string>
```

---

## 7. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-ride-requests.md`
- `prd-favor-requests.md`

### External Dependencies
- Google Places SDK for iOS
- Google Places API key

---

## 8. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Suggestions appear | Within 500ms | Type and measure |
| Seattle bias works | Local results first | Search "Airport" |
| Recent locations | Persists across sessions | Use location, relaunch |
| Selection works | Text populated | Select prediction |

---

## 9. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Store coordinates in DB? | **Optional** | Could enable future map features |
| Apple Maps instead? | **No** | Google Places has better data |
| Current location button? | **Future** | Add in later iteration |

---

*End of PRD: Location Autocomplete*
