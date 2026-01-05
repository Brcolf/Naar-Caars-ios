#!/bin/bash

# QA Checkpoint Runner for Naar's Cars iOS
# Usage: ./checkpoint.sh <checkpoint-id> [options]
#
# Examples:
#   ./checkpoint.sh auth-002
#   ./checkpoint.sh --feature messaging
#   ./checkpoint.sh foundation-001 --verbose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="NaarsCars"
PROJECT_FILE="${PROJECT_NAME}.xcodeproj"
SCHEME="${PROJECT_NAME}"
DESTINATION="platform=iOS Simulator,name=iPhone 15"
REPORTS_DIR="QA/Reports"

# Parse arguments
CHECKPOINT_ID=""
FEATURE=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --feature)
            FEATURE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: ./checkpoint.sh <checkpoint-id> [options]"
            echo ""
            echo "Options:"
            echo "  --feature <name>  Run all tests for a feature"
            echo "  --verbose         Show detailed test output"
            echo "  --help            Show this help message"
            echo ""
            echo "Checkpoint IDs:"
            echo "  Foundation: foundation-001, foundation-002, foundation-003, foundation-004, foundation-final"
            echo "  Auth:       auth-001, auth-002, auth-003, auth-final"
            echo "  Profile:    profile-001, profile-002, profile-final"
            echo "  Rides:      ride-001, ride-002, ride-final"
            echo "  Favors:     favor-001, favor-final"
            echo "  Claiming:   claim-001, claim-final"
            echo "  Messaging:  messaging-001, messaging-final"
            echo "  Push:       push-001, push-final"
            echo "  Notif:      notifications-001, notifications-final"
            echo "  Reviews:    review-001, review-final"
            echo "  TownHall:   townhall-001, townhall-final"
            echo "  Leaderboard: leaderboard-001, leaderboard-final"
            echo "  Admin:      admin-001, admin-final"
            echo "  Invite:     invite-001, invite-final"
            echo ""
            echo "Note: Task 5.0 database checkpoint (SEC-DB-*, PERF-DB-*, EDGE-*)"
            echo "      is executed manually in Supabase Dashboard. See CHECKPOINT-GUIDE.md"
            exit 0
            ;;
        *)
            CHECKPOINT_ID="$1"
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$CHECKPOINT_ID" && -z "$FEATURE" ]]; then
    echo -e "${RED}Error: Please provide a checkpoint ID or --feature name${NC}"
    echo "Run './checkpoint.sh --help' for usage"
    exit 1
fi

# Map checkpoint to test targets
get_test_targets() {
    local checkpoint=$1
    case $checkpoint in
        # Foundation checkpoints (match tasks-foundation-architecture.md)
        foundation-001)
            # After Task 7.0: Core models
            echo "NaarsCarsTests/Core/Models"
            ;;
        foundation-002)
            # After Task 12.0: App launches, navigation works (manual verification)
            echo "MANUAL: Verify app launches and navigation works in simulator"
            ;;
        foundation-003)
            # After Task 16.0: RateLimiter and CacheManager
            echo "NaarsCarsTests/Core/Utilities/RateLimiterTests NaarsCarsTests/Core/Utilities/CacheManagerTests"
            ;;
        foundation-004)
            # After Task 18.0: ImageCompressor and RealtimeManager
            echo "NaarsCarsTests/Core/Utilities/ImageCompressorTests NaarsCarsTests/Core/Services/RealtimeManagerTests"
            ;;
        foundation-final)
            # After Task 22.0: All foundation tests + PERF-CLI-* manual tests
            echo "NaarsCarsTests/Core"
            ;;
        # Auth checkpoints
        auth-001)
            echo "NaarsCarsTests/Core/Services/AuthServiceTests NaarsCarsTests/Features/Authentication/SignupViewModelTests"
            ;;
        auth-002)
            echo "NaarsCarsTests/Features/Authentication/LoginViewModelTests"
            ;;
        auth-003)
            echo "NaarsCarsTests/Features/Authentication"
            ;;
        auth-final)
            echo "NaarsCarsTests/Features/Authentication NaarsCarsTests/Core/Services/AuthServiceTests NaarsCarsIntegrationTests/Auth"
            ;;
        # Profile checkpoints
        profile-001)
            echo "NaarsCarsTests/Core/Services/ProfileServiceTests NaarsCarsTests/Core/Utilities/ValidatorsTests"
            ;;
        profile-002)
            echo "NaarsCarsTests/Features/Profile"
            ;;
        profile-final)
            echo "NaarsCarsTests/Features/Profile NaarsCarsSnapshotTests/Profile"
            ;;
        # Ride checkpoints
        ride-001)
            echo "NaarsCarsTests/Core/Services/RideServiceTests"
            ;;
        ride-002)
            echo "NaarsCarsTests/Features/Rides"
            ;;
        ride-final)
            echo "NaarsCarsTests/Features/Rides NaarsCarsIntegrationTests/Rides"
            ;;
        # Favor checkpoints
        favor-001)
            echo "NaarsCarsTests/Core/Services/FavorServiceTests"
            ;;
        favor-final)
            echo "NaarsCarsTests/Features/Favors"
            ;;
        # Claim checkpoints
        claim-001)
            echo "NaarsCarsTests/Core/Services/ClaimServiceTests"
            ;;
        claim-final)
            echo "NaarsCarsTests/Features/Claiming NaarsCarsIntegrationTests/Claiming"
            ;;
        # Messaging checkpoints
        messaging-001)
            echo "NaarsCarsTests/Core/Services/MessageServiceTests"
            ;;
        messaging-final)
            echo "NaarsCarsTests/Features/Messaging NaarsCarsIntegrationTests/Messaging"
            ;;
        # Push notification checkpoints
        push-001)
            echo "NaarsCarsTests/Core/Utilities/DeepLinkParserTests"
            ;;
        push-final)
            echo "NaarsCarsTests/Features/PushNotifications"
            ;;
        # In-app notification checkpoints
        notifications-001)
            echo "NaarsCarsTests/Core/Services/NotificationServiceTests"
            ;;
        notifications-final)
            echo "NaarsCarsTests/Features/Notifications"
            ;;
        # Review checkpoints
        review-001)
            echo "NaarsCarsTests/Core/Services/ReviewServiceTests"
            ;;
        review-final)
            echo "NaarsCarsTests/Features/Reviews"
            ;;
        # Town Hall checkpoints
        townhall-001)
            echo "NaarsCarsTests/Core/Services/TownHallServiceTests"
            ;;
        townhall-final)
            echo "NaarsCarsTests/Features/TownHall"
            ;;
        # Leaderboard checkpoints
        leaderboard-001)
            echo "NaarsCarsTests/Core/Services/LeaderboardServiceTests"
            ;;
        leaderboard-final)
            echo "NaarsCarsTests/Features/Leaderboards"
            ;;
        # Admin checkpoints
        admin-001)
            echo "NaarsCarsTests/Core/Services/AdminServiceTests"
            ;;
        admin-final)
            echo "NaarsCarsTests/Features/Admin"
            ;;
        # Invite checkpoints
        invite-001)
            echo "NaarsCarsTests/Core/Services/InviteServiceTests"
            ;;
        invite-final)
            echo "NaarsCarsTests/Features/Invites"
            ;;
        # Apple Sign-In checkpoints
        apple-001)
            echo "NaarsCarsTests/Core/Services/AuthServiceTests"
            ;;
        apple-final)
            echo "NaarsCarsTests/Features/Authentication/AppleSignIn"
            ;;
        # Biometric checkpoints
        biometric-001)
            echo "NaarsCarsTests/Core/Services/BiometricServiceTests"
            ;;
        biometric-final)
            echo "NaarsCarsTests/Features/Security"
            ;;
        # Dark mode checkpoints
        darkmode-001)
            echo "MANUAL: Verify app builds with color updates"
            ;;
        darkmode-final)
            echo "NaarsCarsSnapshotTests/DarkMode"
            ;;
        # Localization checkpoints
        localization-001)
            echo "MANUAL: Verify no hardcoded strings, app builds"
            ;;
        localization-final)
            echo "NaarsCarsTests/Core/Utilities/LocalizationTests"
            ;;
        # Location checkpoints
        location-001)
            echo "NaarsCarsTests/Core/Services/LocationServiceTests"
            ;;
        location-final)
            echo "NaarsCarsTests/Features/Location"
            ;;
        # Map checkpoints
        map-001)
            echo "NaarsCarsTests/Core/Services/LocationServiceTests"
            ;;
        map-final)
            echo "NaarsCarsTests/Features/Maps"
            ;;
        # Crash reporting checkpoints
        crash-001)
            echo "NaarsCarsTests/Core/Services/CrashReportingServiceTests"
            ;;
        crash-final)
            echo "NaarsCarsTests/Features/CrashReporting"
            ;;
        # Phase checkpoints (run all tests for a phase)
        phase-0)
            echo "NaarsCarsTests/Core NaarsCarsTests/Features/Authentication"
            ;;
        phase-1)
            echo "NaarsCarsTests/Features/Profile NaarsCarsTests/Features/Rides NaarsCarsTests/Features/Favors NaarsCarsTests/Features/Claiming"
            ;;
        phase-2)
            echo "NaarsCarsTests/Features/Messaging NaarsCarsTests/Features/Notifications NaarsCarsTests/Features/PushNotifications"
            ;;
        phase-3)
            echo "NaarsCarsTests/Features/TownHall NaarsCarsTests/Features/Reviews NaarsCarsTests/Features/Leaderboards"
            ;;
        phase-4)
            echo "NaarsCarsTests/Features/Admin NaarsCarsTests/Features/Invites"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Map feature to test targets
get_feature_targets() {
    local feature=$1
    case $feature in
        foundation)
            echo "NaarsCarsTests/Core"
            ;;
        auth|authentication)
            echo "NaarsCarsTests/Features/Authentication NaarsCarsTests/Core/Services/AuthServiceTests"
            ;;
        profile)
            echo "NaarsCarsTests/Features/Profile"
            ;;
        rides)
            echo "NaarsCarsTests/Features/Rides"
            ;;
        favors)
            echo "NaarsCarsTests/Features/Favors"
            ;;
        claiming)
            echo "NaarsCarsTests/Features/Claiming"
            ;;
        messaging)
            echo "NaarsCarsTests/Features/Messaging"
            ;;
        notifications)
            echo "NaarsCarsTests/Features/Notifications"
            ;;
        townhall)
            echo "NaarsCarsTests/Features/TownHall"
            ;;
        reviews)
            echo "NaarsCarsTests/Features/Reviews"
            ;;
        leaderboards)
            echo "NaarsCarsTests/Features/Leaderboards"
            ;;
        admin)
            echo "NaarsCarsTests/Features/Admin"
            ;;
        all)
            echo "NaarsCarsTests"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get test targets
if [[ -n "$FEATURE" ]]; then
    TEST_TARGETS=$(get_feature_targets "$FEATURE")
    REPORT_NAME="feature-${FEATURE}"
else
    TEST_TARGETS=$(get_test_targets "$CHECKPOINT_ID")
    REPORT_NAME="$CHECKPOINT_ID"
fi

if [[ -z "$TEST_TARGETS" ]]; then
    echo -e "${RED}Error: Unknown checkpoint '$CHECKPOINT_ID' or feature '$FEATURE'${NC}"
    exit 1
fi

# Create report directory
REPORT_DIR="${REPORTS_DIR}/${REPORT_NAME}"
mkdir -p "$REPORT_DIR"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
TIMESTAMP_FILE=$(date +"%Y%m%d-%H%M%S")

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  QA Checkpoint: ${CHECKPOINT_ID:-$FEATURE}${NC}"
echo -e "${BLUE}  Started: ${TIMESTAMP}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Build test command
BUILD_CMD="xcodebuild test -project ${PROJECT_FILE} -scheme ${SCHEME} -destination '${DESTINATION}'"

# Add test targets
for target in $TEST_TARGETS; do
    BUILD_CMD="${BUILD_CMD} -only-testing:${target}"
done

# Run tests
echo -e "${YELLOW}Running tests...${NC}"
echo ""

START_TIME=$(date +%s)

# Execute and capture output
if $VERBOSE; then
    eval "$BUILD_CMD" 2>&1 | tee "${REPORT_DIR}/raw-output-${TIMESTAMP_FILE}.log"
    TEST_RESULT=${PIPESTATUS[0]}
else
    # Try to use xcpretty if available
    if command -v xcpretty &> /dev/null; then
        eval "$BUILD_CMD" 2>&1 | xcpretty | tee "${REPORT_DIR}/output-${TIMESTAMP_FILE}.log"
        TEST_RESULT=${PIPESTATUS[0]}
    else
        eval "$BUILD_CMD" 2>&1 | tee "${REPORT_DIR}/raw-output-${TIMESTAMP_FILE}.log"
        TEST_RESULT=${PIPESTATUS[0]}
    fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""

# Parse results and generate summary
if [[ $TEST_RESULT -eq 0 ]]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ CHECKPOINT ${CHECKPOINT_ID:-$FEATURE} PASSED${NC}"
    echo -e "${GREEN}  Duration: ${DURATION}s${NC}"
    echo -e "${GREEN}  Report: ${REPORT_DIR}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Generate summary file
    cat > "${REPORT_DIR}/summary.md" << EOF
# Checkpoint Report: ${CHECKPOINT_ID:-$FEATURE}

**Date:** ${TIMESTAMP}
**Duration:** ${DURATION} seconds
**Status:** ✅ PASSED

## Test Targets
$(for target in $TEST_TARGETS; do echo "- $target"; done)

## Result
All tests passed successfully.

## Next Steps
Update the checkpoint in the task file to ✅ PASSED and continue to the next task.
EOF

    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ❌ CHECKPOINT ${CHECKPOINT_ID:-$FEATURE} FAILED${NC}"
    echo -e "${RED}  Duration: ${DURATION}s${NC}"
    echo -e "${RED}  Report: ${REPORT_DIR}${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Review the test output above for failure details.${NC}"
    echo -e "${YELLOW}Fix failures before proceeding past this checkpoint.${NC}"
    
    # Generate summary file
    cat > "${REPORT_DIR}/summary.md" << EOF
# Checkpoint Report: ${CHECKPOINT_ID:-$FEATURE}

**Date:** ${TIMESTAMP}
**Duration:** ${DURATION} seconds
**Status:** ❌ FAILED

## Test Targets
$(for target in $TEST_TARGETS; do echo "- $target"; done)

## Result
One or more tests failed. Review the log file for details:
- \`${REPORT_DIR}/raw-output-${TIMESTAMP_FILE}.log\`

## Next Steps
1. Review failure details in the log
2. Fix the failing tests or implementation
3. Re-run this checkpoint
4. Do NOT proceed until checkpoint passes
EOF

    exit 1
fi
