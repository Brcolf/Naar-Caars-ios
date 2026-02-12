// Edge Function: send-notification
// Unified notification sender for all notification types
// Processes notification_queue and sends APNs push notifications
// Called via Supabase Database Webhook or scheduled cron

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { corsHeaders, sendAPNsPush, resolveEventType, resolveTableName, processBatch } from '../_shared/apns.ts'
import { getBadgeCount } from '../_shared/badges.ts'
import { NOTIFICATION_TYPES } from '../_shared/notificationTypes.ts'

interface NotificationPayload {
  title: string
  body: string
  type: string
  data: Record<string, any>
}

interface QueuedNotification {
  id: string
  notification_type: string
  recipient_user_id: string
  payload: NotificationPayload
  batch_key: string | null
  created_at: string
  processed_at: string | null
}

interface APNsPayload {
  aps: {
    alert: {
      title: string
      body: string
    }
    sound: string
    badge?: number
    'mutable-content'?: number
    'content-available'?: number
    category?: string
  }
  type: string
  [key: string]: any
}

// Notification categories for actionable notifications
const NOTIFICATION_CATEGORIES: Record<string, string> = {
  [NOTIFICATION_TYPES.COMPLETION_REMINDER]: 'COMPLETION_REMINDER',
  [NOTIFICATION_TYPES.MESSAGE]: 'MESSAGE',
  new_request: 'NEW_REQUEST',
}

// Simple in-memory rate limiter
const rateLimitMap = new Map<string, number>()
function checkRateLimit(userId: string, maxPerMinute: number = 30): boolean {
  const now = Date.now()
  const last = rateLimitMap.get(userId) ?? 0
  if (now - last < (60000 / maxPerMinute)) return false
  rateLimitMap.set(userId, now)
  return true
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing Supabase environment variables')
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Parse request body
    let requestData: any = {}
    try {
      requestData = await req.json()
    } catch {
      // No body is fine - we'll process the queue
    }

    // Input validation
    if (requestData.title && requestData.title.length > 200) {
      requestData.title = requestData.title.substring(0, 200);
    }
    if (requestData.body && requestData.body.length > 500) {
      requestData.body = requestData.body.substring(0, 500);
    }

    // Check if this is a direct notification request or queue processing
    if (requestData.direct) {
      // Rate limit direct notifications
      if (requestData.recipient_user_id && !checkRateLimit(requestData.recipient_user_id)) {
        return new Response(
          JSON.stringify({ error: 'Rate limited', retry_after_ms: 2000 }),
          { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      return await sendDirectNotification(supabase, requestData)
    } else if (requestData.action === 'completion_response') {
      return await handleCompletionResponse(supabase, requestData)
    } else {
      const eventType = resolveEventType(requestData)
      const tableName = resolveTableName(requestData)
      if (tableName && tableName !== 'notification_queue') {
        return new Response(
          JSON.stringify({ skipped: true, reason: 'unsupported_table', tableName }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (eventType && eventType !== 'INSERT' && eventType !== 'UPDATE') {
        return new Response(
          JSON.stringify({ skipped: true, reason: 'unsupported_event', eventType }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (eventType === 'UPDATE') {
        const record = resolveRecord(requestData)
        const oldRecord = resolveOldRecord(requestData)
        const processedTransition = record?.processed_at && !oldRecord?.processed_at && !record?.sent_at

        if (!processedTransition) {
          return new Response(
            JSON.stringify({ skipped: true, reason: 'ignored_update' }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }

      // Process notification queue
      return await processNotificationQueue(supabase)
    }
  } catch (error) {
    console.error('Error in send-notification:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function sendDirectNotification(supabase: any, data: any) {
  const { recipient_user_id, notification_type, title, body, payload_data } = data

  if (!recipient_user_id || !notification_type || !title) {
    return new Response(
      JSON.stringify({ error: 'Missing required fields' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const result = await sendPushToUser(
    supabase, recipient_user_id, notification_type,
    title, body || '', payload_data || {}
  )

  return new Response(
    JSON.stringify(result),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function handleCompletionResponse(supabase: any, data: any) {
  const { reminder_id, completed } = data

  if (!reminder_id) {
    return new Response(
      JSON.stringify({ error: 'Missing reminder_id' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const { data: result, error } = await supabase
    .rpc('handle_completion_response', {
      p_reminder_id: reminder_id,
      p_completed: completed === true || completed === 'true'
    })

  if (error) {
    console.error('Error handling completion response:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify(result),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function processNotificationQueue(supabase: any) {
  // Queue any due completion reminders
  const { error: reminderError } = await supabase.rpc('process_completion_reminders')
  if (reminderError) {
    console.error('Error processing completion reminders:', reminderError)
  }

  // Fetch unprocessed non-batched notifications
  const { data: notifications, error } = await supabase
    .from('notification_queue')
    .select('*')
    .is('sent_at', null)
    .is('batch_key', null)
    .order('created_at', { ascending: true })
    .limit(100)

  if (error) {
    console.error('Error fetching notification queue:', error)
    throw error
  }

  if (!notifications || notifications.length === 0) {
    return new Response(
      JSON.stringify({ processed: 0, message: 'No notifications to process' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Process notifications in parallel with batching (max 10 concurrent)
  const results: any[] = []

  const batchResults = await processBatch(
    notifications as QueuedNotification[],
    10,
    async (notification) => {
      const payload = notification.payload as NotificationPayload
      const result = await sendPushToUser(
        supabase, notification.recipient_user_id, notification.notification_type,
        payload.title, payload.body, payload.data || {}
      )
      // Mark as sent only if APNs delivery succeeded or the notification was
      // intentionally skipped (for example no active token). Keep failed sends
      // pending so they can be retried on the next processing pass.
      if (result.sent || result.skipped) {
        await supabase
          .from('notification_queue')
          .update({ sent_at: new Date().toISOString() })
          .eq('id', notification.id)
      }
      return { id: notification.id, ...result }
    }
  )

  for (const result of batchResults) {
    if (result.status === 'fulfilled') {
      results.push(result.value)
    } else {
      results.push({ error: (result.reason as Error).message })
    }
  }

  // Also process any batched notifications that are ready
  const { data: batchedCount } = await supabase.rpc('process_batched_notifications')

  return new Response(
    JSON.stringify({
      processed: results.length,
      batched_processed: batchedCount || 0,
      results
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function sendPushToUser(
  supabase: any,
  userId: string,
  notificationType: string,
  title: string,
  body: string,
  data: Record<string, any>
): Promise<{ sent: boolean; devices?: number; successes?: number; failures?: number; skipped?: boolean; reason?: string }> {
  
  // Get user's push tokens
  const { data: tokens, error: tokenError } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', userId)

  if (tokenError) {
    throw new Error(`Failed to fetch push tokens: ${tokenError.message}`)
  }

  if (!tokens || tokens.length === 0) {
    console.log(`⏭️ No push tokens found for user ${userId}`)
    return { sent: false, skipped: true, reason: 'no_tokens' }
  }

  // Get badge count using shared utility (single optimized query)
  const badgeCount = await getBadgeCount(supabase, userId)

  // Prepare APNs payload
  const apnsPayload: APNsPayload = {
    aps: {
      alert: { title, body },
      sound: 'default',
      badge: badgeCount,
      'mutable-content': 1,
    },
    type: notificationType,
    ...data
  }

  // Add category for actionable notifications
  if (notificationType === NOTIFICATION_TYPES.COMPLETION_REMINDER) {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES[NOTIFICATION_TYPES.COMPLETION_REMINDER]
  } else if (notificationType === NOTIFICATION_TYPES.MESSAGE) {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES[NOTIFICATION_TYPES.MESSAGE]
  } else if (notificationType === NOTIFICATION_TYPES.NEW_RIDE || notificationType === NOTIFICATION_TYPES.NEW_FAVOR) {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES.new_request
  }

  // Send push to all devices for this user
  const pushResults = await Promise.allSettled(
    tokens.map(async (tokenRow: { token: string }) => {
      return await sendAPNsPush(tokenRow.token, apnsPayload, supabase)
    })
  )

  const successes = pushResults.filter(r => r.status === 'fulfilled').length
  const failures = pushResults.filter(r => r.status === 'rejected').length

  pushResults.forEach((result, index) => {
    if (result.status === 'rejected') {
      console.error(`Failed to send push to token ${tokens[index].token.substring(0, 8)}...:`, result.reason)
    }
  })

  // Update last_used_at for successful tokens
  if (successes > 0) {
    await supabase
      .from('push_tokens')
      .update({ last_used_at: new Date().toISOString() })
      .eq('user_id', userId)
  }

  console.log(`✅ Sent push notifications to user ${userId}: ${successes} succeeded, ${failures} failed`)

  return { sent: successes > 0, devices: tokens.length, successes, failures }
}

function resolveRecord(payload: any): any {
  return payload?.record || payload?.data?.record || payload?.new || payload?.data?.new || payload
}

function resolveOldRecord(payload: any): any {
  return payload?.old_record || payload?.data?.old_record || payload?.old || payload?.data?.old
}
