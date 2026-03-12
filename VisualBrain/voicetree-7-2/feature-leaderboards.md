---
color: gold
position:
  x: -48
  y: -1532
isContextNode: false
agent_name: Amy
---

# Feature: Leaderboards

Gamification and user reputation rankings.

## Views
- **LeaderboardView.swift** - Rankings list with tabs
- **LeaderboardRowView.swift** - User rank display with stats

## ViewModels
- **LeaderboardViewModel.swift** - Fetch and display rankings

## Services
- **LeaderboardService.swift** - Fetch leaderboard data from database

## Models
- **LeaderboardEntry.swift** - User ranking with points/completed requests

## Ranking Criteria

### Points System
Points are earned from:
- Completing ride/favor requests
- Receiving 5-star reviews
- Community contributions (Town Hall posts/comments)
- Helping other users

### Leaderboard Types
1. **All-Time** - Total lifetime points
2. **Monthly** - Points this month
3. **Weekly** - Points this week

## Implementation

Database view or query aggregates:
- Completed requests count
- Average review rating
- Town Hall karma
- Other engagement metrics

Top users displayed with:
- Rank (#1, #2, #3, etc.)
- Avatar
- Name
- Points/stats
- Badges (top helper, most reliable, etc.)

## Gamification Elements

### Badges (Implied)
- 🌟 Top Helper
- 🚗 Ride Master
- 💬 Community Champion
- ⭐ 5-Star Rated

### Motivation
Leaderboards encourage:
- Helping community members
- Quality service (good reviews)
- Active participation
- Reliability (completing claims)

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
