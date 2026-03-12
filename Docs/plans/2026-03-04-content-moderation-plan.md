# Content Moderation System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete content moderation system that satisfies App Store Guideline 1.2: reports link to posts/comments, auto-hide at 3+ reports, admin notifications on every report, admin reports queue with hide/restore/dismiss actions, and reporter feedback UX.

**Architecture:** Database-driven moderation using `hidden_at`/`hidden_by` columns on content tables. A DB trigger auto-hides content at 3+ unique reports and notifies admins on every report. The admin panel gets a new Reports section. Feed queries filter hidden content for regular users.

**Tech Stack:** Supabase (PostgreSQL migrations, RPC functions, RLS), SwiftUI, SwiftData

---

### Task 1: Database Migration — Extend Reports Table and Add Moderation Columns

**Files:**
- Create: Supabase migration `content_moderation_system`

Apply via `mcp__supabase__apply_migration`. This single migration does everything:

**Step 1: Apply the migration**

```sql
-- 1. Add post/comment columns to reports table
ALTER TABLE public.reports
    ADD COLUMN IF NOT EXISTS reported_post_id UUID REFERENCES public.town_hall_posts(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS reported_comment_id UUID REFERENCES public.town_hall_comments(id) ON DELETE CASCADE;

-- 2. Update the constraint to accept post/comment reports
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS report_target_check;
ALTER TABLE public.reports ADD CONSTRAINT report_target_check CHECK (
    reported_user_id IS NOT NULL
    OR reported_message_id IS NOT NULL
    OR reported_post_id IS NOT NULL
    OR reported_comment_id IS NOT NULL
);

-- 3. Add indexes for new columns
CREATE INDEX IF NOT EXISTS idx_reports_reported_post ON public.reports(reported_post_id) WHERE reported_post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_reported_comment ON public.reports(reported_comment_id) WHERE reported_comment_id IS NOT NULL;

-- 4. Add moderation columns to town_hall_posts
ALTER TABLE public.town_hall_posts
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 5. Add moderation columns to town_hall_comments
ALTER TABLE public.town_hall_comments
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 6. Admin RLS policy for reports (admins can read all reports)
CREATE POLICY "Admins can view all reports"
ON public.reports FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
);

-- 7. Admin RLS policy for updating reports (admins can update status)
CREATE POLICY "Admins can update reports"
ON public.reports FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
);

-- 8. Replace submit_report to accept post/comment IDs
CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id UUID,
    p_reported_user_id UUID DEFAULT NULL,
    p_reported_message_id UUID DEFAULT NULL,
    p_reported_post_id UUID DEFAULT NULL,
    p_reported_comment_id UUID DEFAULT NULL,
    p_report_type TEXT DEFAULT 'other',
    p_description TEXT DEFAULT NULL
) RETURNS UUID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report_id UUID;
BEGIN
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    -- Prevent duplicate reports from same user on same content
    IF p_reported_post_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports WHERE reporter_id = p_reporter_id AND reported_post_id = p_reported_post_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_comment_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports WHERE reporter_id = p_reporter_id AND reported_comment_id = p_reported_comment_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    INSERT INTO reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        report_type, description
    ) VALUES (
        p_reporter_id, p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_report_type, p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$$;

-- 9. Auto-hide trigger + admin notification on every report
CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
BEGIN
    -- Auto-hide posts at 3+ unique reporters
    IF NEW.reported_post_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM reports WHERE reported_post_id = NEW.reported_post_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM town_hall_posts WHERE id = NEW.reported_post_id;

        IF v_report_count >= 3 THEN
            UPDATE town_hall_posts
            SET hidden_at = NOW(), hidden_by = NULL
            WHERE id = NEW.reported_post_id AND hidden_at IS NULL;
        END IF;
    END IF;

    -- Auto-hide comments at 3+ unique reporters
    IF NEW.reported_comment_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM reports WHERE reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM town_hall_comments WHERE id = NEW.reported_comment_id;

        IF v_report_count >= 3 THEN
            UPDATE town_hall_comments
            SET hidden_at = NOW(), hidden_by = NULL
            WHERE id = NEW.reported_comment_id AND hidden_at IS NULL;
        END IF;
    END IF;

    -- Notify all admins on every report
    IF v_content_preview IS NULL THEN
        v_content_preview := 'User or message report';
    END IF;

    FOR v_admin IN SELECT id FROM profiles WHERE is_admin = true
    LOOP
        v_notification_id := create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            INITCAP(REPLACE(NEW.report_type, '_', ' ')) || ': ' || LEFT(v_content_preview, 60),
            NULL, NULL, NULL, NULL,
            COALESCE(NEW.reported_post_id, NULL),
            NEW.reporter_id
        );
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_report_created ON public.reports;
CREATE TRIGGER on_report_created
    AFTER INSERT ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_report();

-- 10. Admin RPC to hide/restore/dismiss content
CREATE OR REPLACE FUNCTION public.admin_moderate_content(
    p_admin_id UUID,
    p_report_id UUID,
    p_action TEXT,  -- 'hide', 'restore', 'dismiss'
    p_admin_notes TEXT DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_report RECORD;
BEGIN
    -- Verify admin
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_admin_id AND is_admin = true) THEN
        RAISE EXCEPTION 'Unauthorized: not an admin';
    END IF;

    SELECT * INTO v_report FROM reports WHERE id = p_report_id;
    IF v_report IS NULL THEN
        RAISE EXCEPTION 'Report not found';
    END IF;

    IF p_action = 'hide' THEN
        IF v_report.reported_post_id IS NOT NULL THEN
            UPDATE town_hall_posts SET hidden_at = NOW(), hidden_by = p_admin_id
            WHERE id = v_report.reported_post_id;
        END IF;
        IF v_report.reported_comment_id IS NOT NULL THEN
            UPDATE town_hall_comments SET hidden_at = NOW(), hidden_by = p_admin_id
            WHERE id = v_report.reported_comment_id;
        END IF;
        UPDATE reports SET status = 'action_taken', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;

    ELSIF p_action = 'restore' THEN
        IF v_report.reported_post_id IS NOT NULL THEN
            UPDATE town_hall_posts SET hidden_at = NULL, hidden_by = NULL
            WHERE id = v_report.reported_post_id;
        END IF;
        IF v_report.reported_comment_id IS NOT NULL THEN
            UPDATE town_hall_comments SET hidden_at = NULL, hidden_by = NULL
            WHERE id = v_report.reported_comment_id;
        END IF;
        UPDATE reports SET status = 'dismissed', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;

    ELSIF p_action = 'dismiss' THEN
        UPDATE reports SET status = 'dismissed', reviewed_at = NOW(),
            reviewed_by = p_admin_id, admin_notes = p_admin_notes
        WHERE id = p_report_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_moderate_content(UUID, UUID, TEXT, TEXT) TO authenticated;

-- 11. Admin RPC to fetch reports with content details
CREATE OR REPLACE FUNCTION public.admin_get_reports(
    p_admin_id UUID,
    p_status TEXT DEFAULT NULL
) RETURNS TABLE (
    report_id UUID,
    reporter_id UUID,
    reporter_name TEXT,
    reported_user_id UUID,
    reported_user_name TEXT,
    reported_post_id UUID,
    reported_comment_id UUID,
    report_type TEXT,
    description TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    content_preview TEXT,
    content_hidden BOOLEAN,
    report_count INT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_admin_id AND is_admin = true) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT
        r.id AS report_id,
        r.reporter_id,
        rp.name AS reporter_name,
        r.reported_user_id,
        rup.name AS reported_user_name,
        r.reported_post_id,
        r.reported_comment_id,
        r.report_type,
        r.description,
        r.status,
        r.created_at,
        r.reviewed_at,
        COALESCE(
            LEFT(p.content, 120),
            LEFT(c.content, 120),
            'User/message report'
        ) AS content_preview,
        COALESCE(p.hidden_at IS NOT NULL, c.hidden_at IS NOT NULL, false) AS content_hidden,
        COALESCE(
            (SELECT COUNT(DISTINCT r2.reporter_id)::INT FROM reports r2 WHERE r2.reported_post_id = r.reported_post_id AND r.reported_post_id IS NOT NULL),
            (SELECT COUNT(DISTINCT r2.reporter_id)::INT FROM reports r2 WHERE r2.reported_comment_id = r.reported_comment_id AND r.reported_comment_id IS NOT NULL),
            1
        ) AS report_count
    FROM reports r
    LEFT JOIN profiles rp ON rp.id = r.reporter_id
    LEFT JOIN profiles rup ON rup.id = r.reported_user_id
    LEFT JOIN town_hall_posts p ON p.id = r.reported_post_id
    LEFT JOIN town_hall_comments c ON c.id = r.reported_comment_id
    WHERE (p_status IS NULL OR r.status = p_status)
    ORDER BY r.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_reports(UUID, TEXT) TO authenticated;
```

**Step 2: Verify migration applied**

Check with `mcp__supabase__list_migrations` — confirm `content_moderation_system` appears.

**Step 3: Commit migration file**

```bash
git add supabase/migrations/ && git commit -m "feat: content moderation — DB migration with reports, auto-hide, admin RPCs"
```

---

### Task 2: Add `content_reported` Notification Type

**Files:**
- Modify: `NaarsCars/Core/Models/AppNotification.swift`

**Step 1: Add the new case to NotificationType enum**

Add after the existing town hall cases:

```swift
case contentReported = "content_reported"
```

**Step 2: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add NaarsCars/Core/Models/AppNotification.swift && git commit -m "feat: add content_reported notification type"
```

---

### Task 3: Admin Moderation Service

**Files:**
- Create: `NaarsCars/Core/Services/AdminModerationService.swift`

**Step 1: Create the service**

```swift
//
//  AdminModerationService.swift
//  NaarsCars
//
//  Service for admin content moderation actions
//

import Foundation

struct AdminReport: Codable, Identifiable, Equatable {
    let reportId: UUID
    let reporterId: UUID
    let reporterName: String?
    let reportedUserId: UUID?
    let reportedUserName: String?
    let reportedPostId: UUID?
    let reportedCommentId: UUID?
    let reportType: String
    let description: String?
    let status: String
    let createdAt: Date
    let reviewedAt: Date?
    let contentPreview: String?
    let contentHidden: Bool
    let reportCount: Int

    var id: UUID { reportId }

    var reportTypeDisplay: String {
        reportType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isPost: Bool { reportedPostId != nil }
    var isComment: Bool { reportedCommentId != nil }
    var contentTypeLabel: String {
        if reportedPostId != nil { return "Post" }
        if reportedCommentId != nil { return "Comment" }
        if reportedUserId != nil { return "User" }
        return "Message"
    }
}

@MainActor
final class AdminModerationService {
    static let shared = AdminModerationService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    func fetchReports(status: String? = nil) async throws -> [AdminReport] {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }

        var params: [String: String] = ["p_admin_id": userId.uuidString]
        if let status {
            params["p_status"] = status
        }

        let response = try await supabase.rpc("admin_get_reports", params: params).execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date")
        }
        return try decoder.decode([AdminReport].self, from: response.data)
    }

    func moderateContent(reportId: UUID, action: String, notes: String? = nil) async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }

        try await supabase.rpc("admin_moderate_content", params: [
            "p_admin_id": userId.uuidString,
            "p_report_id": reportId.uuidString,
            "p_action": action,
            "p_admin_notes": notes ?? ""
        ]).execute()
    }
}
```

**Step 2: Add to Xcode project and build**

Add the file to the Xcode project in the Core/Services group. Build to verify.

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/AdminModerationService.swift NaarsCars/NaarsCars.xcodeproj/project.pbxproj && git commit -m "feat: add AdminModerationService for report fetching and moderation actions"
```

---

### Task 4: Admin Reports Queue View

**Files:**
- Create: `NaarsCars/Features/Admin/Views/AdminReportsView.swift`
- Modify: `NaarsCars/Features/Admin/Views/AdminPanelView.swift`

**Step 1: Create AdminReportsView**

```swift
//
//  AdminReportsView.swift
//  NaarsCars
//
//  Admin view for reviewing and acting on content reports
//

import SwiftUI

@MainActor
struct AdminReportsView: View {
    @State private var reports: [AdminReport] = []
    @State private var isLoading = false
    @State private var selectedFilter: String? = "pending"
    @State private var error: String?

    private let filters: [(label: String, value: String?)] = [
        ("All", nil),
        ("Pending", "pending"),
        ("Resolved", "action_taken"),
        ("Dismissed", "dismissed")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.label) { filter in
                        Button(filter.label) {
                            selectedFilter = filter.value
                            Task { await loadReports() }
                        }
                        .font(.naarsSubheadline)
                        .fontWeight(selectedFilter == filter.value ? .semibold : .regular)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selectedFilter == filter.value ? Color.naarsPrimary : Color(.systemGray5))
                        )
                        .foregroundColor(selectedFilter == filter.value ? .white : .primary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if isLoading && reports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reports.isEmpty {
                ContentUnavailableView("No Reports", systemImage: "checkmark.shield", description: Text("No reports to review"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(reports) { report in
                        ReportCardView(report: report, onAction: { action in
                            Task { await handleAction(action, report: report) }
                        })
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadReports() }
            }
        }
        .navigationTitle("Reports")
        .task { await loadReports() }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await AdminModerationService.shared.fetchReports(status: selectedFilter)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func handleAction(_ action: String, report: AdminReport) async {
        do {
            try await AdminModerationService.shared.moderateContent(reportId: report.reportId, action: action)
            await loadReports()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Report Card

private struct ReportCardView: View {
    let report: AdminReport
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: content type + report type badge
            HStack {
                Label(report.contentTypeLabel, systemImage: report.isPost ? "text.bubble" : "text.quote")
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(report.reportTypeDisplay)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(reportTypeBadgeColor.opacity(0.15))
                    .foregroundColor(reportTypeBadgeColor)
                    .clipShape(Capsule())

                if report.reportCount > 1 {
                    Text("\(report.reportCount) reports")
                        .font(.naarsCaption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            // Content preview
            if let preview = report.contentPreview {
                Text(preview)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Reporter info + timestamp
            HStack {
                if let name = report.reporterName {
                    Text("Reported by \(name)")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(report.createdAt, style: .relative)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            // Auto-hidden indicator
            if report.contentHidden && report.status == "pending" {
                Label("Auto-hidden", systemImage: "eye.slash")
                    .font(.naarsCaption)
                    .foregroundColor(.orange)
            }

            // Action buttons (only for pending reports)
            if report.status == "pending" {
                HStack(spacing: 12) {
                    if !report.contentHidden {
                        Button(action: { onAction("hide") }) {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Button(action: { onAction("restore") }) {
                            Label("Restore", systemImage: "eye")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }

                    Button(action: { onAction("dismiss") }) {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            } else {
                Text(report.status == "action_taken" ? "Action taken" : "Dismissed")
                    .font(.naarsCaption)
                    .foregroundColor(report.status == "action_taken" ? .red : .green)
            }
        }
        .padding(.vertical, 6)
    }

    private var reportTypeBadgeColor: Color {
        switch report.reportType {
        case "harassment": return .red
        case "spam": return .orange
        case "inappropriate_content": return .purple
        case "scam": return .red
        default: return .secondary
        }
    }
}
```

**Step 2: Add Reports link to AdminPanelView**

In `AdminPanelView.swift`, add a NavigationLink to the management/navigation section (alongside Pending Users and User Management):

```swift
NavigationLink(destination: AdminReportsView()) {
    Label("Reports", systemImage: "flag.fill")
}
```

**Step 3: Add to Xcode project, build, commit**

```bash
git add NaarsCars/Features/Admin/Views/AdminReportsView.swift NaarsCars/Features/Admin/Views/AdminPanelView.swift NaarsCars/NaarsCars.xcodeproj/project.pbxproj && git commit -m "feat: admin reports queue with hide/restore/dismiss actions"
```

---

### Task 5: Filter Hidden Content from Town Hall Feed

**Files:**
- Modify: `NaarsCars/Core/Services/TownHallService.swift`

**Step 1: Update post fetch queries to filter hidden content**

In the `fetchPosts` method, add `.is("hidden_at", value: .null)` to the query chain:

```swift
let response = try await supabase
    .from("town_hall_posts")
    .select()
    .is("hidden_at", value: .null)    // ← add this line
    .order("created_at", ascending: false)
    .range(from: offset, to: offset + limit - 1)
    .execute()
```

Do the same for any other post fetch queries in the file (search for `.from("town_hall_posts")`).

For comments, add the same filter to comment fetch queries (`.is("hidden_at", value: .null)`).

**Step 2: Update SwiftData models**

Add `hiddenAt` to `SDTownHallPost` and `SDTownHallComment` in `SDModels.swift` as optional Date:

```swift
var hiddenAt: Date?
```

And the corresponding `TownHallPost` and `TownHallComment` models if they don't have it.

**Step 3: Build and commit**

```bash
git add NaarsCars/Core/Services/TownHallService.swift NaarsCars/Core/Storage/SDModels.swift && git commit -m "feat: filter hidden content from Town Hall feed"
```

---

### Task 6: Reporter Feedback UX — Toast + Disable Re-Report

**Files:**
- Modify: `NaarsCars/Features/TownHall/Views/ReportContentSheet.swift`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`

**Step 1: Track reported IDs in a shared set**

Add a static set to track reported content in the session. In `ReportContentSheet.swift`, after successful submission, add the ID to a shared set and show a toast.

**Step 2: Update ReportContentSheet to return reported ID on success**

Add an `onReported` closure parameter to ReportContentSheet that passes back the content ID when report succeeds. The parent view uses this to update its local state.

**Step 3: Update TownHallPostCard flag button**

Replace the flag button with a "Reported" label (grayed out) when the post has been reported by the current user in this session:

```swift
if hasReported {
    Label("Reported", systemImage: "flag.fill")
        .font(.naarsCaption)
        .foregroundColor(.secondary)
} else if !isOwnPost {
    Button(action: { showReportSheet = true }) {
        Image(systemName: "flag")
            .font(.naarsCaption)
            .foregroundColor(.secondary)
    }
}
```

**Step 4: Build and commit**

```bash
git add NaarsCars/Features/TownHall/Views/ReportContentSheet.swift NaarsCars/Features/TownHall/Views/TownHallPostCard.swift && git commit -m "feat: reporter feedback — toast confirmation and disable re-report"
```

---

### Task 7: Final Verification

**Step 1: Clean build**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 15' clean build 2>&1 | tail -5
```

**Step 2: Test end-to-end**

1. Report a Town Hall post → should see "Report submitted" toast, flag changes to "Reported"
2. Check admin panel → Reports section should show the report with Hide/Dismiss actions
3. Report same post from 2 other accounts (or insert test reports) → post should auto-hide after 3rd report
4. Admin restores auto-hidden post → post reappears in feed
5. Admin hides a post manually → post disappears from feed
6. Verify admin got notification for each report

**Step 3: Run advisors check**

Use `mcp__supabase__get_advisors` with type "security" to verify RLS is correct on the new columns/policies.
