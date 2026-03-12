# Handoff Prompt — App Store Submission Fixes

Copy-paste this prompt into a new Claude Code session to execute the plan.

---

```
You are executing a pre-written fix plan for App Store submission. The plan is at:
Docs/plans/2026-03-12-app-store-submission-fixes-plan.md

## Rules

1. Read the ENTIRE plan document first before making any changes.
2. Execute steps in exact phase order (Phase 0 → 1 → 2 → 3 → 4 → 5).
3. Within each phase, follow step ordering. Steps marked [parallel] can be done simultaneously.
4. For EVERY code change: read the target file first, find the exact code specified in the plan, then make the edit. Do NOT guess line numbers — the plan's line numbers are approximate.
5. After each phase, run the phase verification commands listed in the plan.
6. If a verification fails, fix the issue before proceeding to the next phase.
7. Do NOT refactor, improve, or change anything beyond what the plan specifies.
8. Do NOT add comments, docstrings, or type annotations unless the plan says to.
9. Use the Supabase MCP tools for database migration steps (Phase 0 and Step 5.3).
10. Step 2.6 (thread view wiring) was already completed — skip it.

## Step 2.5 Note

For the deletion-warning translations (Step 2.5), if you are not confident in translation quality for Spanish, Korean, Vietnamese, Chinese Simplified, or Chinese Traditional, flag the step and provide the English source string for professional translation. Do not guess at translations.

## Context

This plan was produced from a combined audit by Claude Opus and Codex. The app is an iOS social/transportation app called Naar's Cars. The messaging system was recently refactored from SwiftUI to UIKit (UICollectionView with diffable data source). The UIKit refactor branch has been merged to main — all work happens on main.

The codebase is Swift, SwiftUI + UIKit hybrid, with a Supabase backend.

The plan fixes:
- 5 database source/live drift issues (migrations)
- 5 critical app issues (subscription leak, privacy manifest, blocked-user filtering, main-thread hitch, plist accuracy)
- 5 medium-priority issues (retry bug, dark mode, deinit, toggles, translations)
- 3 localization/accessibility issues
- 5 low-risk cleanup items

Start by reading the plan, then begin Phase 0.
```

---

## For Parallel Execution with Multiple Agents

If you want to speed this up by running Sonnet and Opus tasks in parallel, use this modified prompt:

```
Read the fix plan at Docs/plans/2026-03-12-app-store-submission-fixes-plan.md.

Execute ALL Sonnet-assigned steps using parallel subagents where possible. The following groups are independent and can run simultaneously:

Group A (Phase 1 - Sonnet steps): Steps 1.1, 1.2, 1.4, 1.5
Group B (Phase 2 - Sonnet steps): Steps 2.1, 2.2, 2.3
Group C (Phase 3 - all Sonnet): Steps 3.1, 3.2, 3.3
Group D (Phase 4 - all parallel): Steps 4.1, 4.2, 4.3, 4.4, 4.5

Run Group A first. Then Group B. Then C. Then D.

Within each group, dispatch all steps as parallel subagents.

The Opus steps (0.1-0.5, 1.3) must be done sequentially by you (the main agent) because they require architectural judgment.

Step 2.6 is already complete — skip it.

After all groups complete, run Phase 5 verification.
```
