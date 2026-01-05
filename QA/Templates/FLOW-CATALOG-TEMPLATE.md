# User Flow Catalog Template

## Instructions

Copy this template to your project's `QA/` directory and fill in your app-specific flows.

---

## Flow ID Format

```
FLOW_[CATEGORY]_[NUMBER]

Categories:
- AUTH      Authentication flows
- PROFILE   User profile flows
- [FEATURE] Your feature name
- ADMIN     Administrative flows
```

---

## Template: Authentication Flows

### FLOW_AUTH_001: [Flow Name]

**Description:** [What does this flow accomplish?]

**Preconditions:**
- [What must be true before this flow starts?]

**Happy Path:**
```
1. [Step 1]
2. [Step 2]
3. [Step 3]
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | [What could go wrong?] | [How should app respond?] |
| F2 | | |

**Test Coverage:**
- Unit: `[TestClassName]`
- Integration: `[TestClassName]`
- UI: `[TestClassName]` (if applicable)

---

## Template: Feature Flows

### FLOW_[FEATURE]_001: [Flow Name]

**Description:** [Description]

**Preconditions:**
- [Precondition 1]
- [Precondition 2]

**Happy Path:**
```
1. [Step]
2. [Step]
3. [Step]
```

**Critical Failure Paths:**
| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| F1 | | |

**Test Coverage:**
- Unit: 
- Integration: 
- UI: 

---

## Flow Coverage Matrix Template

Copy and customize for your project:

| Flow ID | Unit | Integration | UI | Snapshot | Status |
|---------|------|-------------|-----|----------|--------|
| FLOW_AUTH_001 | ⏳ | ⏳ | ⏳ | - | Not Started |
| FLOW_AUTH_002 | ⏳ | ⏳ | - | - | Not Started |
| FLOW_[X]_001 | ⏳ | ⏳ | - | ⏳ | Not Started |

**Legend:**
- ⏳ Not Started
- 🟡 In Progress  
- ✅ Complete
- ❌ Failing
- `-` Not Applicable

---

## Checkpoint Mapping Template

Define which checkpoints validate which flows:

| Checkpoint ID | Flows Validated | Test Targets |
|---------------|-----------------|--------------|
| auth-001 | FLOW_AUTH_001 | `Tests/Auth/SignupTests` |
| auth-002 | FLOW_AUTH_002, FLOW_AUTH_003 | `Tests/Auth/LoginTests` |
| [feature]-001 | FLOW_[X]_001 | `Tests/[Feature]` |

---

## Notes

- Each flow should have at least unit test coverage
- Critical flows (auth, payments, data modification) need integration tests
- User-facing flows benefit from UI tests
- Update the coverage matrix as you implement tests
