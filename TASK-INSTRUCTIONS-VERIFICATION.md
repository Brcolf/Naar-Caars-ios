# Task Instructions Section Verification

**Date:** January 5, 2025  
**Status:** ✅ Complete

---

## Summary

All Phase 0-2 task markdown files now have the complete "Instructions for Completing Tasks" section, matching the template from `tasks-authentication.md`.

---

## Files Updated

### Phase 0: Foundation
- ✅ `tasks-foundation-architecture.md` - Already had complete instructions
- ✅ `tasks-authentication.md` - Added **BLOCKING** section

### Phase 1: Core Experience
- ✅ `tasks-user-profile.md` - Added **BLOCKING** section
- ✅ `tasks-ride-requests.md` - Updated to full template (was missing BLOCKING and example)
- ✅ `tasks-favor-requests.md` - Added complete instructions section
- ✅ `tasks-request-claiming.md` - Added complete instructions section

### Phase 2: Communication
- ✅ `tasks-messaging.md` - Added complete instructions section
- ✅ `tasks-push-notifications.md` - Added complete instructions section
- ✅ `tasks-in-app-notifications.md` - Added complete instructions section

---

## Instructions Template

All files now include:

```markdown
## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.
```

---

## Verification

All Phase 0-2 task files have been verified to contain:
- ✅ Instructions header
- ✅ IMPORTANT section
- ✅ BLOCKING section
- ✅ QA RULES section (all 4 rules)
- ✅ Example section
- ✅ Update note

---

**Verification Complete:** January 5, 2025





