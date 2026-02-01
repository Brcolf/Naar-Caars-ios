# Photo Upload Limits Design

## Problem Statement
Town Hall image uploads and avatar updates currently reject high-resolution iPhone photos. The Town Hall flow performs a pre-compression dimension check against a 2400px limit and then uses the `messageImage` compression preset (1200px/800KB). The avatar flow compresses to a 400px/500KB target. These constraints are stricter than Supabase storage limits (2MB for profile avatars and 5MB for town hall images), so “too large” errors occur even when photos could be safely downscaled and stored. We need to accept standard high-quality iPhone photos while still compressing and resizing to avoid storing full-resolution assets.

## Goals
- Accept standard high-quality iPhone photos for Town Hall posts and avatars.
- Resize and compress to avoid full-resolution storage.
- Keep stored images within current bucket limits.
- Preserve existing UX, with clearer size messaging where applicable.

## Non-Goals
- Changing Supabase bucket policies or storage limits.
- Introducing new storage buckets or media pipelines.
- Refactoring unrelated image flows or database schemas.

## Proposed Approach (Recommended)
Increase compression limits for avatar and Town Hall images, while keeping the existing compression algorithm (resize to max dimension, then iteratively lower JPEG quality until within byte budget). Specifically:
- `ImagePreset.avatar`: 1024px max dimension, 1MB max bytes, initial quality 0.8.
- `ImagePreset.messageImage`: 2048px max dimension, 2.5MB max bytes, initial quality 0.75.
Town Hall uploads already use `messageImage`, so this change aligns the preset with Town Hall needs. The pre-compression dimension check in `CreatePostViewModel` will use the preset’s max dimension and allow images up to 2× that value (4096px), covering standard iPhone photo sizes while still preventing extreme inputs.

## Data Flow
- Avatar: PhotosPicker selection → `ImageCompressor` (avatar preset) → local avatar preview → `ProfileService.uploadAvatar()` → Supabase storage.
- Town Hall: Image selection → pre-check against `messageImage.maxDimension * 2` → `ImageCompressor` (message preset) → Supabase storage → post creation.

## Error Handling
- Town Hall pre-check error message reports the updated max pixel dimension.
- Compression failures continue to surface existing “too large to compress” errors.

## Testing
- Update `ImageCompressorTests` to assert new preset limits and output dimensions.
- Run targeted unit tests for `ImageCompressorTests`.
