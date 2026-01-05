# Tasks: Map View

Based on `prd-map-view.md`

## Relevant Files

### Source Files
- `Core/Services/LocationService.swift` - Extend with user location
- `Features/Rides/Views/RideMapView.swift` - Map display
- `UI/Components/Maps/RequestAnnotation.swift` - Map pin

### Test Files
- `NaarsCarsTests/Core/Services/LocationServiceTests.swift`

## Notes

- Uses MapKit for native iOS maps
- Requires location permission
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/map-view`

- [ ] 1.0 Request location permission
  - [ ] 1.1 Verify NSLocationWhenInUseUsageDescription in Info.plist
  - [ ] 1.2 Extend LocationService with CLLocationManager
  - [ ] 1.3 Implement requestLocationPermission()
  - [ ] 1.4 Handle permission states (authorized, denied, notDetermined)
  - [ ] 1.5 Implement getCurrentLocation()
  - [ ] 1.6 🧪 Write LocationServiceTests.testGetCurrentLocation

### 🔒 CHECKPOINT: QA-MAP-001
> Run: `./QA/Scripts/checkpoint.sh map-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: Location permission flow works
> Must pass before continuing

- [ ] 2.0 Build RideMapView
  - [ ] 2.1 Create RideMapView.swift
  - [ ] 2.2 Add Map view with user location
  - [ ] 2.3 Display ride pickup/destination as pins
  - [ ] 2.4 Add polyline route between points
  - [ ] 2.5 Fit map region to show all points

- [ ] 3.0 Build RequestAnnotation
  - [ ] 3.1 Create RequestAnnotation.swift
  - [ ] 3.2 Custom pin appearance for rides
  - [ ] 3.3 Show callout with ride summary
  - [ ] 3.4 Navigate to detail on tap

- [ ] 4.0 Add map to ride detail
  - [ ] 4.1 Add RideMapView to RideDetailView
  - [ ] 4.2 Show route from pickup to destination
  - [ ] 4.3 Add "Open in Maps" button
  - [ ] 4.4 Handle map tap for directions

- [ ] 5.0 Verify map view
  - [ ] 5.1 Test map displays correctly
  - [ ] 5.2 Test user location shown
  - [ ] 5.3 Test route display
  - [ ] 5.4 Test open in Maps
  - [ ] 5.5 Commit: "feat: implement map view"

### 🔒 CHECKPOINT: QA-MAP-FINAL
> Run: `./QA/Scripts/checkpoint.sh map-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Map view tests must pass
