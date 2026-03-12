---
color: silver
position:
  x: -8
  y: -1743
isContextNode: false
agent_name: Amy
---

# Infrastructure: Utilities & Helpers

Core utility functions and helpers used throughout the app.

## Configuration & Constants

### Constants.swift
Centralized app constants:
- **Colors** - Brand colors (naarsPrimary, naarsSuccess, etc.)
- **Timing** - Animation durations, delays
- **Dimensions** - Spacing, sizes, corner radius
- **Supabase** - Bucket names, function names
- **Feature Flags** - Toggle features

### Secrets.swift
Sensitive configuration (gitignored):
- Supabase URL
- Supabase anon key
- Apple Team ID
- Push notification key ID

**Template:** `Secrets.swift.template` for new developers

## Date & Time

### DateFormatters.swift
Shared date formatters:
- `shortDate` - "Jan 15"
- `longDate` - "January 15, 2026"
- `time` - "3:45 PM"
- `relative` - "2 hours ago"
- Prevents repeated formatter creation (performance)

### DateDecoderFactory.swift
Custom JSONDecoder configurations:
- `makeSupabaseDecoder()` - Handles PostgreSQL date formats
- Timezone handling
- ISO8601 parsing

## Caching & Storage

### CacheManager.swift
Generic in-memory cache with TTL:
```swift
CacheManager.shared.set(key: "profile_123", value: profile, ttl: 300)
let cached = CacheManager.shared.get(key: "profile_123")
```

### LocalAttachmentStorage.swift
Local file storage for message attachments:
- Save images/audio before upload
- Retrieve during upload retry
- Clean up after successful upload

### PersistentImageService.swift
Image caching and management:
- Download and cache avatars
- Cache ride/favor images
- Memory + disk cache

## Validation & Formatting

### Validators.swift
Input validation:
- `isValidEmail()`
- `isValidPhoneNumber()`
- `isValidURL()`

### InviteCodeFormatter.swift
Invite code formatting (e.g., "ABC-DEF-GHI"):
```swift
InviteCodeFormatter.format("ABCDEFGHI") // "ABC-DEF-GHI"
```

### InviteCodeGenerator.swift
Generate random invite codes:
```swift
InviteCodeGenerator.generate() // "XYZ-123-ABC"
```

## Location & Mapping

### RideCostEstimator.swift
Calculate ride costs using MapKit:
- Route from pickup to destination
- Estimate distance and time
- Calculate cost based on distance
- Async/await MapKit integration

### GeocodingCacheService.swift
Cache geocoding results:
- Address → Coordinates
- Coordinates → Address
- Reduces MapKit API calls

### RideCostModels.swift
Data models for cost estimation:
- `RouteInfo` - Distance, duration, polyline
- `CostEstimate` - Total, breakdown

## Network & Retry Logic

### NetworkMonitor.swift
Network connectivity monitoring:
- Detect online/offline state
- Notify when connectivity changes
- Used by sync engines to pause/resume

### RetryableOperation.swift
Generic retry logic with exponential backoff:
```swift
try await RetryableOperation.execute(maxRetries: 3) {
    // Network operation
}
```

## User Experience

### HapticManager.swift
Haptic feedback:
- `success()` - Success feedback
- `error()` - Error feedback
- `selection()` - Selection change
- `impact(style:)` - Impact feedback

### Throttler.swift
Prevent rapid repeated actions:
```swift
throttler.throttle {
    // Action that shouldn't run too frequently
}
```

### RateLimiter.swift
Rate limiting for API calls:
```swift
try rateLimiter.checkLimit(key: "claim_action", limit: 5, window: 60)
```

## Localization

### LocalizationManager.swift
Multi-language support:
- Get/set user's preferred language
- Load localization strings
- Force locale for testing

**Usage:**
```swift
"welcome_message".localized
```

## Parsing & Extraction

### PostTitleExtractor.swift
Extract title from post content:
- First line as title
- Or generate from content

### DeepLinkParser.swift
Parse deep links:
- `naars://ride/123` → Navigate to ride detail
- Handle universal links
- Route to appropriate screen

## Error Handling

### AppError.swift
Structured error types:
- `NetworkError`
- `AuthError`
- `ValidationError`
- `StorageError`
With localized descriptions

### AnyCodable.swift
Dynamic JSON handling:
- `AnyCodable` wrapper
- Handle unknown JSON structures

## System

### DeviceIdentifier.swift
Unique device identification:
- Generate stable device ID
- Used for analytics
- Push token association

### Logger.swift
Legacy logging (pre-AppLogger):
- Structured log output
- Category-based logging

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
