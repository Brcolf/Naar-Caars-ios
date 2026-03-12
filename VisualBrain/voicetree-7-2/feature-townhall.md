---
color: purple
position:
  x: -768
  y: -950
isContextNode: false
agent_name: Amy
---

# Feature: Town Hall

Community forum with posts, comments, and voting.

## Views
- **TownHallView.swift** - Feed of community posts
- **TownHallPostDetailView.swift** - Post with comments thread
- **CreateTownHallPostView.swift** - New post composer
- **TownHallCommentRow.swift** - Comment display with replies

## ViewModels
- **TownHallViewModel.swift** - Load posts, voting, sorting
- **TownHallPostDetailViewModel.swift** - Post detail with comments
- **CreateTownHallPostViewModel.swift** - Post creation

## Services
- **TownHallService.swift** - CRUD for posts
- **TownHallCommentService.swift** - Comments with threading
- **TownHallVoteService.swift** - Upvote/downvote logic

## Models
- **TownHallPost.swift** - Post content, vote counts, comment counts
- **TownHallComment.swift** - Comments with parent_id for threading
- **TownHallVote.swift** - User votes (upvote/downvote)

## Storage
- **TownHallRepository.swift** - SwiftData cache for posts
- **TownHallSyncEngine.swift** - Realtime sync from Supabase

## Features

### Posts
- Create text posts with optional title extraction
- Markdown-style formatting support
- Vote on posts (upvote/downvote)
- Sort by hot, new, top

### Comments
- Threaded comment system
- Reply to comments (nested)
- Vote on comments
- Edit/delete own comments

### Voting
- Upvote/downvote posts and comments
- Net score calculation
- Vote affects leaderboard reputation

### Real-Time Updates
`TownHallSyncEngine` subscribes to Supabase Realtime:
- New posts appear automatically
- Vote counts update live
- Comment counts update live

## UI Patterns

Similar to Reddit/HackerNews:
- Collapsible comment threads
- Vote arrows with score display
- Time ago timestamps
- User attribution

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
