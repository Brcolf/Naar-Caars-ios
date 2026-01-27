# Naar's Cars iOS App

Native iOS application for the Naar's Cars community ride-sharing platform.

---

## 🚗 About

Naar's Cars is an invite-only community platform for neighbors to help each other with rides and favors. This repository contains the native iOS application built with SwiftUI and Supabase.

---

## 📁 Project Structure

```
naars-cars-ios/
├── docs/
│   ├── PRDs/              # Product Requirements Documents (21 features)
│   ├── Tasks/             # Detailed task breakdowns for implementation
│   └── QA/                # Quality assurance framework and checkpoints
│
├── database/              # Database setup files
│   ├── migrations/        # SQL migration files (generated in Phase 0)
│   └── DATABASE-INFO.md   # Supabase credentials (created, not committed)
│
├── NaarsCars/             # iOS Xcode project (created in Phase 1)
│   ├── App/               # Application entry point
│   ├── Features/          # Feature modules (Auth, Rides, Favors, etc.)
│   ├── Core/              # Services, Models, Extensions, Utilities
│   ├── UI/                # Reusable UI components and styles
│   └── Resources/         # Assets, localization, Info.plist
│
├── NaarsCarsTests/        # Unit and integration tests
│
├── SECURITY.md            # Security requirements and RLS policies
├── PRIVACY-DISCLOSURES.md # Privacy requirements for App Store
└── README.md              # This file
```

---

## 🏗️ Technology Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Architecture:** MVVM (Model-View-ViewModel)
- **Backend:** Supabase (PostgreSQL + Realtime + Auth + Storage)
- **Minimum iOS:** 17.0
- **Development Tool:** Xcode 16+ and Cursor IDE

---

## 🚀 Getting Started

### Prerequisites

- **macOS Sonoma 14.0+** (required for Xcode 16)
- **Xcode 16+** (latest stable version)
- **Cursor IDE** (for AI-assisted development)
- **Supabase Account** (free tier is fine for development)
- **Apple Developer Account** ($99/year - required for TestFlight/App Store)

### Secrets Setup (Required for Build)

1. Copy `NaarsCars/Core/Utilities/Secrets.swift.template` to `NaarsCars/Core/Utilities/Secrets.swift`.
2. Run `NaarsCars/Scripts/obfuscate.swift` to generate obfuscated byte arrays for the Supabase URL and anon key.
3. Paste the generated arrays into `Secrets.swift`.

`Secrets.swift` is gitignored and must be created locally for builds.

### ⚠️ CRITICAL: Database-First Approach

**This project uses a database-first development approach. You MUST complete Phase 0 (Database Setup) before creating the iOS project in Phase 1.**

**Workflow:**
1. ✅ Phase 0: Set up Supabase database schema (1 week)
2. ✅ Phase 1: Create iOS Xcode project (2-3 weeks)
3. ✅ Phases 2+: Build features against verified database

**DO NOT skip Phase 0.** Building the iOS app without a correct database will cause bugs and wasted time.

---

## 📋 Development Phases

### Phase 0: Database Setup (⛔ START HERE)

**Estimated Time:** 1 week (3-5 days if focused)

**Tasks:**
1. Create new Supabase project
2. Use Cursor to generate SQL migration files
3. Apply migrations to create all 16 database tables
4. Set up Row Level Security (RLS) policies
5. Create database functions and triggers
6. Seed test data
7. Verify schema with test queries

**Start here:** `docs/Tasks/tasks-foundation-architecture.md` → Task 0.1

**Completion Criteria:** Pass QA-DATABASE-FINAL checkpoint

---

### Phase 1: iOS Foundation (After Phase 0)

**Estimated Time:** 2-3 weeks

**Tasks:**
1. Create Xcode project
2. Set up folder structure
3. Install Supabase Swift SDK
4. Connect to database from Phase 0
5. Build core services and models
6. Create reusable UI components
7. Set up navigation architecture

**Start here:** `docs/Tasks/tasks-foundation-architecture.md` → Task 1.1

**Completion Criteria:** Pass QA-FOUNDATION-001 checkpoint

---

### Phase 2: Authentication

**Estimated Time:** 1.5 weeks

**Features:**
- Email/password signup with invite codes
- Login and logout
- Session persistence
- Biometric authentication (Face ID/Touch ID)
- Apple Sign-In

**Start here:** `docs/Tasks/tasks-authentication.md`

---

### Phase 3: Core Features

**Estimated Time:** 3-4 weeks

**Features:**
- User profiles
- Ride requests (create, view, claim)
- Favor requests (create, view, claim)
- Request claiming workflow
- User reviews and ratings

**Task Lists:**
- `docs/Tasks/tasks-user-profile.md`
- `docs/Tasks/tasks-ride-requests.md`
- `docs/Tasks/tasks-favor-requests.md`
- `docs/Tasks/tasks-request-claiming.md`
- `docs/Tasks/tasks-reviews-ratings.md`

---

### Phase 4: Communication

**Estimated Time:** 2-3 weeks

**Features:**
- Real-time messaging
- Push notifications
- In-app notifications
- Request Q&A (public questions on posts)

**Task Lists:**
- `docs/Tasks/tasks-messaging.md`
- `docs/Tasks/tasks-push-notifications.md`
- `docs/Tasks/tasks-in-app-notifications.md`

---

### Phase 5: Community

**Estimated Time:** 2 weeks

**Features:**
- Town Hall (community forum)
- Leaderboards (gamification)
- Invite system

**Task Lists:**
- `docs/Tasks/tasks-town-hall.md`
- `docs/Tasks/tasks-leaderboards.md`
- `docs/Tasks/tasks-invite-system.md`

---

### Phase 6: Administration & Polish

**Estimated Time:** 2-3 weeks

**Features:**
- Admin panel
- Dark mode
- Localization
- Location autocomplete
- Map view
- Crash reporting

**Task Lists:**
- `docs/Tasks/tasks-admin-panel.md`
- `docs/Tasks/tasks-dark-mode.md`
- `docs/Tasks/tasks-localization.md`
- `docs/Tasks/tasks-location-autocomplete.md`
- `docs/Tasks/tasks-map-view.md`
- `docs/Tasks/tasks-crash-reporting.md`

---

## 📖 Documentation

### Key Documents

| Document | Purpose |
|----------|---------|
| `docs/PRDs/PRD-INDEX.md` | Master index of all features |
| `docs/Tasks/TASK-LISTS-SUMMARY.md` | Summary of all tasks (~1,880 total) |
| `docs/QA/CHECKPOINT-GUIDE.md` | How to run quality checkpoints |
| `docs/QA/FLOW-CATALOG.md` | All 27 user flows for testing |
| `docs/QA/QA-RUNNER-INSTRUCTIONS.md` | Cursor-specific QA guide |
| `SECURITY.md` | Security requirements and RLS policies |
| `PRIVACY-DISCLOSURES.md` | Privacy requirements for App Store |
| `Legal/PRIVACY_POLICY.md` | Draft Privacy Policy (must be hosted for App Store submission) |
| `Legal/TERMS_OF_SERVICE.md` | Draft Terms of Service (must be hosted and linked in-app) |

### Understanding the Task System

Each feature has:
1. **PRD** (Product Requirements Document) - What to build and why
2. **Task List** - Step-by-step implementation checklist
3. **Checkpoints** - Mandatory quality gates marked with 🔒

**Example workflow:**
1. Read `docs/PRDs/prd-authentication.md` to understand the feature
2. Follow `docs/Tasks/tasks-authentication.md` checklist
3. Check off each task as you complete it (`- [ ]` → `- [x]`)
4. When you hit a 🔒 CHECKPOINT, run the verification script
5. Fix any issues before continuing

---

## 🔧 Development Workflow

### Using Cursor for Development

This project is designed to work with Cursor IDE for AI-assisted development.

**Typical Cursor usage:**
1. Open task file (e.g., `tasks-authentication.md`)
2. Find next unchecked task (e.g., Task 2.3)
3. Press `Cmd+I` to open Cursor Composer
4. Paste task description + file path from task list
5. Review generated code
6. Run tests (if applicable)
7. Check off task (`- [x]`)
8. Commit to git

**Example Cursor prompt:**
```
Implement Task 2.3 from docs/Tasks/tasks-authentication.md:

Create LoginViewModel.swift in Features/Authentication/ViewModels/

Requirements:
- @MainActor and ObservableObject
- @Published properties for email, password, isLoading, errorMessage
- loginWithEmail() async function
- Use AuthService.shared for actual login
- Follow MVVM pattern from prd-foundation-architecture.md
```

### Running Checkpoints

At each 🔒 CHECKPOINT in task lists:

```bash
# Stop coding
# Run the checkpoint script
./docs/QA/Scripts/checkpoint.sh <checkpoint-id>

# Example:
./docs/QA/Scripts/checkpoint.sh foundation-001

# Fix any failures
# Only continue when checkpoint passes
```

**Never skip checkpoints.** They catch bugs early.

---

## 🎯 Current Status

Track your progress here:

- [ ] **Phase 0: Database Setup**
  - [ ] Task 0.1 - 0.10 (Database creation)
  - [ ] QA-DATABASE-FINAL checkpoint passed

- [ ] **Phase 1: iOS Foundation**
  - [ ] Task 1.0 - 1.9 (Xcode project setup)
  - [ ] Task 2.0 - 2.13 (Supabase SDK)
  - [ ] Task 3.0 - 3.12 (Core models)
  - [ ] Task 4.0 - 4.6 (Services)
  - [ ] Task 5.0+ (App state, navigation, UI)
  - [ ] QA-FOUNDATION-001 checkpoint passed

- [ ] **Phase 2: Authentication**
  - [ ] Login/Signup
  - [ ] Session management
  - [ ] Biometric auth
  - [ ] Apple Sign-In

- [ ] **Phase 3: Core Features**
  - [ ] User profiles
  - [ ] Ride requests
  - [ ] Favor requests
  - [ ] Request claiming
  - [ ] Reviews & ratings

- [ ] **Phase 4: Communication**
  - [ ] Messaging
  - [ ] Push notifications
  - [ ] In-app notifications

- [ ] **Phase 5: Community**
  - [ ] Town Hall
  - [ ] Leaderboards
  - [ ] Invite system

- [ ] **Phase 6: Administration & Polish**
  - [ ] Admin panel
  - [ ] Dark mode
  - [ ] Localization
  - [ ] Maps & location
  - [ ] Crash reporting

- [ ] **Release**
  - [ ] TestFlight beta
  - [ ] App Store submission
  - [ ] Launch! 🚀

---

## 🔒 Security & Privacy

### Security

All security requirements are documented in `SECURITY.md`, including:
- Row Level Security (RLS) policies for all database tables
- Authentication and authorization rules
- Data encryption requirements
- API key management
- Secure credential storage

**Key security practices:**
- Never commit `Secrets.swift` to git
- Never commit `database/DATABASE-INFO.md` to git
- Use RLS policies to protect all data
- Use biometric authentication where possible
- Implement rate limiting for API calls

### Privacy

Privacy requirements for App Store compliance are in `PRIVACY-DISCLOSURES.md`:
- Required privacy labels
- Data collection disclosures
- User consent flows
- Data retention policies

---

## 📊 Estimated Timeline

**With 25 hours/week of focused development:**

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 0: Database | 1 week | 1 week |
| Phase 1: Foundation | 2-3 weeks | 3-4 weeks |
| Phase 2: Authentication | 1.5 weeks | 4.5-5.5 weeks |
| Phase 3: Core Features | 3-4 weeks | 7.5-9.5 weeks |
| Phase 4: Communication | 2-3 weeks | 9.5-12.5 weeks |
| Phase 5: Community | 2 weeks | 11.5-14.5 weeks |
| Phase 6: Polish | 2-3 weeks | 13.5-17.5 weeks |
| **Total to TestFlight** | **14-18 weeks** | **~4 months** |
| App Store Review | 1-2 weeks | 15-20 weeks |
| **Total to Launch** | **~4-5 months** | **~5 months** |

**Note:** This assumes:
- Following tasks in order
- Not skipping checkpoints
- Learning as you go (first SwiftUI project)
- Using Cursor for code generation
- 25 hours/week dedicated time

---

## 💰 Costs

### Development (First 6 Months)

| Item | Cost | When |
|------|------|------|
| Apple Developer | $99/year | Before TestFlight |
| Supabase Pro | $25/month | Month 4+ (testing) |
| Firebase | $10-25/month | Month 4+ (push notifications) |
| Google Places API | $10-30/month | Month 5+ (location features) |
| Cursor Pro | $20/month | Optional (recommended) |
| **Total First 6 Months** | **$391-443** | - |

### Ongoing (After Launch)

| Item | Annual Cost |
|------|-------------|
| Apple Developer | $99/year |
| Supabase Pro | $300/year |
| Firebase | $120-300/year |
| Google Places API | $120-360/year |
| **Total Annual** | **$639-1,299/year** |

Scales with user count. Free tiers available for development and early users.

---

## 🐛 Troubleshooting

### Common Issues

**"Database connection failed"**
- Check Secrets.swift has correct Supabase URL and key
- Verify Supabase project is running
- Check network connection

**"RLS policy error"**
- Ensure you're logged in as an approved user
- Check RLS policies were applied in Phase 0
- Run verification queries from `database/migrations/verify_schema.sql`

**"Checkpoint script failed"**
- Read the error message carefully
- Fix the specific test that's failing
- Re-run the checkpoint script
- Never skip checkpoints even if tempted

**"Cursor generated wrong code"**
- Make sure you're referencing the correct PRD and task
- Be more specific in your prompt
- Include file paths and exact requirements
- Review generated code before accepting

**"Too many files in task list"**
- Focus on ONE task at a time
- Don't try to implement entire features at once
- Check off tasks as you go
- Commit after each task or small group of tasks

---

## 🤝 Contributing

This is a personal project, but if you're collaborating:

1. Always work in feature branches
2. Follow the task lists exactly
3. Never skip checkpoints
4. Run tests before committing
5. Write clear commit messages
6. Keep PRDs and tasks updated

---

## 📜 License

[Your License Here - e.g., MIT, Private, etc.]

---

## 📞 Support

For questions about:
- **PRDs and requirements:** See `docs/PRDs/`
- **Implementation tasks:** See `docs/Tasks/`
- **Quality assurance:** See `docs/QA/CHECKPOINT-GUIDE.md`
- **Database setup:** See Phase 0 tasks in `docs/Tasks/tasks-foundation-architecture.md`

---

## ✅ Quick Start Checklist

Before you begin:

- [ ] macOS Sonoma 14.0+ installed
- [ ] Xcode 16+ installed
- [ ] Cursor IDE installed
- [ ] Supabase account created
- [ ] All documentation files in `docs/` folder
- [ ] SECURITY.md and PRIVACY-DISCLOSURES.md present
- [ ] Read this README completely
- [ ] Ready to commit 25+ hours/week

**Then start here:**
1. Open `docs/Tasks/tasks-foundation-architecture.md`
2. Begin with **Task 0.1** (Create Supabase Project)
3. Work through Phase 0 completely
4. Pass QA-DATABASE-FINAL checkpoint
5. THEN proceed to Phase 1 (Xcode project)

---

**Good luck building Naar's Cars! 🚗💨**

---

*Last Updated: January 2026*
