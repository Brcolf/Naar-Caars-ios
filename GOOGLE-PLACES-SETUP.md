# Google Places API Setup Instructions

## Overview

The Location Autocomplete feature uses Google Places API REST endpoints (not the SDK). This allows immediate functionality without adding external dependencies.

## Required Setup Steps

### 1. Get Google Places API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Enable **Places API**:
   - Navigate to **APIs & Services** → **Library**
   - Search for "Places API"
   - Click **Enable**

4. Create API Key:
   - Navigate to **APIs & Services** → **Credentials**
   - Click **Create Credentials** → **API Key**
   - Copy the API key

5. Restrict API Key (Recommended):
   - Click on the API key to edit
   - Under **Application restrictions**, select **iOS apps**
   - Add your app's bundle ID (e.g., `com.naarscars.NaarsCars`)
   - Under **API restrictions**, select **Restrict key**
   - Choose **Places API** only
   - Click **Save**

### 2. Add API Key to Secrets.swift

Add the Google Places API key to `NaarsCars/Core/Utilities/Secrets.swift`:

```swift
enum Secrets {
    // ... existing Supabase credentials ...
    
    // Google Places API Key
    static var googlePlacesAPIKey: String {
        // TODO: Add obfuscated Google Places API key here
        // Use the obfuscate.swift script to generate obfuscated bytes
        // swift Scripts/obfuscate.swift "YOUR_GOOGLE_PLACES_API_KEY"
        
        // For now, return environment variable or nil
        #if DEBUG
        return ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"] ?? ""
        #else
        // Return obfuscated key in production
        return deobfuscate(googlePlacesAPIKeyBytes)
        #endif
    }
    
    // Obfuscated Google Places API key bytes
    // Generate with: swift Scripts/obfuscate.swift "YOUR_API_KEY"
    private static let googlePlacesAPIKeyBytes: [UInt8] = [
        // Add obfuscated bytes here
    ]
}
```

### 3. Update LocationService

Update `LocationService.getGooglePlacesAPIKey()` to use `Secrets.googlePlacesAPIKey`:

```swift
private func getGooglePlacesAPIKey() -> String? {
    let key = Secrets.googlePlacesAPIKey
    return key.isEmpty ? nil : key
}
```

### 4. Test API Key

1. Run the app
2. Navigate to Create Ride view
3. Start typing in the pickup location field
4. Autocomplete suggestions should appear

## API Costs

Google Places API pricing (as of 2024):
- **Autocomplete (Per Session)**: $2.83 per 1000 sessions
- **Place Details**: $17 per 1000 requests

**Optimization strategies** (already implemented):
- Debounce search (300ms delay) - TODO: Implement in UI component
- Minimum 2 characters before search
- Cache recent locations locally
- Seattle-area bias to improve relevance

## Troubleshooting

### Error: "Google Places API key is missing"
- Verify API key is added to `Secrets.swift`
- Check that `googlePlacesAPIKey` property exists
- Verify API key is not empty

### Error: "API error: REQUEST_DENIED"
- Check API key restrictions in Google Cloud Console
- Verify Places API is enabled
- Check that bundle ID matches restriction settings

### Error: "API error: INVALID_REQUEST"
- Verify API key format is correct
- Check that Places API is enabled for the project

### No Suggestions Appearing
- Verify API key is valid
- Check network connectivity
- Review API quotas in Google Cloud Console
- Check logs for specific error messages

## Alternative: Using Google Places SDK

If you prefer to use the Google Places SDK instead of REST API:

1. Add SDK via SPM:
   - File → Add Package Dependencies
   - URL: `https://github.com/googlemaps/ios-maps-sdk`
   - Select version 8.0.0 or later

2. Initialize SDK in `AppDelegate` or `NaarsCarsApp.swift`:
   ```swift
   import GooglePlaces
   
   // In application didFinishLaunchingWithOptions or App init
   GMSPlacesClient.provideAPIKey(Secrets.googlePlacesAPIKey)
   ```

3. Update `LocationService.swift` to use SDK methods instead of REST API calls.

## Notes

- The REST API approach is simpler and requires no external dependencies
- The SDK approach provides better performance and offline capabilities
- Both approaches require the same API key and have the same pricing
- The current implementation uses REST API for simplicity

