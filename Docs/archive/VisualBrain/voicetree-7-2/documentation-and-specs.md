---
color: blue
position:
  x: -241
  y: -982
isContextNode: false
agent_name: Amy
---

# Documentation & Specifications

Project documentation, specs, and planning artifacts.

## Root Documentation

### README.md
Project overview, setup instructions, architecture summary.

### SECURITY.md
Security policies, vulnerability reporting, secure coding practices.

### AGENTS.md
AI agent guidelines for working with the codebase.

## Docs/

### Audit & Analysis Documents

**STRUCTURAL_HANDOFF_AUDIT.md**
Comprehensive architecture audit covering:
- System architecture & data flow
- State management & auth lifecycle
- Critical red flags & technical debt
- Performance bottlenecks
- Recent improvements
- Recommendations for architect

**REQUESTS-MODULE-BROKEN-STATE-REPORT.md**
Deep dive into rides/favors claiming bug:
- Root cause analysis (RLS policies)
- User flow tracing
- Error handling gaps
- Clarifying questions
- Recommended fixes

**IMESSAGE_PARITY_AUDIT.md**
Comparison of messaging features vs iMessage:
- Feature parity checklist
- Missing features
- UX gaps

**COMPREHENSIVE_FIX_SUMMARY.md**
Summary of February 2026 comprehensive fix pass:
- Messaging bugs resolved
- Performance improvements
- Database optimizations
- Remaining issues

### Implementation Plans

**PERFORMANCE-AND-RELIABILITY-IMPLEMENTATION-PLAN.md**
Plan for addressing performance issues:
- Badge count optimization
- Message sorting optimization
- Sync engine improvements

**MESSAGING-LOAD-JUMPINESS-EXECUTION-PLAN.md**
Specific plan for fixing message list scroll jumpiness.

**MESSAGING-MESSAGE-VIEW-SCROLL-AND-KEYBOARD-PLAN.md**
Plan for keyboard handling and scroll behavior in messaging.

**MESSAGING-UICOLLECTIONVIEW-REVIEW.md**
Review of custom UICollectionView implementation for messages.

### Architectural Reviews

**plans/2026-02-06-ride-estimated-cost-retry-design.md**
Design doc for cost estimation retry logic.

## PRDs/
Product Requirements Documents:
- Feature specifications
- User stories
- Acceptance criteria
- API contracts

## Tasks/
Task tracking:
- Sprint plans
- Feature breakdown
- Bug tracking
- Technical debt items

## Legal/
Legal documentation:
- Terms of Service
- Privacy Policy
- Data handling policies

## Scripts/
Helper scripts:
- Database migration runners
- Code generation
- Cleanup scripts
- **clean_localizable_catalog.py** - Cleanup unused localization strings

## NaarsCars Documentation

### App-Level Docs

**ADD-FILES-TO-XCODE.md**
Guide for adding new files to Xcode project.

**FIX-XCODE-FILES.md**
Instructions for fixing Xcode project file issues.

**FIX-DUPLICATE-FILES.md**
Cleanup guide for duplicate file references.

**VERIFY-FILES-ADDED.md**
Checklist to verify new files are properly integrated.

**DATABASE_FIX_GUIDE.md**
Database troubleshooting guide.

**DATABASE_FIX_RLS_POLICIES.sql**
SQL fixes for RLS policies.

**CLEANUP_SUMMARY.md**
Summary of code cleanup efforts.

**WARNING_FIXES_REPORT.md**
Report on compiler warning fixes.

**MISSING-FILES-REPORT.txt**
List of missing files that need to be created/found.

**PROFILE-FILES-TO-ADD.md**
Files to add for profile feature.

**TASK-6.0-STATUS.md**
Status update for major task/sprint.

**MESSAGING-REVIEW-AND-PLAN.md** (root)
Comprehensive messaging review and improvement plan.

## Documentation Quality

### ✅ Strengths
- Comprehensive audit documents
- Detailed problem analysis
- Clear implementation plans
- Technical debt tracking

### 🟡 Gaps
- API documentation (service methods not documented)
- Architecture decision records (ADRs) would help
- Runbook for common issues
- Onboarding guide for new developers

## Recommended Documentation

### To Add
1. **CONTRIBUTING.md** - How to contribute code
2. **ARCHITECTURE.md** - High-level architecture overview
3. **API.md** - Document all service methods
4. **TROUBLESHOOTING.md** - Common issues and solutions
5. **ADRs/** - Architecture Decision Records for major choices

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
