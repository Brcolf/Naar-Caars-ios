# PRD: Leaderboards

## Document Information
- **Feature Name**: Leaderboards
- **Phase**: 3 (Community Features)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

Leaderboards show community members ranked by their helpfulness - how many requests they've fulfilled. This gamifies helping and recognizes top contributors.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Show ranked user list | Leaderboard displays |
| Filter by time period | Year/Quarter/Month views |
| Show fulfilled count | Numbers accurate |
| Highlight current user | User sees their rank |

---

## 3. Functional Requirements

### 3.1 Leaderboard View

```
┌─────────────────────────────────────┐
│   Leaderboards              🏆      │
├─────────────────────────────────────┤
│   ┌─────────────────────────────┐   │
│   │ 2025 │ Q1 2025 │ January   ││   │
│   └─────────────────────────────┘   │
├─────────────────────────────────────┤
│                                     │
│   🥇 #1                             │
│   ┌─────────────────────────────┐   │
│   │ [Avatar]  Bob M.            │   │
│   │ 15 requests fulfilled       │   │
│   │ 8 requests made             │   │
│   └─────────────────────────────┘   │
│                                     │
│   🥈 #2                             │
│   ┌─────────────────────────────┐   │
│   │ [Avatar]  Jane D.           │   │
│   │ 12 requests fulfilled       │   │
│   │ 5 requests made             │   │
│   └─────────────────────────────┘   │
│                                     │
│   🥉 #3                             │
│   ┌─────────────────────────────┐   │
│   │ [Avatar]  You ← (highlighted)│   │
│   │ 10 requests fulfilled       │   │
│   │ 3 requests made             │   │
│   └─────────────────────────────┘   │
│                                     │
│   #4                                │
│   ┌─────────────────────────────┐   │
│   │ [Avatar]  Sara K.           │   │
│   │ 8 requests fulfilled        │   │
│   │ 6 requests made             │   │
│   └─────────────────────────────┘   │
│                                     │
│   ... more users ...                │
│                                     │
└─────────────────────────────────────┘
```

### 3.2 Data Calculation

```swift
struct LeaderboardEntry: Identifiable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let requestsFulfilled: Int
    let requestsMade: Int
    var rank: Int?
    
    var id: UUID { userId }
}

// Query logic:
// 1. Get completed rides where claimed_by = userId
// 2. Get completed favors where claimed_by = userId
// 3. Sum for fulfilled count
// 4. Get rides/favors where user_id = userId for made count
// 5. Filter by date range
// 6. Sort by fulfilled count (descending)
```

### 3.3 Time Filters

| Filter | Date Range |
|--------|------------|
| Year | Current calendar year |
| Quarter | Current quarter (Q1-Q4) |
| Month | Current calendar month |

### 3.4 Features

- **Top 3 medals** (🥇🥈🥉)
- **Highlight current user** with different background
- **Tap user** to view profile
- **Only show active users** (at least 1 request fulfilled or made)
- **Pull to refresh**

---

## 4. Non-Goals

- Historical leaderboards
- Weekly filter
- Achievements/badges
- Points system

---

## 5. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-ride-requests.md`
- `prd-favor-requests.md`

---

*End of PRD: Leaderboards*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 3.2 - Data Calculation

**Replace client-side calculation with server-side:**

```markdown
### 3.2 Data Calculation

**Requirement LB-FR-001**: Leaderboard data MUST be calculated server-side.

**Problem with client-side calculation:**
- At 100+ users: 2-5 second delay
- At 500+ users: potential timeout
- Wastes bandwidth downloading all rides/favors
- Battery drain from processing

#### Option A: Database View (Recommended for MVP)

Create a PostgreSQL view that pre-calculates rankings:

```sql
-- migrations/xxx_create_leaderboard_view.sql

-- Real-time view (always up-to-date)
CREATE OR REPLACE VIEW leaderboard_stats AS
SELECT 
    p.id as user_id,
    p.name,
    p.avatar_url,
    
    -- Requests fulfilled (rides + favors where user is claimer and status = completed)
    COALESCE(
        (SELECT COUNT(*) FROM rides 
         WHERE claimed_by = p.id AND status = 'completed'),
        0
    ) + COALESCE(
        (SELECT COUNT(*) FROM favors 
         WHERE claimed_by = p.id AND status = 'completed'),
        0
    ) as requests_fulfilled,
    
    -- Requests made
    COALESCE(
        (SELECT COUNT(*) FROM rides WHERE user_id = p.id),
        0
    ) + COALESCE(
        (SELECT COUNT(*) FROM favors WHERE user_id = p.id),
        0
    ) as requests_made

FROM profiles p
WHERE p.approved = true;

-- Index for efficient sorting
CREATE INDEX idx_leaderboard_fulfilled 
ON profiles(id) 
INCLUDE (name, avatar_url);
```

#### Option B: Database Function (For Time-Filtered Queries)

For year/quarter/month filtering, create a function:

```sql
CREATE OR REPLACE FUNCTION get_leaderboard(
    start_date DATE DEFAULT '1970-01-01',
    end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
    user_id UUID,
    name TEXT,
    avatar_url TEXT,
    requests_fulfilled BIGINT,
    requests_made BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.name,
        p.avatar_url,
        (
            SELECT COUNT(*) FROM rides r
            WHERE r.claimed_by = p.id 
            AND r.status = 'completed'
            AND r.completed_at BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM favors f
            WHERE f.claimed_by = p.id 
            AND f.status = 'completed'
            AND f.completed_at BETWEEN start_date AND end_date
        ) as requests_fulfilled,
        (
            SELECT COUNT(*) FROM rides r
            WHERE r.user_id = p.id
            AND r.created_at BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM favors f
            WHERE f.user_id = p.id
            AND f.created_at BETWEEN start_date AND end_date
        ) as requests_made
    FROM profiles p
    WHERE p.approved = true
    ORDER BY requests_fulfilled DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql;
```

**Requirement LB-FR-002**: LeaderboardService implementation:

```swift
// Core/Services/LeaderboardService.swift
@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()
    private let supabase = SupabaseService.shared.client
    
    func fetchLeaderboard(period: LeaderboardPeriod) async throws -> [LeaderboardEntry] {
        let (startDate, endDate) = period.dateRange
        
        // Call server-side function
        let response = try await supabase
            .rpc("get_leaderboard", params: [
                "start_date": startDate.ISO8601Format(.iso8601Date(timeZone: .gmt)),
                "end_date": endDate.ISO8601Format(.iso8601Date(timeZone: .gmt))
            ])
            .execute()
        
        var entries = try JSONDecoder().decode(
            [LeaderboardEntry].self, 
            from: response.data
        )
        
        // Add rank numbers (1-indexed)
        for index in entries.indices {
            entries[index].rank = index + 1
        }
        
        return entries
    }
}

// Period date range calculation
extension LeaderboardPeriod {
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
            
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return (start, now)
            
        case .thisQuarter:
            let quarter = (calendar.component(.month, from: now) - 1) / 3
            var components = calendar.dateComponents([.year], from: now)
            components.month = quarter * 3 + 1
            let start = calendar.date(from: components)!
            return (start, now)
            
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return (start, now)
        }
    }
}
```
```

---

## ADD: Section 3.5 - Performance Requirements

**Insert after calculation section**

```markdown
### 3.5 Performance Requirements

**Requirement LB-FR-004**: Leaderboard load time requirements:

| User Count | Max Load Time |
|------------|---------------|
| <100 | <500ms |
| 100-500 | <1s |
| 500+ | <2s |

**Requirement LB-FR-005**: Client caching for leaderboard:

```swift
@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var selectedPeriod: LeaderboardPeriod = .allTime
    
    private var cachedEntries: [LeaderboardPeriod: (entries: [LeaderboardEntry], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 minutes
    
    func loadLeaderboard() async {
        // Check cache first
        if let cached = cachedEntries[selectedPeriod],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            entries = cached.entries
            // Refresh in background
            Task { await fetchFresh(showLoading: false) }
            return
        }
        
        await fetchFresh(showLoading: true)
    }
    
    func refresh() async {
        // Pull-to-refresh bypasses cache
        cachedEntries.removeValue(forKey: selectedPeriod)
        await fetchFresh(showLoading: false)
    }
    
    private func fetchFresh(showLoading: Bool) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }
        
        do {
            let freshEntries = try await LeaderboardService.shared.fetchLeaderboard(
                period: selectedPeriod
            )
            entries = freshEntries
            cachedEntries[selectedPeriod] = (freshEntries, Date())
        } catch {
            // Keep showing cached data if available
            if cachedEntries[selectedPeriod] == nil {
                // No cache - show error
            }
        }
    }
}
```

**Requirement LB-FR-006**: Show cached data immediately, refresh in background:

```swift
struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel()
    
    var body: some View {
        List {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                // Skeleton loading
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonLeaderboardRow()
                }
            } else {
                ForEach(viewModel.entries) { entry in
                    LeaderboardRow(entry: entry)
                }
            }
        }
        .task {
            await viewModel.loadLeaderboard()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            Task { await viewModel.loadLeaderboard() }
        }
    }
}
```
```

---

## ADD: Section 3.6 - Skeleton Loading

**Insert after performance section**

```markdown
### 3.6 Skeleton Loading

**Requirement LB-FR-007**: Show skeleton rows while loading:

```swift
struct SkeletonLeaderboardRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            SkeletonView()
                .frame(width: 30, height: 20)
            
            // Avatar
            SkeletonView()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            
            // Name and stats
            VStack(alignment: .leading, spacing: 4) {
                SkeletonView()
                    .frame(width: 120, height: 16)
                SkeletonView()
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
            
            // Score
            SkeletonView()
                .frame(width: 40, height: 24)
        }
        .padding(.vertical, 8)
    }
}
```
```

---

## ADD: Section 6.1 - Future Scalability

**Insert in appropriate section**

```markdown
### 6.1 Future Scalability

For communities growing beyond 500 users, consider:

#### Materialized View with Scheduled Refresh

```sql
-- Create materialized view for faster queries
CREATE MATERIALIZED VIEW leaderboard_stats_cached AS
SELECT * FROM leaderboard_stats;

-- Create index
CREATE UNIQUE INDEX idx_leaderboard_cached_user 
ON leaderboard_stats_cached(user_id);

CREATE INDEX idx_leaderboard_cached_rank 
ON leaderboard_stats_cached(requests_fulfilled DESC);

-- Refresh schedule (every 15 minutes)
-- Set up via Supabase cron or external scheduler
SELECT cron.schedule(
    'refresh-leaderboard',
    '*/15 * * * *',
    'REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard_stats_cached'
);
```

#### Update Service to Use Materialized View

```swift
// For all-time leaderboard, use cached view
func fetchAllTimeLeaderboard() async throws -> [LeaderboardEntry] {
    let response = try await supabase
        .from("leaderboard_stats_cached")
        .select("user_id, name, avatar_url, requests_fulfilled, requests_made")
        .order("requests_fulfilled", ascending: false)
        .limit(100)
        .execute()
    
    // ... decode
}

// For filtered periods, still use function
func fetchFilteredLeaderboard(period: LeaderboardPeriod) async throws -> [LeaderboardEntry] {
    // ... use get_leaderboard function
}
```
```

---

*End of Leaderboards Addendum*
