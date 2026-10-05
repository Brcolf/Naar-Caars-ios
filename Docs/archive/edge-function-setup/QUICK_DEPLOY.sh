#!/bin/bash
# Quick Deploy Script for send-message-push Edge Function
# This script helps automate the deployment process

set -e  # Exit on error

echo "🚀 Deploying send-message-push Edge Function..."
echo ""

# Check if logged in
echo "Step 1: Checking Supabase login status..."
if ! supabase projects list &>/dev/null; then
    echo "⚠️  Not logged in to Supabase CLI"
    echo ""
    echo "Please run this command in your terminal:"
    echo "  supabase login"
    echo ""
    echo "This will open a browser window for authentication."
    exit 1
fi

echo "✅ Logged in to Supabase"
echo ""

# Check if linked to project
echo "Step 2: Checking project link..."
if [ ! -f ".supabase/config.toml" ]; then
    echo "⚠️  Not linked to a Supabase project"
    echo ""
    echo "Please run this command with your project ref:"
    echo "  supabase link --project-ref YOUR_PROJECT_REF"
    echo ""
    echo "To find your project ref:"
    echo "  1. Go to https://app.supabase.com"
    echo "  2. Open your project"
    echo "  3. Look at the URL: https://app.supabase.com/project/YOUR_PROJECT_REF"
    echo "  4. Copy YOUR_PROJECT_REF and use it in the link command"
    exit 1
fi

PROJECT_REF=$(grep "project_id" .supabase/config.toml 2>/dev/null | cut -d'"' -f2 || echo "")
if [ -z "$PROJECT_REF" ]; then
    echo "⚠️  Could not detect project ref from config"
    echo "Please make sure you're in the correct directory and linked to your project"
    exit 1
fi

echo "✅ Linked to project: $PROJECT_REF"
echo ""

# Deploy function
echo "Step 3: Deploying Edge Function..."
echo "This may take a minute..."
echo ""

if supabase functions deploy send-message-push; then
    echo ""
    echo "✅ Edge Function deployed successfully!"
    echo ""
    echo "Next steps (manual):"
    echo ""
    echo "1. Set environment variables in Supabase Dashboard:"
    echo "   - Go to: https://app.supabase.com/project/$PROJECT_REF/functions"
    echo "   - Click on 'send-message-push'"
    echo "   - Click 'Settings' tab"
    echo "   - Add these secrets:"
    echo "     • APNS_TEAM_ID (your Apple Team ID)"
    echo "     • APNS_KEY_ID (your APNs Key ID)"
    echo "     • APNS_KEY (base64 encoded .p8 file content)"
    echo "     • APNS_BUNDLE_ID (your app bundle ID)"
    echo "     • APNS_PRODUCTION (false for testing)"
    echo ""
    echo "2. Create Database Webhook:"
    echo "   - Go to: https://app.supabase.com/project/$PROJECT_REF/database/webhooks"
    echo "   - Click 'Create a new hook'"
    echo "   - Configure:"
    echo "     Name: message_push_webhook"
    echo "     Table: messages"
    echo "     Events: INSERT"
    echo "     Type: HTTP Request"
    echo "     URL: https://$PROJECT_REF.supabase.co/functions/v1/send-message-push"
    echo "     Method: POST"
    echo "     Headers:"
    echo "       Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
    echo "       Content-Type: application/json"
    echo "     Body: { \"id\": \"{{NEW.id}}\", \"conversation_id\": \"{{NEW.conversation_id}}\", \"from_id\": \"{{NEW.from_id}}\", \"text\": \"{{NEW.text}}\" }"
    echo ""
    echo "For detailed instructions, see: STEP_BY_STEP_SETUP.md"
else
    echo ""
    echo "❌ Deployment failed"
    echo "Please check the error messages above"
    exit 1
fi


