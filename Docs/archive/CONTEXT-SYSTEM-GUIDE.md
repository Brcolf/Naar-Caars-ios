# Context Management System - Quick Guide

**Purpose:** Systematically work through the Naar's Cars iOS build with clear tracking, dependencies, and progress management.

---

## 📁 System Files

### 1. BUILD-CONTEXT.md
**Purpose:** Your primary navigation tool - shows current focus, status, and next steps.

**Use When:**
- Starting work for the day
- Checking what to work on next
- Understanding current build status
- Finding blockers

**Key Sections:**
- 🎯 Current Focus - What you're working on now
- 📊 Build Status Overview - High-level phase status
- 🚨 Critical Blockers - Must-fix items
- 📋 Phase Breakdown - Detailed phase information
- 🔒 QA Checkpoint Status - Test status

### 2. PROGRESS-TRACKER.md
**Purpose:** Detailed task-by-task progress tracking for all 21 PRDs.

**Use When:**
- Tracking individual task completion
- Seeing detailed progress within a PRD
- Understanding what's been done
- Planning work breakdown

**Key Sections:**
- Overall statistics
- Phase-by-phase task breakdown
- Checkpoint tracking
- Progress visualization

### 3. DEPENDENCY-MAP.md
**Purpose:** Visual representation of what depends on what.

**Use When:**
- Starting a new feature
- Understanding why something is blocked
- Finding parallel work opportunities
- Resolving dependency issues

**Key Sections:**
- Phase dependencies (visual)
- PRD dependency graph
- Critical path dependencies
- Parallel work opportunities

---

## 🚀 Daily Workflow

### Morning Routine
1. **Open BUILD-CONTEXT.md**
   - Check "Current Focus" section
   - Review "Immediate Next Steps"
   - Check for blockers

2. **Open Current Task List**
   - Navigate to the task list file
   - Review current task
   - Understand requirements

3. **Begin Work**
   - Update BUILD-CONTEXT.md if starting new task
   - Work through task list
   - Mark tasks complete as you go

### During Work
1. **Complete a Task**
   - Mark checkbox in task list
   - Update PROGRESS-TRACKER.md if significant
   - Continue to next task

2. **Hit a Checkpoint**
   - STOP work
   - Run checkpoint script
   - Fix any failures
   - Mark checkpoint as passed
   - Update BUILD-CONTEXT.md
   - Continue

3. **Complete a PRD**
   - Mark all tasks complete
   - Run final checkpoint
   - Update BUILD-CONTEXT.md (mark PRD complete)
   - Update PROGRESS-TRACKER.md
   - Check DEPENDENCY-MAP.md for next work

### End of Day
1. **Update Context Files**
   - Mark current task status
   - Update progress percentages
   - Note any blockers or issues

2. **Plan Tomorrow**
   - Review next steps in BUILD-CONTEXT.md
   - Identify any blockers
   - Prepare for next checkpoint if close

---

## 🎯 Starting a New Feature

### Step 1: Check Dependencies
1. Open DEPENDENCY-MAP.md
2. Find your feature
3. Check "Depends On" column
4. Verify all dependencies are complete in BUILD-CONTEXT.md

### Step 2: Update Context
1. Open BUILD-CONTEXT.md
2. Mark feature as "In Progress"
3. Update "Current Focus" section
4. Update "Immediate Next Steps"

### Step 3: Read Documentation
1. Read the PRD (in PRDs/ folder)
2. Read the task list (in Tasks/ folder)
3. Understand requirements and flows

### Step 4: Begin Work
1. Start with first task in task list
2. Work sequentially
3. Mark tasks complete
4. Run checkpoints when encountered

---

## 🔒 Checkpoint Workflow

### When You Hit a Checkpoint

1. **STOP** - Do not proceed to next task

2. **RUN** - Execute checkpoint:
   ```bash
   ./QA/Scripts/checkpoint.sh [checkpoint-id]
   ```
   Example:
   ```bash
   ./QA/Scripts/checkpoint.sh foundation-001
   ```

3. **REVIEW** - Check results:
   - ✅ All tests pass → Continue
   - ❌ Tests fail → Fix issues

4. **FIX** - If tests fail:
   - Read error messages
   - Fix issues
   - Re-run checkpoint
   - Repeat until all pass

5. **UPDATE** - Mark checkpoint as passed:
   - Update BUILD-CONTEXT.md checkpoint status
   - Update PROGRESS-TRACKER.md
   - Mark as ✅ PASSED

6. **CONTINUE** - Proceed to next task

### Never Skip Checkpoints
- ⛔ Checkpoints are mandatory quality gates
- ⛔ Cannot proceed without passing
- ⛔ Critical checkpoints block production

---

## 📊 Progress Updates

### When to Update Files

**BUILD-CONTEXT.md:**
- Starting a new task/PRD/phase
- Completing a task/PRD/phase
- Hitting a blocker
- Passing a checkpoint
- Changing current focus

**PROGRESS-TRACKER.md:**
- Completing individual tasks
- Completing a PRD
- Passing checkpoints
- Weekly progress reviews

**DEPENDENCY-MAP.md:**
- Usually static (dependencies don't change)
- Update if architecture changes
- Reference when starting new work

---

## 🚨 Handling Blockers

### Identify Blocker
1. Check BUILD-CONTEXT.md "Critical Blockers" section
2. Check DEPENDENCY-MAP.md for dependencies
3. Understand why you're blocked

### Resolve Blocker
1. Work on blocking task/PRD first
2. Complete blocking work
3. Run any required checkpoints
4. Mark blocker as resolved

### Unblock Feature
1. Update BUILD-CONTEXT.md
2. Mark feature as "In Progress"
3. Begin work on feature

---

## 🔍 Quick Reference

### "What should I work on?"
→ Check BUILD-CONTEXT.md "Current Focus" section

### "Is this feature blocked?"
→ Check DEPENDENCY-MAP.md dependency matrix

### "What's the progress?"
→ Check PROGRESS-TRACKER.md for detailed stats

### "What's next?"
→ Check BUILD-CONTEXT.md "Immediate Next Steps"

### "Can I work on this in parallel?"
→ Check DEPENDENCY-MAP.md "Parallel Work Opportunities"

### "What checkpoints are pending?"
→ Check BUILD-CONTEXT.md "QA Checkpoint Status"

---

## 📝 Best Practices

### Do's ✅
- ✅ Update context files regularly
- ✅ Check dependencies before starting work
- ✅ Never skip checkpoints
- ✅ Mark tasks complete as you go
- ✅ Update progress after completing PRDs
- ✅ Reference DEPENDENCY-MAP when starting new features

### Don'ts ❌
- ❌ Skip updating context files
- ❌ Start work without checking dependencies
- ❌ Skip checkpoints
- ❌ Work on blocked features
- ❌ Forget to mark tasks complete
- ❌ Proceed past failed checkpoints

---

## 🎓 Example Workflow

### Example: Starting Foundation Architecture

1. **Check BUILD-CONTEXT.md**
   - Current Focus: Phase 0, Foundation Architecture
   - Next Step: Task 0.0 - Database Setup

2. **Check DEPENDENCY-MAP.md**
   - Foundation Architecture has no dependencies ✅
   - Can start immediately ✅

3. **Read Documentation**
   - Read `PRDs/prd-foundation-architecture.md`
   - Read `Tasks/tasks-foundation-architecture.md`

4. **Start Work**
   - Update BUILD-CONTEXT.md: Mark as "In Progress"
   - Begin Task 0.0: Create Supabase project
   - Complete task, mark checkbox

5. **Continue**
   - Work through tasks 0.1, 0.2, etc.
   - Mark complete as you go

6. **Hit Checkpoint**
   - Task says: "🔒 CHECKPOINT: QA-FOUNDATION-001"
   - STOP work
   - Run: `./QA/Scripts/checkpoint.sh foundation-001`
   - Fix any failures
   - Mark checkpoint as ✅ PASSED
   - Update BUILD-CONTEXT.md
   - Continue

7. **Complete PRD**
   - All tasks complete
   - All checkpoints passed
   - Update BUILD-CONTEXT.md: Mark PRD as complete
   - Update PROGRESS-TRACKER.md
   - Move to next PRD (Authentication)

---

## 🔗 Related Documentation

- [PRD Index](./PRDs/PRD-INDEX.md) - All 21 PRDs
- [Task Lists Summary](./Tasks/TASK-LISTS-SUMMARY.md) - All task lists
- [QA Flow Catalog](./QA/FLOW-CATALOG.md) - User flows
- [Checkpoint Guide](./QA/CHECKPOINT-GUIDE.md) - How to run checkpoints
- [Security Requirements](./SECURITY.md) - Security docs
- [Privacy Disclosures](./PRIVACY-DISCLOSURES.md) - Privacy docs

---

**Remember:** The context management system is your guide. Keep it updated, and it will keep you on track! 🚀

