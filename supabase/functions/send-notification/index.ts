// Edge Function: send-notification
// Unified notification sender for all notification types
// Processes notification_queue and sends APNs push notifications
// Called via Supabase Database Webhook or scheduled cron

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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
const NOTIFICATION_CATEGORIES = {
  completion_reminder: 'COMPLETION_REMINDER',
  message: 'MESSAGE',
  new_request: 'NEW_REQUEST',
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
      // Direct notification - send immediately
      return await sendDirectNotification(supabase, requestData)
    } else if (requestData.action === 'completion_response') {
      // Handle completion reminder response (Yes/No)
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
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
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
    supabase,
    recipient_user_id,
    notification_type,
    title,
    body || '',
    payload_data || {}
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

  // Call the database function to handle the response
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

  // Fetch unprocessed notifications from queue
  // For non-batched notifications, process immediately
  // For batched notifications, they're handled by the cron job
  const { data: notifications, error } = await supabase
    .from('notification_queue')
    .select('*')
    .is('sent_at', null)
    .is('batch_key', null)  // Only non-batched notifications
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

  const results = []
  
  for (const notification of notifications as QueuedNotification[]) {
    try {
      const payload = notification.payload as NotificationPayload
      
      const result = await sendPushToUser(
        supabase,
        notification.recipient_user_id,
        notification.notification_type,
        payload.title,
        payload.body,
        payload.data || {}
      )

      // Mark as sent
      await supabase
        .from('notification_queue')
        .update({ sent_at: new Date().toISOString() })
        .eq('id', notification.id)

      results.push({ id: notification.id, ...result })
    } catch (err) {
      console.error(`Error processing notification ${notification.id}:`, err)
      results.push({ id: notification.id, error: err.message })
    }
  }

  // Also process any batched notifications that are ready
  const { data: batchedCount } = await supabase
    .rpc('process_batched_notifications')

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
    console.error('Error fetching push tokens:', tokenError)
    throw new Error(`Failed to fetch push tokens: ${tokenError.message}`)
  }

  if (!tokens || tokens.length === 0) {
    console.log(`⏭️ No push tokens found for user ${userId}`)
    return { sent: false, skipped: true, reason: 'no_tokens' }
  }

  // Get unread notification count for badge
  const { count: unreadCount } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('read', false)

  // Get unread message count for badge
  const { data: unreadMessages, error: unreadMessagesError } = await supabase
    .rpc('get_unread_message_count', { p_user_id: userId })

  if (unreadMessagesError) {
    console.error('Error fetching unread message count:', unreadMessagesError)
  }

  const unreadMessagesCount = typeof unreadMessages === 'number' ? unreadMessages : 0

  // Prepare APNs payload
  const apnsPayload: APNsPayload = {
    aps: {
      alert: {
        title,
        body
      },
      sound: 'default',
      badge: (unreadCount ?? 0) + unreadMessagesCount,
      'mutable-content': 1,
    },
    type: notificationType,
    ...data
  }

  // Add category for actionable notifications
  if (notificationType === 'completion_reminder') {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES.completion_reminder
  } else if (notificationType === 'message') {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES.message
  } else if (notificationType === 'new_ride' || notificationType === 'new_favor') {
    apnsPayload.aps.category = NOTIFICATION_CATEGORIES.new_request
  }

  // Send push to all devices for this user
  const pushResults = await Promise.allSettled(
    tokens.map(async (tokenRow: { token: string }) => {
      return await sendAPNsPush(tokenRow.token, apnsPayload, supabase)
    })
  )

  // Count successes and failures
  const successes = pushResults.filter(r => r.status === 'fulfilled').length
  const failures = pushResults.filter(r => r.status === 'rejected').length

  // Log failures
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

  return {
    sent: successes > 0,
    devices: tokens.length,
    successes,
    failures
  }
}

async function sendAPNsPush(token: string, payload: APNsPayload, supabase: any): Promise<void> {
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsKey = Deno.env.get('APNS_KEY')
  const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')
  const apnsProduction = Deno.env.get('APNS_PRODUCTION') === 'true'

  if (!apnsTeamId || !apnsKeyId || !apnsKey || !apnsBundleId) {
    throw new Error('Missing APNs environment variables')
  }

  // APNs endpoint
  const apnsUrl = apnsProduction
    ? `https://api.push.apple.com/3/device/${token}`
    : `https://api.sandbox.push.apple.com/3/device/${token}`

  // Create JWT token for APNs authentication
  const jwt = await createAPNsJWT(apnsTeamId, apnsKeyId, apnsKey)

  // Determine push type
  let pushType = 'alert'
  if (payload.aps['content-available'] === 1 && !payload.aps.alert) {
    pushType = 'background'
  }

  // Send to APNs
  const response = await fetch(apnsUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwt}`,
      'apns-topic': apnsBundleId,
      'apns-priority': '10',
      'apns-push-type': pushType,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000)
  })

  if (!response.ok) {
    const errorText = await response.text()
    
    // Handle specific APNs error codes
    if (response.status === 410) {
      // Token is no longer valid - remove it
      console.log(`🗑️ Removing invalid token: ${token.substring(0, 8)}...`)
      await supabase
        .from('push_tokens')
        .delete()
        .eq('token', token)
    }
    
    throw new Error(`APNs error (${response.status}): ${errorText}`)
  }

  const apnsId = response.headers.get('apns-id')
  console.log(`✅ APNs push sent successfully (ID: ${apnsId})`)
}

async function createAPNsJWT(teamId: string, keyId: string, key: string): Promise<string> {
  const { create, getNumericDate } = await import('https://deno.land/x/djwt@v2.8/mod.ts')
  
  // Decode base64 key if needed
  let privateKeyPem: string
  try {
    privateKeyPem = atob(key)
  } catch {
    privateKeyPem = key
  }

  // Import the private key
  const cryptoKey = await importECPrivateKey(privateKeyPem)

  // JWT header
  const header = {
    alg: 'ES256' as const,
    kid: keyId
  }

  // JWT payload
  const payload = {
    iss: teamId,
    iat: getNumericDate(new Date())
  }

  // Create JWT
  const jwt = await create(header, payload, cryptoKey)

  return jwt
}

function resolveEventType(payload: any): string | undefined {
  return payload?.type || payload?.eventType || payload?.event_type || payload?.data?.type || payload?.data?.eventType || payload?.data?.event_type
}

function resolveTableName(payload: any): string | undefined {
  return payload?.table || payload?.table_name || payload?.data?.table || payload?.data?.table_name
}

function resolveRecord(payload: any): any {
  return payload?.record || payload?.data?.record || payload?.new || payload?.data?.new || payload
}

function resolveOldRecord(payload: any): any {
  return payload?.old_record || payload?.data?.old_record || payload?.old || payload?.data?.old
}
async function importECPrivateKey(pemKey: string): Promise<CryptoKey> {
  // Remove PEM headers/footers and whitespace
  const keyData = pemKey
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  // Decode base64
  const binaryKey = Uint8Array.from(atob(keyData), c => c.charCodeAt(0))

  // Import as EC private key for ES256
  return await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'ECDSA',
      namedCurve: 'P-256'
    },
    false,
    ['sign']
  )
}

