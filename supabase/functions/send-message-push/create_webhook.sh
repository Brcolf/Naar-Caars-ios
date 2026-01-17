#!/bin/bash
# Script to create database webhook via Supabase Management API

set -e

PROJECT_REF="easlpsksbylyceqiqecq"
WEBHOOK_URL="https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push"

echo "Creating database webhook..."
echo "Project: $PROJECT_REF"
echo ""

# Try to get access token from CLI
ACCESS_TOKEN=$(cat ~/.supabase/access-token 2>/dev/null || echo "")

if [ -z "$ACCESS_TOKEN" ]; then
    echo "⚠️  Access token not found in ~/.supabase/access-token"
    echo ""
    echo "To get your access token:"
    echo "1. Run: supabase projects list"
    echo "2. Or check: cat ~/.supabase/access-token"
    echo ""
    echo "Alternatively, you can create the webhook manually in the Dashboard:"
    echo "https://supabase.com/dashboard/project/$PROJECT_REF/database/webhooks"
    exit 1
fi

# Get service role key from secrets
echo "Fetching service role key..."
SERVICE_ROLE_KEY=$(supabase secrets list --project-ref $PROJECT_REF 2>/dev/null | grep SUPABASE_SERVICE_ROLE_KEY | awk '{print $1}' || echo "")

if [ -z "$SERVICE_ROLE_KEY" ]; then
    echo "⚠️  Could not retrieve service role key automatically"
    echo "You'll need to get it from: https://supabase.com/dashboard/project/$PROJECT_REF/settings/api"
    echo "Then use it in the webhook configuration below"
    exit 1
fi

# Note: Supabase Management API may not have direct webhook creation
# This is a placeholder - webhooks might need to be created via Dashboard
echo ""
echo "Note: Database webhooks must be created via the Supabase Dashboard."
echo "Here's the configuration you need:"
echo ""
echo "Name: message_push_webhook"
echo "Table: messages"
echo "Events: INSERT"
echo "Type: HTTP Request"
echo "URL: $WEBHOOK_URL"
echo "Method: POST"
echo "Header 1 - Key: Authorization"
echo "Header 1 - Value: Bearer [YOUR_SERVICE_ROLE_KEY]"
echo "Header 2 - Key: Content-Type"
echo "Header 2 - Value: application/json"
echo ""
echo "Request Body:"
echo '{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}'
echo ""
echo "Direct link to create webhook:"
echo "https://supabase.com/dashboard/project/$PROJECT_REF/database/webhooks"
echo ""
echo "To get your service role key, go to:"
echo "https://supabase.com/dashboard/project/$PROJECT_REF/settings/api"


