# send-notification Webhook Setup

Use a Supabase database webhook to trigger `send-notification` whenever the
`notification_queue` is updated for delivery. This keeps push delivery fully
server-driven.

## Webhook configuration

- **Name**: `notification-queue-processor`
- **Table**: `notification_queue`
- **Events**: INSERT, UPDATE
- **Type**: Supabase Edge Functions
- **Function**: `send-notification`

The Edge Function can process the queue without a specific request body, so the
default payload from Supabase is sufficient.

## Scheduling reminders

Completion reminders and Town Hall batching are driven by server-side schedulers.
If you do not use `pg_cron`, run these RPCs via an external scheduler:

- `POST /rest/v1/rpc/process_completion_reminders` (every minute)
- `POST /rest/v1/rpc/process_batched_notifications` (every 3 minutes)

See `NOTIFICATION-DEPLOYMENT-GUIDE.md` for the full deployment steps.
