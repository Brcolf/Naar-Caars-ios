#!/bin/bash
# Test script for push notifications
# This tests the Edge Function directly

set -e

PROJECT_REF="easlpsksbylyceqiqecq"
EDGE_FUNCTION_URL="https://${PROJECT_REF}.supabase.co/functions/v1/send-message-push"

echo "🧪 Testing Push Notification Edge Function"
echo ""

# Get anon key from Supabase
echo "Step 1: Getting Supabase anon key..."
ANON_KEY=$(supabase secrets list --project-ref $PROJECT_REF 2>/dev/null | grep SUPABASE_ANON_KEY | head -1 | awk '{print $1}' || echo "")

if [ -z "$ANON_KEY" ]; then
    echo "⚠️  Could not get anon key automatically"
    echo "Please get it from: https://supabase.com/dashboard/project/$PROJECT_REF/settings/api"
    echo "Then set it as: export SUPABASE_ANON_KEY='your-key-here'"
    read -p "Enter your Supabase anon key: " ANON_KEY
fi

echo "✅ Using anon key"
echo ""

# Prompt for test data
echo "Step 2: Enter test data"
echo ""
read -p "Enter recipient user ID (Alice's UUID): " RECIPIENT_USER_ID
read -p "Enter conversation ID (or press Enter to use a test UUID): " CONVERSATION_ID
read -p "Enter sender name (or press Enter for 'Test Sender'): " SENDER_NAME
read -p "Enter message text (or press Enter for 'Test message'): " MESSAGE_TEXT

# Set defaults
CONVERSATION_ID=${CONVERSATION_ID:-$(uuidgen)}
SENDER_NAME=${SENDER_NAME:-"Test Sender"}
MESSAGE_TEXT=${MESSAGE_TEXT:-"Test message"}
MESSAGE_ID=$(uuidgen)
SENDER_ID=$(uuidgen)

echo ""
echo "Step 3: Calling Edge Function..."
echo ""

# Call Edge Function
RESPONSE=$(curl -s -X POST "$EDGE_FUNCTION_URL" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"recipient_user_id\": \"$RECIPIENT_USER_ID\",
    \"conversation_id\": \"$CONVERSATION_ID\",
    \"sender_name\": \"$SENDER_NAME\",
    \"message_preview\": \"$MESSAGE_TEXT\",
    \"message_id\": \"$MESSAGE_ID\",
    \"sender_id\": \"$SENDER_ID\"
  }")

echo "Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# Check response
if echo "$RESPONSE" | grep -q '"sent":true'; then
    echo "✅ Push notification sent successfully!"
    echo ""
    echo "Check Edge Function logs:"
    echo "https://supabase.com/dashboard/project/$PROJECT_REF/functions/send-message-push/logs"
elif echo "$RESPONSE" | grep -q '"skipped":true'; then
    echo "⏭️  Push was skipped (user viewing or no tokens)"
    echo ""
    echo "Check the reason in the response above"
else
    echo "❌ Error occurred"
    echo ""
    echo "Check the response above for error details"
fi

echo ""
echo "Note: If testing on simulator, you won't see the notification,"
echo "      but the Edge Function logs will show if it was sent."


