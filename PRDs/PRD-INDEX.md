# Naar's Cars iOS App - PRD Master Index

## Project Overview

**Application Name:** Naar's Cars  
**Platform:** iOS (SwiftUI)  
**Minimum iOS Version:** 17.0+  
**Backend:** Supabase (existing)  
**Migration From:** React/Next.js Web Application

---

## Executive Summary

This document serves as the master index for all Product Requirements Documents (PRDs) for rebuilding the Naar's Cars community ride-sharing application as a native iOS app using SwiftUI.

Naar's Cars is an invite-only community application for Seattle neighbors to share rides and exchange favors. The app facilitates:
- Ride requests (transportation needs)
- Favor requests (general help)
- Real-time messaging
- Community engagement (Town Hall, Leaderboards)
- Trust building (Reviews, Invite-only access)

---

## Development Phases

### Phase 0: Foundation (Must Complete First)
| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-foundation-architecture.md](./prd-foundation-architecture.md) | Project structure, Supabase setup, shared components | 2-3 weeks |
| [prd-authentication.md](./prd-authentication.md) | Signup, login, invite codes, session management | 1-2 weeks |

### Phase 1: Core Experience
| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-user-profile.md](./prd-user-profile.md) | Profile viewing, editing, avatar upload | 1 week |
| [prd-ride-requests.md](./prd-ride-requests.md) | Create, view, edit ride requests + Q&A | 1.5-2 weeks |
| [prd-favor-requests.md](./prd-favor-requests.md) | Create, view, edit favor requests + Q&A | 1 week |
| [prd-request-claiming.md](./prd-request-claiming.md) | Claiming, unclaiming, completing requests | 1 week |

### Phase 2: Communication
| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-messaging.md](./prd-messaging.md) | Real-time conversations, direct messages | 1.5-2 weeks |
| [prd-notifications-push.md](./prd-notifications-push.md) | APNs integration, notification types | 1 week |
| [prd-notifications-in-app.md](./prd-notifications-in-app.md) | Bell notifications, badges | 0.5 weeks |

### Phase 3: Community Features
| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-town-hall.md](./prd-town-hall.md) | Community forum posts | 0.5 weeks |
| [prd-reviews-ratings.md](./prd-reviews-ratings.md) | Post-completion reviews | 0.5 weeks |
| [prd-leaderboards.md](./prd-leaderboards.md) | Community rankings | 0.5 weeks |

### Phase 4: Administration
| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-admin-panel.md](./prd-admin-panel.md) | User approval, broadcasts | 0.5 weeks |
| [prd-invite-system.md](./prd-invite-system.md) | Invite code management | 0.5 weeks |

---

## Dependency Graph

```
prd-foundation-architecture
    â”‚
    â””â”€â”€ prd-authentication
            â”‚
            â”œâ”€â”€ prd-user-profile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
            â”‚       â”‚                                      â”‚
            â”‚       â””â”€â”€ prd-invite-system                  â”‚
            â”‚                                              â”‚
            â”œâ”€â”€ prd-ride-requests â”€â”€â”€â”€â”                    â”‚
            â”‚       â”‚                 â”‚                    â”‚
            â”œâ”€â”€ prd-favor-requests â”€â”€â”€â”¼â”€â”€ prd-request-claiming
            â”‚       â”‚                 â”‚         â”‚
            â”‚       â”‚                 â”‚         â”‚
            â”‚       â”‚                 â”‚         â”œâ”€â”€ prd-messaging
            â”‚       â”‚                 â”‚         â”‚       â”‚
            â”‚       â”‚                 â”‚         â”‚       â””â”€â”€ prd-notifications-push
            â”‚       â”‚                 â”‚         â”‚
            â”‚       â”‚                 â”‚         â””â”€â”€ prd-reviews-ratings
            â”‚       â”‚                 â”‚                 â”‚
            â”‚       â”‚                 â”‚                 â””â”€â”€ prd-town-hall
            â”‚       â”‚                 â”‚
            â”‚       â”‚                 â””â”€â”€ prd-leaderboards
            â”‚       â”‚
            â”‚       â””â”€â”€ prd-notifications-in-app
            â”‚
            â””â”€â”€ prd-admin-panel
```

---

## Timeline Estimate

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 0: Foundation | 3-5 weeks | 3-5 weeks |
| Phase 1: Core Experience | 4.5-6 weeks | 7.5-11 weeks |
| Phase 2: Communication | 3-3.5 weeks | 10.5-14.5 weeks |
| Phase 3: Community | 1.5 weeks | 12-16 weeks |
| Phase 4: Admin | 1 week | 13-17 weeks |
| Testing & Polish | 2-3 weeks | **15-20 weeks** |

**Total Estimated Duration:** 15-20 weeks (3.5-5 months)

---

## Technical Stack

### Required
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Minimum iOS:** 17.0
- **Backend:** Supabase (existing)
- **Package Manager:** Swift Package Manager

### Dependencies
| Package | Purpose |
|---------|---------|
| supabase-swift | Backend communication |

### Server-Side Requirements
- Supabase project (existing)
- APNs configuration for push notifications
- APNs authentication key from Apple Developer

---

## Key Data Models

| Model | Table | Description |
|-------|-------|-------------|
| Profile | profiles | User information |
| Ride | rides | Ride requests |
| Favor | favors | Favor requests |
| Message | messages | Chat messages |
| Conversation | conversations | Chat threads |
| AppNotification | notifications | In-app notifications |
| Review | reviews | User reviews |
| InviteCode | invite_codes | Invite codes |
| TownHallPost | town_hall_posts | Community posts |

---

## App Navigation Structure

```
App Launch
    â”‚
    â”œâ”€â”€ Unauthenticated
    â”‚   â”œâ”€â”€ LoginView
    â”‚   â””â”€â”€ SignupView (multi-step)
    â”‚
    â”œâ”€â”€ Pending Approval
    â”‚   â””â”€â”€ PendingApprovalView
    â”‚
    â””â”€â”€ Authenticated
        â””â”€â”€ MainTabView
            â”œâ”€â”€ Tab 1: Dashboard (Requests)
            â”‚   â”œâ”€â”€ RideDetailView
            â”‚   â”œâ”€â”€ FavorDetailView
            â”‚   â””â”€â”€ CreateRequestView
            â”‚
            â”œâ”€â”€ Tab 2: Messages
            â”‚   â”œâ”€â”€ ConversationListView
            â”‚   â””â”€â”€ ConversationDetailView
            â”‚
            â”œâ”€â”€ Tab 3: Notifications
            â”‚   â””â”€â”€ NotificationListView
            â”‚
            â”œâ”€â”€ Tab 4: Leaderboard
            â”‚   â””â”€â”€ LeaderboardView
            â”‚
            â””â”€â”€ Tab 5: Profile
                â”œâ”€â”€ MyProfileView
                â”œâ”€â”€ EditProfileView
                â”œâ”€â”€ PublicProfileView
                â””â”€â”€ AdminPanelView (admin only)
```

---

## Success Criteria

### MVP Release (End of Phase 2)
- [ ] Users can sign up with invite code
- [ ] Users can log in and stay logged in
- [ ] Users can create ride and favor requests
- [ ] Users can claim and unclaim requests
- [ ] Users can message each other
- [ ] Push notifications work
- [ ] App is stable with no critical bugs

### Full Release (End of Phase 4)
- [ ] All Phase 3 & 4 features complete
- [ ] Reviews and ratings functional
- [ ] Town Hall functional
- [ ] Leaderboards functional
- [ ] Admin panel functional
- [ ] App Store submission ready

---

## Getting Started

1. **Read Foundation PRD first** - Understand the project structure
2. **Set up Xcode project** - Follow Appendix A in foundation PRD
3. **Configure Supabase** - Add credentials to Secrets.swift
4. **Build Authentication** - Second PRD to implement
5. **Proceed through phases** - Follow dependency order

---

## Cost Summary

| Item | Cost |
|------|------|
| Apple Developer Account | $99/year |
| Supabase (if upgraded) | $0-25/month |
| Cursor Pro | $20/month |
| v0 Pro | $20/month |
| **Total First Year** | **~$500-800** |

---

## Phase 5: Future Enhancements

These features are documented and ready for implementation after the core app is stable.

| PRD | Description | Est. Effort |
|-----|-------------|-------------|
| [prd-apple-sign-in.md](./prd-apple-sign-in.md) | Social login via Apple ID | 1 week |
| [prd-biometric-auth.md](./prd-biometric-auth.md) | Face ID / Touch ID unlock | 0.5 weeks |
| [prd-dark-mode.md](./prd-dark-mode.md) | Dark mode theming support | 1 week |
| [prd-localization.md](./prd-localization.md) | Multi-language support | 2-3 weeks |
| [prd-location-autocomplete.md](./prd-location-autocomplete.md) | Google Places address autocomplete | 1 week |
| [prd-map-view.md](./prd-map-view.md) | Map view for browsing requests | 1-1.5 weeks |
| [prd-crash-reporting.md](./prd-crash-reporting.md) | Firebase Crashlytics integration | 0.5 weeks |

**Recommended for Launch:** Crash Reporting should be included in the initial release to monitor app stability.

---

## Open Items for Future Consideration

- Offline mode with local caching
- iPad support
- Analytics integration (Firebase Analytics)
- Widgets for iOS home screen
- Apple Watch companion app
- CarPlay integration

---

## Complete PRD List

### Phase 0: Foundation
1. `prd-foundation-architecture.md`
2. `prd-authentication.md`

### Phase 1: Core Experience
3. `prd-user-profile.md`
4. `prd-ride-requests.md`
5. `prd-favor-requests.md`
6. `prd-request-claiming.md`

### Phase 2: Communication
7. `prd-messaging.md`
8. `prd-notifications-push.md`
9. `prd-notifications-in-app.md`

### Phase 3: Community Features
10. `prd-town-hall.md`
11. `prd-reviews-ratings.md`
12. `prd-leaderboards.md`

### Phase 4: Administration
13. `prd-admin-panel.md`
14. `prd-invite-system.md`

### Phase 5: Future Enhancements
15. `prd-apple-sign-in.md`
16. `prd-biometric-auth.md`
17. `prd-dark-mode.md`
18. `prd-localization.md`
19. `prd-location-autocomplete.md`
20. `prd-map-view.md`
21. `prd-crash-reporting.md`

**Total: 21 PRDs**

---

*Last Updated: January 2025*
