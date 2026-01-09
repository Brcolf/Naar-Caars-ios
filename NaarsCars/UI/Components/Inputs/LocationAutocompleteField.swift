//
//  LocationAutocompleteField.swift
//  NaarsCars
//
//  Reusable location autocomplete field using Google Places API
//

import SwiftUI
import CoreLocation

/// Reusable location autocomplete field with dropdown suggestions
struct LocationAutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var onSelect: ((PlaceDetails) -> Void)?
    
    @State private var predictions: [PlacePrediction] = []
    @State private var isSearching = false
    @State private var showDropdown = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    
    private let locationService = LocationService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Input field
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        performSearch(query: newValue)
                    }
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !text.isEmpty {
                    Button {
                        clearField()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            
            // Dropdown suggestions
            if showDropdown && isFocused {
                VStack(spacing: 0) {
                    // Recent locations (shown when field is empty)
                    if text.isEmpty && !locationService.recentLocations.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Recent")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            
                            ForEach(locationService.recentLocations) { location in
                                RecentLocationRow(location: location) {
                                    selectRecent(location)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // Search predictions
                    if !predictions.isEmpty {
                        if !text.isEmpty {
                            Text("Suggestions")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        
                        ForEach(predictions) { prediction in
                            PredictionRow(prediction: prediction) {
                                Task {
                                    await selectPrediction(prediction)
                                }
                            }
                        }
                    } else if !text.isEmpty && !isSearching && text.count >= 2 {
                        Text("No results found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }
        }
        .onChange(of: isFocused) { _, focused in
            showDropdown = focused && (!text.isEmpty || !locationService.recentLocations.isEmpty)
        }
    }
    
    // MARK: - Private Methods
    
    private func performSearch(query: String) {
        // Cancel previous search task
        searchTask?.cancel()
        
        guard !query.isEmpty, query.count >= 2 else {
            predictions = []
            showDropdown = false
            return
        }
        
        // Debounce search (300ms)
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard !Task.isCancelled else { return }
            
            isSearching = true
            showDropdown = true
            
            do {
                let results = try await locationService.searchPlaces(query: query)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    predictions = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    predictions = []
                    isSearching = false
                    print("⚠️ [LocationAutocompleteField] Search error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func selectPrediction(_ prediction: PlacePrediction) async {
        do {
            let details = try await locationService.getPlaceDetails(placeID: prediction.placeID)
            
            await MainActor.run {
                // Update text field with selected location
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
                
                // Call completion handler
                onSelect?(details)
                
                // Clear predictions and dismiss keyboard
                predictions = []
                isFocused = false
                showDropdown = false
            }
        } catch {
            await MainActor.run {
                // Fallback to prediction text
                text = prediction.primaryText
                predictions = []
                isFocused = false
                showDropdown = false
                print("⚠️ [LocationAutocompleteField] Failed to get place details: \(error.localizedDescription)")
            }
        }
    }
    
    private func selectRecent(_ location: SavedLocation) {
        text = location.name.isEmpty ? location.address : location.name
        isFocused = false
        showDropdown = false
        
        // Convert SavedLocation to PlaceDetails for onSelect callback
        let details = PlaceDetails(
            placeID: location.placeID,
            name: location.name,
            address: location.address,
            coordinate: location.coordinate
        )
        onSelect?(details)
    }
    
    private func clearField() {
        text = ""
        predictions = []
        searchTask?.cancel()
        isSearching = false
        showDropdown = false
    }
}

// MARK: - Supporting Views

/// Row for displaying a place prediction suggestion
struct PredictionRow: View {
    let prediction: PlacePrediction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 18))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(prediction.primaryText)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if !prediction.secondaryText.isEmpty {
                        Text(prediction.secondaryText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Row for displaying a recent location
struct RecentLocationRow: View {
    let location: SavedLocation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name.isEmpty ? location.address : location.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if !location.name.isEmpty {
                        Text(location.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        LocationAutocompleteField(
            label: "Pickup Location",
            placeholder: "Where should they pick you up?",
            text: .constant(""),
            icon: "location.circle.fill"
        )
        
        LocationAutocompleteField(
            label: "Destination",
            placeholder: "Where are you going?",
            text: .constant("Capitol"),
            icon: "mappin.circle.fill"
        )
    }
    .padding()
}

