---
color: purple
position:
  x: -504
  y: -982
isContextNode: false
agent_name: Amy
---

# Architecture Overview Diagram

Visual representation of the NaarsCars iOS architecture.

## System Architecture

```mermaid
graph TB
    subgraph "iOS App"
        UI[SwiftUI Views]
        VM[ViewModels]
        SVC[Services Layer]
        SD[SwiftData Cache]
        SYNC[Sync Engines]
    end

    subgraph "Supabase Backend"
        DB[(PostgreSQL)]
        RT[Realtime WebSocket]
        AUTH[Auth/GoTrue]
        STORAGE[Storage Buckets]
        EDGE[Edge Functions]
    end

    subgraph "External Services"
        APNS[Apple Push Notifications]
        MAPS[MapKit/Geocoding]
    end

    UI --> VM
    VM --> SVC
    SVC --> SD
    SVC --> DB
    SD --> SYNC
    SYNC --> RT
    RT --> DB

    SVC --> AUTH
    SVC --> STORAGE

    DB --> EDGE
    EDGE --> APNS

    SVC --> MAPS

    style UI fill:#61dafb
    style VM fill:#4fc3f7
    style SVC fill:#4caf50
    style SD fill:#ff9800
    style SYNC fill:#ff9800
    style DB fill:#9c27b0
    style RT fill:#9c27b0
    style EDGE fill:#9c27b0
```

## Data Flow Architecture

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant ViewModel
    participant Service
    participant SwiftData
    participant Supabase
    participant Realtime

    Note over User,Realtime: Write Flow (Optimistic Update)
    User->>UI: Tap "Send Message"
    UI->>ViewModel: sendMessage()
    ViewModel->>SwiftData: Insert local message (temp ID)
    SwiftData->>UI: Update via @Query
    ViewModel->>Service: sendMessage()
    Service->>Supabase: POST /messages
    Supabase-->>Service: 201 Created (server ID)
    Service->>SwiftData: Update message (reconcile ID)

    Note over User,Realtime: Read Flow (Reactive Sync)
    Supabase->>Realtime: postgres_changes INSERT
    Realtime->>SyncEngine: WebSocket message
    SyncEngine->>SwiftData: Upsert message
    SwiftData->>UI: @Query triggers refresh
    UI->>User: Display new message
```

## Feature Module Structure

```mermaid
graph LR
    subgraph "Feature Module"
        V[Views]
        VM[ViewModels]
        M[Models]
    end

    subgraph "Core Layer"
        SVC[Services]
        REPO[Repositories]
        UTIL[Utilities]
    end

    V --> VM
    VM --> SVC
    VM --> REPO
    SVC --> REPO
    SVC --> UTIL
    VM --> M
    V --> M
```

## Authentication Flow

```mermaid
stateDiagram-v2
    [*] --> Initializing
    Initializing --> CheckingAuth
    CheckingAuth --> Unauthenticated: No session
    CheckingAuth --> PendingApproval: Has session, not approved
    CheckingAuth --> Authenticated: Has session, approved

    Unauthenticated --> CheckingAuth: Login/Signup
    PendingApproval --> Authenticated: Admin approves
    Authenticated --> Unauthenticated: Logout

    CheckingAuth --> Failed: Error
    Failed --> CheckingAuth: Retry
```

## Messaging Architecture

```mermaid
graph TB
    subgraph "Messaging Module"
        CLV[ConversationsListView]
        CDV[ConversationDetailView]
        MIB[MessageInputBar]
        MB[MessageBubble]

        CLVM[ConversationsListViewModel]
        CDVM[ConversationDetailViewModel]
    end

    subgraph "Storage"
        MR[MessagingRepository]
        MSE[MessagingSyncEngine]
        SD[(SwiftData)]
    end

    subgraph "Services"
        CS[ConversationService]
        MS[MessageService]
        MMS[MessageMediaService]
    end

    CLV --> CLVM
    CDV --> CDVM
    CDV --> MIB
    CDV --> MB

    CLVM --> MR
    CDVM --> MR

    CLVM --> CS
    CDVM --> MS
    CDVM --> MMS

    MR --> SD
    MSE --> SD
    MSE --> Realtime[Supabase Realtime]

    MS --> Supabase[(Supabase DB)]
    CS --> Supabase
    MMS --> Storage[Supabase Storage]
```

## Request Lifecycle (Rides/Favors)

```mermaid
stateDiagram-v2
    [*] --> Open: Post Request
    Open --> Confirmed: Claim
    Confirmed --> Completed: Mark Complete
    Completed --> [*]: Reviewed

    Open --> Open: Unclaim
    Confirmed --> Open: Unclaim

    note right of Open: ⚠️ CLAIM BROKEN
    note right of Open: RLS policy blocks UPDATE
    note right of Open: when claimed_by IS NULL
```

## Database RLS Issue (Current Bug)

```mermaid
graph TB
    subgraph "Claim Attempt"
        USER[User Wants to Claim]
        UI_REQ[UI Shows Success ✅]
        API[ClaimService.claimRequest]
        DB_UPDATE[UPDATE rides SET claimed_by = user_id]
    end

    subgraph "RLS Policy Check"
        USING["USING: auth.uid() = user_id<br/>OR auth.uid() = claimed_by"]
        CHECK1{Is claimer<br/>the poster?}
        CHECK2{Is claimed_by<br/>= claimer?}
    end

    subgraph "Result"
        FAIL[❌ UPDATE Returns 0 Rows]
        SUCCESS[✅ Row Updated]
    end

    USER --> UI_REQ
    UI_REQ --> API
    API --> DB_UPDATE
    DB_UPDATE --> USING
    USING --> CHECK1
    CHECK1 -->|No| CHECK2
    CHECK1 -->|Yes| SUCCESS
    CHECK2 -->|No - claimed_by is NULL| FAIL
    CHECK2 -->|Yes| SUCCESS

    FAIL -.->|But user sees| UI_REQ

    style FAIL fill:#ff5252
    style UI_REQ fill:#4caf50
    style SUCCESS fill:#4caf50
```

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
