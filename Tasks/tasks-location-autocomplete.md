# Tasks: Location Autocomplete

Based on `prd-location-autocomplete.md`

## Relevant Files

### Source Files
- `Core/Services/LocationService.swift` - Location autocomplete
- `UI/Components/Inputs/LocationSearchField.swift` - Autocomplete input
- `UI/Components/Inputs/LocationSuggestionRow.swift` - Suggestion row

### Test Files
- `NaarsCarsTests/Core/Services/LocationServiceTests.swift`

## Notes

- Uses MapKit MKLocalSearchCompleter
- No API key required for basic usage
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/location-autocomplete`

- [ ] 1.0 Implement LocationService
  - [ ] 1.1 Create LocationService.swift
  - [ ] 1.2 Import MapKit
  - [ ] 1.3 Create MKLocalSearchCompleter instance
  - [ ] 1.4 Implement search(query:) method
  - [ ] 1.5 Handle MKLocalSearchCompleterDelegate results
  - [ ] 1.6 Return array of location suggestions
  - [ ] 1.7 🧪 Write LocationServiceTests.testSearch_ReturnsResults
  - [ ] 1.8 Implement getPlaceDetails(for:) using MKLocalSearch
  - [ ] 1.9 🧪 Write LocationServiceTests.testGetPlaceDetails

### 🔒 CHECKPOINT: QA-LOCATION-001
> Run: `./QA/Scripts/checkpoint.sh location-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: LocationService tests pass
> Must pass before continuing

- [ ] 2.0 Build LocationSearchField
  - [ ] 2.1 Create LocationSearchField.swift
  - [ ] 2.2 Add TextField for search input
  - [ ] 2.3 Debounce input (300ms)
  - [ ] 2.4 Show suggestions in dropdown
  - [ ] 2.5 Dismiss suggestions on selection
  - [ ] 2.6 Return selected location string

- [ ] 3.0 Build LocationSuggestionRow
  - [ ] 3.1 Create LocationSuggestionRow.swift
  - [ ] 3.2 Display place name and subtitle
  - [ ] 3.3 Add location pin icon
  - [ ] 3.4 Handle tap to select

- [ ] 4.0 Integrate into ride/favor forms
  - [ ] 4.1 Replace pickup TextField with LocationSearchField
  - [ ] 4.2 Replace destination TextField with LocationSearchField
  - [ ] 4.3 Replace favor location with LocationSearchField

- [ ] 5.0 Verify location autocomplete
  - [ ] 5.1 Test typing in location field
  - [ ] 5.2 Test suggestions appear
  - [ ] 5.3 Test selection populates field
  - [ ] 5.4 Test clear and re-search
  - [ ] 5.5 Commit: "feat: implement location autocomplete"

### 🔒 CHECKPOINT: QA-LOCATION-FINAL
> Run: `./QA/Scripts/checkpoint.sh location-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Location autocomplete tests must pass
