//
//  LocationAutocompleteField.swift
//  NaarsCars
//
//  Reusable location autocomplete field using MapKit (MKLocalSearchCompleter).
//
//  PERFORMANCE / INSTRUMENTS (DEBUG):
//  - Reproduce stall: Open Create Ride → tap into "Pickup location" field → observe delay.
//  - Time Profiler: Product → Profile → Time Profiler → record → reproduce tap → stop.
//    Inspect main thread; look for gaps between "focus gained" and next work.
//  - Main Thread Checker: Edit Scheme → Run → Diagnostics → Main Thread Checker.
//  - Console: filter by "[LocationPerf]" for signpost/timing; check for "main thread blocked >500ms".
//

import SwiftUI
import CoreLocation
import os

#if DEBUG
private let _locationPerfLog = OSLog(subsystem: "com.naarscars.location", category: "LocationPerf")

private func _locationFieldPerfLog(_ phase: String, mainThread: Bool = Thread.isMainThread) {
    let t = CFAbsoluteTimeGetCurrent()
    print(String(format: "[LocationPerf] %.3f main=%@ %@", t, mainThread ? "Y" : "N", phase))
}
#endif

/// Reusable location autocomplete field with dropdown suggestions
struct LocationAutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var accessibilityId: String? = nil
    /// VoiceOver hint for the text field only. A label or hint set on the whole component from
    /// outside lands on the clear button and on every suggestion as well, so they all read
    /// "Pickup Location".
    var accessibilityHintText: String? = nil
    var onSelect: ((PlaceDetails) -> Void)?
    
    @State private var predictions: [PlacePrediction] = []
    @State private var isSearching = false
    @State private var showDropdown = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    /// Snapshot of recents when dropdown opens; avoids reading ObservableObject in body (reduces main-thread work on focus).
    @State private var recentLocationsSnapshot: [SavedLocation] = []
    
    private let locationService = LocationService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            if !label.isEmpty {
                Text(label)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
            }
            
            // Input field
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        performSearch(query: newValue)
                    }
                    .accessibilityIdentifier(accessibilityId ?? "")
                    .accessibilityHint(accessibilityHintText ?? "")

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !text.isEmpty {
                    Button {
                        clearField()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.naarsCallout)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("location_clear_accessibility".localized)
                }
            }
            // The row is as tall as the 44 pt clear button, so the field does not grow when
            // the first character is typed and the button appears.
            .frame(minHeight: 44)
            .padding(.horizontal)
            .padding(.vertical, 6)
            // Inset fill: this sits on a Form row or a card, and the plain secondary system
            // background is the same color as the row in dark mode (the field had no edge).
            .background(Color.naarsInsetBackground)
            .cornerRadius(Constants.Radius.sm)
            
            // Dropdown suggestions (uses snapshot so body does not read LocationService.recentLocations on main)
            if showDropdown && isFocused {
                VStack(spacing: 0) {
                    // Recent locations (shown when field is empty)
                    if text.isEmpty && !recentLocationsSnapshot.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("location_recent_header".localized)
                                .font(.naarsCaption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            
                            ForEach(recentLocationsSnapshot) { location in
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
                            Text("location_suggestions_header".localized)
                                .font(.naarsCaption)
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
                        Text("location_no_results".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.md)
                .cardShadow()
                .padding(.top, 4)
            }
        }
        .onChange(of: isFocused) { _, focused in
            #if DEBUG
            let t0 = CFAbsoluteTimeGetCurrent()
            os_signpost(.begin, log: _locationPerfLog, name: "FocusHandler")
            if focused {
                os_signpost(.event, log: _locationPerfLog, name: "FocusGained")
                _locationFieldPerfLog("focus gained (tap into field) entry")
                FirstTapPerfLogger.logFocusDelivered(source: "pickup")
            }
            #endif
            if !focused {
                showDropdown = false
                recentLocationsSnapshot = []
                #if DEBUG
                os_signpost(.end, log: _locationPerfLog, name: "FocusHandler")
                _locationFieldPerfLog("focus lost handler exit, \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
                #endif
                return
            }
            // Defer dropdown work to next run loop so gesture/keyboard can complete; avoids main-thread stall.
            #if DEBUG
            let capturedFocusTime = t0
            #endif
            Task { @MainActor in
                #if DEBUG
                let deferStart = CFAbsoluteTimeGetCurrent()
                let gapMs = Int((deferStart - capturedFocusTime) * 1000)
                if gapMs > 500 {
                    _locationFieldPerfLog("WARNING: main thread blocked \(gapMs)ms before deferred dropdown ran")
                }
                os_signpost(.begin, log: _locationPerfLog, name: "DeferredDropdown")
                #endif
                // Short yield so keyboard/input session can establish; avoids "gesture gate timed out" and ~3s stall.
                try? await Task.sleep(nanoseconds: Constants.Timing.locationDropdownAfterFocusNanoseconds)
                guard isFocused else {
                    #if DEBUG
                    os_signpost(.end, log: _locationPerfLog, name: "DeferredDropdown")
                    os_signpost(.end, log: _locationPerfLog, name: "FocusHandler")
                    _locationFieldPerfLog("focus deferred dropdown skipped (lost focus during delay)")
                    #endif
                    return
                }
                let recents = locationService.recentLocations
                recentLocationsSnapshot = recents
                showDropdown = !text.isEmpty || !recents.isEmpty
                #if DEBUG
                os_signpost(.end, log: _locationPerfLog, name: "DeferredDropdown")
                os_signpost(.end, log: _locationPerfLog, name: "FocusHandler")
                let deferMs = Int((CFAbsoluteTimeGetCurrent() - deferStart) * 1000)
                _locationFieldPerfLog("focus deferred dropdown done, recents=\(recents.count), \(deferMs)ms")
                FirstTapPerfLogger.logDeferredDropdownDone(deltaMs: deferMs)
                #endif
            }
            #if DEBUG
            let entryMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            _locationFieldPerfLog("focus gained handler exit (deferred), \(entryMs)ms")
            #endif
        }
        #if DEBUG
        .onAppear { _locationFieldPerfLog("LocationAutocompleteField onAppear (body evaluated)") }
        #endif
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
        #if DEBUG
        _locationFieldPerfLog("performSearch debounce scheduled (300ms)")
        os_signpost(.begin, log: _locationPerfLog, name: "DebounceWait")
        #endif
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            #if DEBUG
            os_signpost(.end, log: _locationPerfLog, name: "DebounceWait")
            _locationFieldPerfLog("performSearch debounce fired, main=\(Thread.isMainThread)")
            #endif
            guard !Task.isCancelled else { return }
            #if DEBUG
            _locationFieldPerfLog("performSearch after debounce, calling searchPlaces")
            os_signpost(.begin, log: _locationPerfLog, name: "AutocompleteSearch")
            #endif
            isSearching = true
            showDropdown = true
            
            do {
                let results = try await locationService.searchPlaces(query: query)
                #if DEBUG
                _locationFieldPerfLog("performSearch first result received (count=\(results.count))")
                #endif
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    #if DEBUG
                    os_signpost(.end, log: _locationPerfLog, name: "AutocompleteSearch")
                    _locationFieldPerfLog("performSearch applying results to state")
                    #endif
                    predictions = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    #if DEBUG
                    os_signpost(.end, log: _locationPerfLog, name: "AutocompleteSearch")
                    #endif
                    predictions = []
                    isSearching = false
                    AppLogger.warning("location", "LocationAutocompleteField search error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func selectPrediction(_ prediction: PlacePrediction) async {
        do {
            let details = try await locationService.getPlaceDetails(placeID: prediction.placeID)
            
            await MainActor.run {
                // Update text field with selected location
                text = Self.fieldText(name: details.name, address: details.address)

                // Save to recents
                let saved = SavedLocation(
                    placeID: details.placeID,
                    name: details.name,
                    address: details.address,
                    latitude: details.coordinate.latitude,
                    longitude: details.coordinate.longitude
                )
                locationService.saveRecentLocation(saved)
                recentLocationsSnapshot = locationService.recentLocations
                
                // Call completion handler
                onSelect?(details)
                
                // Clear predictions and dismiss keyboard
                predictions = []
                isFocused = false
                showDropdown = false
            }
        } catch {
            await MainActor.run {
                // Fallback to prediction text: the title with its subtitle (the street or
                // city line), since the title alone can name several places.
                text = prediction.fullText
                predictions = []
                isFocused = false
                showDropdown = false
                AppLogger.warning("location", "LocationAutocompleteField failed to get place details: \(error.localizedDescription)")
            }
        }
    }
    
    private func selectRecent(_ location: SavedLocation) {
        text = Self.fieldText(name: location.name, address: location.address)
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

    /// The text saved for a chosen place: its name followed by its formatted address. The name
    /// alone ("Starbucks", "Safeway") was searched again by the route map, the savings estimate
    /// and the directions hand-off, and each took the first branch that search returned.
    private static func fieldText(name: String, address: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return trimmedAddress }
        guard !trimmedAddress.isEmpty else { return trimmedName }
        // A street-address result is named after its own street line ("123 Main St"), which
        // the address already starts with. Repeating it would read "123 Main St, 123 Main St…".
        if trimmedAddress.range(of: trimmedName, options: [.caseInsensitive, .anchored]) != nil {
            return trimmedAddress
        }
        // Same street number, different spelling ("123 Main Street" / "123 Main St Seattle…").
        if let nameFirstWord = trimmedName.split(separator: " ").first,
           let addressFirstWord = trimmedAddress.split(separator: " ").first,
           nameFirstWord.first?.isNumber == true,
           nameFirstWord == addressFirstWord {
            return trimmedAddress
        }
        return "\(trimmedName), \(trimmedAddress)"
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
                    .foregroundColor(.naarsPrimary)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(prediction.primaryText)
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                    
                    if !prediction.secondaryText.isEmpty {
                        Text(prediction.secondaryText)
                            .font(.naarsCaption)
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
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name.isEmpty ? location.address : location.name)
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                    
                    if !location.name.isEmpty {
                        Text(location.address)
                            .font(.naarsCaption)
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


