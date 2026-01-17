# Messaging Workflows - Complete Requirements

## Overview
This document outlines all messaging workflows and their implementation requirements.

## Workflow 1: Request-Based Conversations

### When Created
- When a ride or favor request is **claimed**
- "Message all participants" button appears on claim cards

### Participants
- Request creator (poster)
- Claimer
- All co-requestors (if any)
- Any participants added to the request later

### Auto-Add Logic
- When a participant is added to a request (ride_participants or favor_participants), they are automatically added to the existing conversation for that request

### Implementation
1. **MessageService method**: `createOrGetRequestConversation(rideId: UUID?, favorId: UUID?, createdBy: UUID) async throws -> Conversation`
2. **UI**: "Message all participants" button on claim cards (RideCard, FavorCard)
3. **Auto-add trigger**: When participants are added to requests, check for existing conversation and add them

## Workflow 2: Direct Messages

### When Created
- From "Message user" button on profile page
- From "New message" button in messages list

### Participants
- Initially: Two users
- Can be expanded: Either participant can add more users to create a group chat

### Implementation
1. **MessageService method**: `getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation` (already exists)
2. **UI**: "Message user" button on PublicProfileView (already exists)
3. **UI**: "New message" button in ConversationsListView with searchable user dropdown

## Workflow 3: Group Chats

### When Created
- From direct message: Either participant can add more users
- From new message: User selects multiple users from dropdown

### Participants
- Initial participants
- Any user added by existing participants

### Implementation
1. **MessageService method**: `addParticipantsToConversation(conversationId: UUID, userIds: [UUID], addedBy: UUID) async throws`
2. **UI**: "Add participants" button in ConversationDetailView
3. **UI**: User search/selection interface

## Workflow 4: New Message Creation

### When Created
- From messages interface header
- Searchable dropdown to select users

### Implementation
1. **UI**: "New message" button in ConversationsListView header
2. **UI**: User search modal/sheet with searchable dropdown
3. **MessageService**: Use `getOrCreateDirectConversation` or create new group conversation

## Database Schema Requirements

### conversations table
- `id` UUID PRIMARY KEY
- `ride_id` UUID NULLABLE (links to ride request)
- `favor_id` UUID NULLABLE (links to favor request)
- `created_by` UUID (conversation creator)
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ

### conversation_participants table
- `id` UUID PRIMARY KEY
- `conversation_id` UUID (FK to conversations)
- `user_id` UUID (FK to profiles)
- `is_admin` BOOLEAN (creator is admin)
- `joined_at` TIMESTAMPTZ

## RLS Policy Requirements

### conversations
- SELECT: User is creator OR user is participant
- INSERT: Approved users can create conversations
- UPDATE: Only creator can update

### conversation_participants
- SELECT: User can see their own participation rows
- INSERT: User can add themselves OR be added by:
  - Conversation creator
  - Request creator (if conversation linked to their request)
  - Existing participants (for group chats)
- UPDATE: User can update their own participation
- DELETE: User can remove their own participation

### messages
- SELECT: User is participant in conversation
- INSERT: User is sender AND participant in conversation

## Implementation Checklist

### Database
- [x] Fix RLS policies (021_complete_messaging_rls_fix.sql)
- [ ] Verify policies support all workflows

### MessageService
- [x] `getOrCreateDirectConversation` (exists)
- [ ] `createOrGetRequestConversation(rideId: UUID?, favorId: UUID?, createdBy: UUID)`
- [ ] `addParticipantsToConversation(conversationId: UUID, userIds: [UUID], addedBy: UUID)`
- [ ] `findExistingRequestConversation(rideId: UUID?, favorId: UUID?)`
- [ ] Helper: `addParticipantsToRequestConversation` (auto-add when participants added to request)

### UI Components
- [x] "Message user" button on PublicProfileView (exists)
- [ ] "Message all participants" button on RideCard (when claimed)
- [ ] "Message all participants" button on FavorCard (when claimed)
- [ ] "New message" button in ConversationsListView header
- [ ] User search modal/sheet component
- [ ] "Add participants" button in ConversationDetailView
- [ ] Participants list in ConversationDetailView header

### Integration Points
- [ ] When ride is claimed, create/get conversation
- [ ] When favor is claimed, create/get conversation
- [ ] When participant added to ride, add to conversation
- [ ] When participant added to favor, add to conversation



