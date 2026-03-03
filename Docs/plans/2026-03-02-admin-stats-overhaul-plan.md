# Admin Dashboard Stats Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Admin Panel stats cards (Pending/Members/Active) with operational metrics (Requests Fulfilled, Total Savings, Active Rides) with tappable overlay sheets showing time-period breakdowns.

**Architecture:** Server-side RPC functions compute aggregates; Swift client calls RPCs via AdminService; three new sheet views present drill-down data. StatCard becomes tappable via Button wrapper.

**Tech Stack:** PostgreSQL RPC functions (SECURITY DEFINER), Supabase Swift SDK `.rpc()`, SwiftUI sheets with segmented pickers.

---

### Task 1: Create Supabase RPC — `admin_dashboard_stats`

**Files:**
- Create: `database/114_admin_dashboard_stats.sql`

**Step 1: Write the migration SQL**

Create file `database/114_admin_dashboard_stats.sql`:

```sql
-- Migration: Admin dashboard summary stats RPC
-- Returns top-level card values for the admin panel

CREATE OR REPLACE FUNCTION admin_dashboard_stats()
RETURNS JSON AS $$
DECLARE
    v_fulfilled BIGINT;
    v_savings NUMERIC(12,2);
    v_active BIGINT;
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    -- Count completed rides + favors
    SELECT COALESCE(
        (SELECT COUNT(*) FROM rides WHERE status = 'completed'),
        0
    ) + COALESCE(
        (SELECT COUNT(*) FROM favors WHERE status = 'completed'),
        0
    ) INTO v_fulfilled;

    -- Sum estimated_cost from all rides that have a value
    SELECT COALESCE(SUM(estimated_cost), 0)
    INTO v_savings
    FROM rides
    WHERE estimated_cost IS NOT NULL;

    -- Count unfinished rides (open + pending + confirmed)
    SELECT COUNT(*)
    INTO v_active
    FROM rides
    WHERE status IN ('open', 'pending', 'confirmed');

    RETURN json_build_object(
        'fulfilled_count', v_fulfilled,
        'total_savings', v_savings,
        'active_rides_count', v_active
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_dashboard_stats() TO authenticated;
```

**Step 2: Apply the migration via Supabase MCP**

Use `mcp__supabase__apply_migration` with name `admin_dashboard_stats` and the SQL above.

**Step 3: Verify the function works**

Run: `mcp__supabase__execute_sql` with `SELECT admin_dashboard_stats();`
Expected: JSON with `fulfilled_count`, `total_savings`, `active_rides_count`.

**Step 4: Commit**

```bash
git add database/114_admin_dashboard_stats.sql
git commit -m "feat: add admin_dashboard_stats RPC function"
```

---

### Task 2: Create Supabase RPC — `admin_stats_fulfilled`

**Files:**
- Create: `database/115_admin_stats_fulfilled.sql`

**Step 1: Write the migration SQL**

```sql
-- Migration: Admin stats fulfilled breakdown by period
-- Returns completed request counts grouped by week/month/year

CREATE OR REPLACE FUNCTION admin_stats_fulfilled(
    p_period TEXT DEFAULT 'month',
    p_count INT DEFAULT 12
)
RETURNS JSON AS $$
DECLARE
    v_trunc TEXT;
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    -- Map period to date_trunc argument
    v_trunc := CASE p_period
        WHEN 'week' THEN 'week'
        WHEN 'month' THEN 'month'
        WHEN 'year' THEN 'year'
        ELSE 'month'
    END;

    RETURN (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT
                period_start,
                SUM(ride_count)::BIGINT AS ride_count,
                SUM(favor_count)::BIGINT AS favor_count,
                SUM(ride_count + favor_count)::BIGINT AS total_count
            FROM (
                -- Completed rides
                SELECT
                    date_trunc(v_trunc, r.updated_at)::DATE AS period_start,
                    COUNT(*) AS ride_count,
                    0 AS favor_count
                FROM rides r
                WHERE r.status = 'completed'
                GROUP BY date_trunc(v_trunc, r.updated_at)

                UNION ALL

                -- Completed favors
                SELECT
                    date_trunc(v_trunc, f.updated_at)::DATE AS period_start,
                    0 AS ride_count,
                    COUNT(*) AS favor_count
                FROM favors f
                WHERE f.status = 'completed'
                GROUP BY date_trunc(v_trunc, f.updated_at)
            ) combined
            GROUP BY period_start
            ORDER BY period_start DESC
            LIMIT p_count
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_fulfilled(TEXT, INT) TO authenticated;
```

**Step 2: Apply and verify**

Apply migration, then run: `SELECT admin_stats_fulfilled('month', 6);`
Expected: JSON array of `{period_start, ride_count, favor_count, total_count}`.

**Step 3: Commit**

```bash
git add database/115_admin_stats_fulfilled.sql
git commit -m "feat: add admin_stats_fulfilled RPC function"
```

---

### Task 3: Create Supabase RPC — `admin_stats_savings`

**Files:**
- Create: `database/116_admin_stats_savings.sql`

**Step 1: Write the migration SQL**

```sql
-- Migration: Admin stats savings breakdown by period
-- Returns estimated_cost sums grouped by week/month/year

CREATE OR REPLACE FUNCTION admin_stats_savings(
    p_period TEXT DEFAULT 'month',
    p_count INT DEFAULT 12
)
RETURNS JSON AS $$
DECLARE
    v_trunc TEXT;
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    v_trunc := CASE p_period
        WHEN 'week' THEN 'week'
        WHEN 'month' THEN 'month'
        WHEN 'year' THEN 'year'
        ELSE 'month'
    END;

    RETURN (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT
                date_trunc(v_trunc, r.created_at)::DATE AS period_start,
                COALESCE(SUM(r.estimated_cost), 0)::NUMERIC(12,2) AS total_savings,
                COUNT(*)::BIGINT AS ride_count
            FROM rides r
            WHERE r.estimated_cost IS NOT NULL
            GROUP BY date_trunc(v_trunc, r.created_at)
            ORDER BY period_start DESC
            LIMIT p_count
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_savings(TEXT, INT) TO authenticated;
```

**Step 2: Apply and verify**

Apply migration, then run: `SELECT admin_stats_savings('month', 6);`
Expected: JSON array of `{period_start, total_savings, ride_count}`.

**Step 3: Commit**

```bash
git add database/116_admin_stats_savings.sql
git commit -m "feat: add admin_stats_savings RPC function"
```

---

### Task 4: Create Supabase RPC — `admin_stats_active_rides`

**Files:**
- Create: `database/117_admin_stats_active_rides.sql`

**Step 1: Write the migration SQL**

```sql
-- Migration: Admin stats active (unfinished) rides
-- Returns all rides with status open/pending/confirmed with poster/claimer names

CREATE OR REPLACE FUNCTION admin_stats_active_rides()
RETURNS JSON AS $$
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    RETURN (
        SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
        FROM (
            SELECT
                r.id,
                r.pickup,
                r.destination,
                r.date,
                r.time,
                r.status,
                r.claimed_by,
                poster.name AS poster_name,
                claimer.name AS claimer_name
            FROM rides r
            LEFT JOIN profiles poster ON poster.id = r.user_id
            LEFT JOIN profiles claimer ON claimer.id = r.claimed_by
            WHERE r.status IN ('open', 'pending', 'confirmed')
            ORDER BY r.date ASC, r.time ASC
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_active_rides() TO authenticated;
```

**Step 2: Apply and verify**

Apply migration, then run: `SELECT admin_stats_active_rides();`
Expected: JSON array of ride objects with poster_name and claimer_name.

**Step 3: Commit**

```bash
git add database/117_admin_stats_active_rides.sql
git commit -m "feat: add admin_stats_active_rides RPC function"
```

---

### Task 5: Update AdminService with new stats methods

**Files:**
- Modify: `NaarsCars/Core/Services/AdminService.swift:11-21` (add response DTOs)
- Modify: `NaarsCars/Core/Services/AdminService.swift:132-190` (replace fetchAdminStats)

**Step 1: Add response DTOs at top of file (after existing DTOs, around line 21)**

Add these structs after the existing `BroadcastParams` struct (after line 28):

```swift
// MARK: - Admin Stats DTOs

struct AdminDashboardStats: Decodable {
    let fulfilledCount: Int
    let totalSavings: Double
    let activeRidesCount: Int

    enum CodingKeys: String, CodingKey {
        case fulfilledCount = "fulfilled_count"
        case totalSavings = "total_savings"
        case activeRidesCount = "active_rides_count"
    }
}

struct FulfilledPeriod: Decodable, Identifiable {
    let periodStart: Date
    let rideCount: Int
    let favorCount: Int
    let totalCount: Int

    var id: Date { periodStart }

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case rideCount = "ride_count"
        case favorCount = "favor_count"
        case totalCount = "total_count"
    }
}

struct SavingsPeriod: Decodable, Identifiable {
    let periodStart: Date
    let totalSavings: Double
    let rideCount: Int

    var id: Date { periodStart }

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case totalSavings = "total_savings"
        case rideCount = "ride_count"
    }
}

struct ActiveRideRow: Decodable, Identifiable {
    let id: UUID
    let pickup: String
    let destination: String
    let date: Date
    let time: String
    let status: String
    let claimedBy: UUID?
    let posterName: String?
    let claimerName: String?

    enum CodingKeys: String, CodingKey {
        case id, pickup, destination, date, time, status
        case claimedBy = "claimed_by"
        case posterName = "poster_name"
        case claimerName = "claimer_name"
    }
}
```

**Step 2: Replace `fetchAdminStats()` method (lines 132-190)**

Replace the existing `fetchAdminStats` method with:

```swift
/// Fetch admin dashboard summary stats via RPC
/// - Returns: AdminDashboardStats with fulfilled count, savings, and active rides
/// - Throws: AppError if not admin or fetch fails
func fetchDashboardStats() async throws -> AdminDashboardStats {
    try await verifyAdminStatus()

    let response = try await supabase
        .rpc("admin_dashboard_stats")
        .execute()

    let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: response.data)

    AppLogger.info("admin", "Dashboard stats: \(stats.fulfilledCount) fulfilled, $\(stats.totalSavings) savings, \(stats.activeRidesCount) active")
    return stats
}

/// Fetch fulfilled requests breakdown by period
func fetchFulfilledBreakdown(period: String, count: Int = 12) async throws -> [FulfilledPeriod] {
    try await verifyAdminStatus()

    let params: [String: AnyCodable] = [
        "p_period": AnyCodable(period),
        "p_count": AnyCodable(count)
    ]

    let response = try await supabase
        .rpc("admin_stats_fulfilled", params: params)
        .execute()

    let decoder = DateDecoderFactory.makeSupabaseDecoder()
    let periods = try decoder.decode([FulfilledPeriod]?.self, from: response.data)
    return periods ?? []
}

/// Fetch savings breakdown by period
func fetchSavingsBreakdown(period: String, count: Int = 12) async throws -> [SavingsPeriod] {
    try await verifyAdminStatus()

    let params: [String: AnyCodable] = [
        "p_period": AnyCodable(period),
        "p_count": AnyCodable(count)
    ]

    let response = try await supabase
        .rpc("admin_stats_savings", params: params)
        .execute()

    let decoder = DateDecoderFactory.makeSupabaseDecoder()
    let periods = try decoder.decode([SavingsPeriod]?.self, from: response.data)
    return periods ?? []
}

/// Fetch all active (unfinished) rides
func fetchActiveRides() async throws -> [ActiveRideRow] {
    try await verifyAdminStatus()

    let response = try await supabase
        .rpc("admin_stats_active_rides")
        .execute()

    let decoder = DateDecoderFactory.makeSupabaseDecoder()
    let rides = try decoder.decode([ActiveRideRow]?.self, from: response.data)
    return rides ?? []
}
```

**Step 3: Remove the old `UserIdResponse` DTO (line 19-21)** since it's no longer needed.

**Step 4: Verify it compiles**

Build the project to confirm no compile errors.

**Step 5: Commit**

```bash
git add NaarsCars/Core/Services/AdminService.swift
git commit -m "feat: add RPC-based admin stats methods to AdminService"
```

---

### Task 6: Update AdminPanelViewModel

**Files:**
- Modify: `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift`

**Step 1: Replace published properties and loadStats**

Replace the entire file content with:

```swift
//
//  AdminPanelViewModel.swift
//  NaarsCars
//
//  ViewModel for admin panel dashboard
//

import Foundation
internal import Combine

/// ViewModel for admin panel dashboard
@MainActor
final class AdminPanelViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isVerifyingAdmin: Bool = false
    @Published var isAdmin: Bool = false
    @Published var fulfilledCount: Int = 0
    @Published var totalSavings: Double = 0
    @Published var activeRidesCount: Int = 0
    @Published var error: AppError?
    @Published var isLoading: Bool = false

    // MARK: - Private Properties

    private let adminService = AdminService.shared
    private var hasVerified = false

    // MARK: - Computed Properties

    /// Formatted savings string (e.g. "$1,234")
    var formattedSavings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalSavings)) ?? "$0"
    }

    // MARK: - Public Methods

    /// Verify admin access and load stats
    func verifyAdminAccess() async {
        guard !hasVerified else { return }

        isVerifyingAdmin = true
        error = nil
        defer { isVerifyingAdmin = false }

        do {
            try await adminService.verifyAdminStatus()
            hasVerified = true
            isAdmin = true
            await loadStats()
        } catch {
            self.error = error as? AppError ?? AppError.unauthorized
            isAdmin = false
            Log.security("Non-admin accessed admin panel view")
        }
    }

    /// Load admin dashboard statistics via RPC
    func loadStats() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let stats = try await adminService.fetchDashboardStats()
            fulfilledCount = stats.fulfilledCount
            totalSavings = stats.totalSavings
            activeRidesCount = stats.activeRidesCount
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error loading stats: \(error.localizedDescription)")
        }
    }
}
```

**Step 2: Verify it compiles**

**Step 3: Commit**

```bash
git add NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift
git commit -m "feat: update AdminPanelViewModel for new stats"
```

---

### Task 7: Create overlay views

**Files:**
- Create: `NaarsCars/Features/Admin/Views/AdminFulfilledOverlay.swift`
- Create: `NaarsCars/Features/Admin/Views/AdminSavingsOverlay.swift`
- Create: `NaarsCars/Features/Admin/Views/AdminActiveRidesOverlay.swift`

**Step 1: Create AdminFulfilledOverlay.swift**

```swift
//
//  AdminFulfilledOverlay.swift
//  NaarsCars
//
//  Overlay showing fulfilled requests breakdown by period
//

import SwiftUI

struct AdminFulfilledOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [FulfilledPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let periodOptions = ["week", "month", "year"]
    private let adminService = AdminService.shared

    private var total: Int {
        periods.reduce(0) { $0 + $1.totalCount }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    Text("Week").tag("week")
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                }
                .pickerStyle(.segmented)
                .padding()

                // Total
                VStack(spacing: 4) {
                    Text("\(total)")
                        .font(.system(size: 48, weight: .bold))
                    Text("Requests Fulfilled")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)

                // Breakdown list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(periods) { period in
                        HStack {
                            Text(periodLabel(period.periodStart))
                                .font(.naarsBody)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(period.totalCount)")
                                    .font(.naarsHeadline)
                                Text("\(period.rideCount) rides, \(period.favorCount) favors")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Requests Fulfilled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            periods = try await adminService.fetchFulfilledBreakdown(period: selectedPeriod)
        } catch {
            self.error = "Failed to load data"
            AppLogger.error("admin", "Fulfilled overlay error: \(error.localizedDescription)")
        }
    }

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case "week":
            formatter.dateFormat = "MMM d, yyyy"
            return "Week of \(formatter.string(from: date))"
        case "year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        default:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }
}
```

**Step 2: Create AdminSavingsOverlay.swift**

```swift
//
//  AdminSavingsOverlay.swift
//  NaarsCars
//
//  Overlay showing savings breakdown by period
//

import SwiftUI

struct AdminSavingsOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [SavingsPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let periodOptions = ["week", "month", "year"]
    private let adminService = AdminService.shared

    private var total: Double {
        periods.reduce(0) { $0 + $1.totalSavings }
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: total)) ?? "$0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    Text("Week").tag("week")
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                }
                .pickerStyle(.segmented)
                .padding()

                // Total
                VStack(spacing: 4) {
                    Text(formattedTotal)
                        .font(.system(size: 48, weight: .bold))
                    Text("Total Savings")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)

                // Breakdown list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(periods) { period in
                        HStack {
                            Text(periodLabel(period.periodStart))
                                .font(.naarsBody)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCurrency(period.totalSavings))
                                    .font(.naarsHeadline)
                                Text("\(period.rideCount) rides")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Total Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            periods = try await adminService.fetchSavingsBreakdown(period: selectedPeriod)
        } catch {
            self.error = "Failed to load data"
            AppLogger.error("admin", "Savings overlay error: \(error.localizedDescription)")
        }
    }

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case "week":
            formatter.dateFormat = "MMM d, yyyy"
            return "Week of \(formatter.string(from: date))"
        case "year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        default:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
```

**Step 3: Create AdminActiveRidesOverlay.swift**

```swift
//
//  AdminActiveRidesOverlay.swift
//  NaarsCars
//
//  Overlay listing all unfinished rides
//

import SwiftUI

struct AdminActiveRidesOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rides: [ActiveRideRow] = []
    @State private var isLoading = false
    @State private var error: String?

    private let adminService = AdminService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    Text(error)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rides.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.naarsSuccess)
                        Text("No active rides")
                            .font(.naarsHeadline)
                        Text("All rides have been completed")
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(rides) { ride in
                        VStack(alignment: .leading, spacing: 6) {
                            // Poster and claimer
                            HStack {
                                Text(ride.posterName ?? "Unknown")
                                    .font(.naarsHeadline)
                                if let claimer = ride.claimerName {
                                    Image(systemName: "arrow.right")
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                    Text(claimer)
                                        .font(.naarsHeadline)
                                }
                                Spacer()
                                statusBadge(ride.status)
                            }

                            // Route
                            HStack(spacing: 4) {
                                Text(ride.pickup)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(ride.destination)
                            }
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                            // Date
                            Text(formatDate(ride.date))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Active Rides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            rides = try await adminService.fetchActiveRides()
        } catch {
            self.error = "Failed to load data"
            AppLogger.error("admin", "Active rides overlay error: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = switch status {
        case "open": ("Open", .naarsSuccess)
        case "pending": ("Pending", .naarsWarning)
        case "confirmed": ("Claimed", .naarsPrimary)
        default: (status.capitalized, .gray)
        }

        Text(text)
            .font(.naarsCaption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Admin/Views/AdminFulfilledOverlay.swift NaarsCars/Features/Admin/Views/AdminSavingsOverlay.swift NaarsCars/Features/Admin/Views/AdminActiveRidesOverlay.swift
git commit -m "feat: add admin stats overlay views"
```

---

### Task 8: Update AdminPanelView — tappable stats with sheets

**Files:**
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift:82-110` (statsSection)
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift:264-295` (StatCard)

**Step 1: Add sheet state properties to AdminPanelView**

Add after line 14 (`@Environment(\.dismiss) private var dismiss`):

```swift
@State private var showFulfilledOverlay = false
@State private var showSavingsOverlay = false
@State private var showActiveRidesOverlay = false
```

**Step 2: Replace the statsSection (lines 82-110)**

```swift
@ViewBuilder
private var statsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("admin_stats".localized)
            .font(.naarsTitle3)

        HStack(spacing: 16) {
            Button { showFulfilledOverlay = true } label: {
                StatCard(
                    title: "Fulfilled",
                    value: "\(viewModel.fulfilledCount)",
                    icon: "checkmark.circle.fill",
                    color: .naarsSuccess
                )
            }
            .buttonStyle(.plain)

            Button { showSavingsOverlay = true } label: {
                StatCard(
                    title: "Savings",
                    value: viewModel.formattedSavings,
                    icon: "dollarsign.circle.fill",
                    color: .naarsSuccess
                )
            }
            .buttonStyle(.plain)

            Button { showActiveRidesOverlay = true } label: {
                StatCard(
                    title: "Active",
                    value: "\(viewModel.activeRidesCount)",
                    icon: "clock.fill",
                    color: .naarsWarning
                )
            }
            .buttonStyle(.plain)
        }
    }
    .sheet(isPresented: $showFulfilledOverlay) {
        AdminFulfilledOverlay()
    }
    .sheet(isPresented: $showSavingsOverlay) {
        AdminSavingsOverlay()
    }
    .sheet(isPresented: $showActiveRidesOverlay) {
        AdminActiveRidesOverlay()
    }
}
```

**Step 3: Remove old localized string references**

The old `admin_stat_pending`, `admin_stat_members`, `admin_stat_active` localized keys are no longer used. The new labels are hardcoded since they're admin-only and don't need localization.

**Step 4: Remove references to old ViewModel properties**

In `navigationSection`, the `pendingCount` badge (lines 175-184) references `viewModel.pendingCount`. This property no longer exists on the VM. We should keep the Pending Approvals navigation link but remove the badge count since admin stats no longer tracks pending users. Replace the conditional badge with nothing:

Remove lines 175-184 (the `if viewModel.pendingCount > 0 { ... }` block).

**Step 5: Verify it compiles**

**Step 6: Commit**

```bash
git add NaarsCars/Features/Admin/Views/AdminPanelView.swift
git commit -m "feat: make admin stats cards tappable with overlay sheets"
```

---

### Task 9: End-to-end verification

**Step 1: Build the project**

Ensure the full project compiles without errors.

**Step 2: Test the RPCs manually**

Run via Supabase MCP:
- `SELECT admin_dashboard_stats();`
- `SELECT admin_stats_fulfilled('month', 3);`
- `SELECT admin_stats_savings('month', 3);`
- `SELECT admin_stats_active_rides();`

**Step 3: Final commit with all files**

If any fixups were needed, commit them.

```bash
git add -A
git commit -m "feat: admin dashboard stats overhaul - fulfilled, savings, active rides"
```
