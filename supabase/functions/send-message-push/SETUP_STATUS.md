# Setup Status: send-message-push Edge Function

## ✅ Completed Automatically

1. **Edge Function Deployed** ✅
   - Function: `send-message-push`
   - Project: `easlpsksbylyceqiqecq` (Naars-cars)
   - Status: Deployed and ready

2. **Environment Variables Set** ✅
   - `APNS_TEAM_ID`: `WT4DGUYKL4` ✅
   - `APNS_KEY_ID`: `H5U4Q54895` ✅
   - `APNS_KEY`: Base64 encoded (set) ✅
   - `APNS_BUNDLE_ID`: `com.NaarsCars` ✅
   - `APNS_PRODUCTION`: `false` ✅

## ⏳ Remaining Manual Step

**Create Database Webhook** (takes ~2 minutes)

See: **WEBHOOK_CONFIG.md** for copy/paste ready configuration

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks

---

## Quick Verification

### Check Environment Variables
Run in terminal:
```bash
cd /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs
supabase secrets list --project-ref easlpsksbylyceqiqecq | grep APNS
```

You should see all 5 APNS variables listed.

### Check Function Status
Visit: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push

You should see:
- Function name: `send-message-push`
- Status: Active/Deployed
- All secrets visible in Settings tab

---

## Next Steps

1. **Create the webhook** using WEBHOOK_CONFIG.md
2. **Test by sending a message** from your iOS app
3. **Check logs** to verify push notifications are being sent

---

## Troubleshooting

If webhook creation fails:
- Verify service role key is correct (get from Settings → API)
- Check webhook URL matches exactly: `https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push`
- Ensure request body template uses `{{NEW.id}}` format (not `{{ NEW.id }}`)

If push notifications don't arrive:
- Check Edge Function logs for errors
- Verify device token is registered in `push_tokens` table
- Make sure recipient is NOT viewing the conversation (app closed or different screen)
- Verify notification permissions are granted in iOS app
- Use real device (simulator doesn't receive push)


