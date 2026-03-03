# Filter Tile Fixed-Height Design

**Date:** 2026-03-03
**Status:** Approved

## Problem

The filter tiles ("Open Requests", "My Requests", "Claimed Requests") in RequestsDashboardView wrap inconsistently across phone sizes. Selecting a filter changes font weight from `.regular` to `.semibold`, which widens the text and can push it over the wrap threshold, causing tiles to jump between 1-line and 2-line heights.

## Root Cause

1. `.lineLimit(2)` allows wrapping
2. `.frame(minHeight: 40)` sets a minimum but no fixed height
3. `.fontWeight` changes on selection alter text width, triggering reflow
4. "Claimed Requests" is the longest label and wraps first on smaller screens

## Fix

Two changes in `FilterTile` (in `RequestsDashboardView.swift`):

1. **Constant font weight:** Replace `.fontWeight(isSelected ? .semibold : .regular)` with `.fontWeight(.medium)`. Selection indicated by background color only.
2. **Fixed minimum height:** Replace `minHeight: 40` with `minHeight: 56` to accommodate 2 lines consistently.

## What Does NOT Change

- FilterTilesView layout (HStack with equal-width tiles)
- filterHeaderView (padding, background, divider)
- Section header pinning (pinnedViews: [.sectionHeaders])
- ScrollView .refreshable behavior
- Filter logic in RequestsDashboardViewModel
- Badge overlay
- Localization

## Files Affected

| File | Change |
|------|--------|
| `RequestsDashboardView.swift` | 2-line change in FilterTile struct |
