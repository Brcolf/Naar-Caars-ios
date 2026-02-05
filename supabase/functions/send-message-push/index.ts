// Edge Function: send-message-push
// Listens for message push notifications and sends APNs push notifications
// Called via Supabase Database Webhook or HTTP request

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PushNotificationPayload {
  recipient_user_id: string
  conversation_id: string
  sender_name: string
  message_preview: string
  message_id: string
  sender_id: string
}

interface APNsPayload {
  aps: {
    alert: {
      title: string
      body: string
    }
    sound: string
    badge: number
    priority: number
    category?: string
  }
  type: string
  conversation_id: string
  message_id: string
  sender_id: string
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

    // Parse request body - handle both JSON and form data
    let payload: any
    
    try {
      // Try to parse as JSON first
      payload = await req.json()
      console.log('📨 Received webhook payload (JSON):', JSON.stringify(payload, null, 2))
    } catch (jsonError) {
      // If JSON parsing fails, try form data
      try {
        const formData = await req.formData()
        payload = {}
        for (const [key, value] of formData.entries()) {
          payload[key] = value
        }
        console.log('📨 Received webhook payload (Form Data):', JSON.stringify(payload, null, 2))
      } catch (formError) {
        // If both fail, try text
        const text = await req.text()
        console.log('📨 Received webhook payload (Text):', text)
        try {
          payload = JSON.parse(text)
        } catch (parseError) {
          throw new Error(`Failed to parse request body. JSON error: ${jsonError}, Form error: ${formError}, Text: ${text.substring(0, 200)}`)
        }
      }
    }

    const eventType = resolveEventType(payload)
    if (eventType && eventType !== 'INSERT') {
      return new Response(
        JSON.stringify({ skipped: true, reason: 'unsupported_event', eventType }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const tableName = resolveTableName(payload)
    if (tableName && tableName !== 'messages') {
      return new Response(
        JSON.stringify({ skipped: true, reason: 'unsupported_table', tableName }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const normalizedPayload = normalizeWebhookPayload(payload)
    
    // If webhook provides full payload, use it; otherwise fetch from database
    let recipient_user_id: string
    let conversation_id: string
    let sender_name: string
    let message_preview: string
    let message_id: string
    let sender_id: string

    if (payload.recipient_user_id && payload.conversation_id && payload.sender_name) {
      // Full payload provided (from trigger with pg_notify or custom webhook)
      recipient_user_id = payload.recipient_user_id
      conversation_id = payload.conversation_id
      sender_name = payload.sender_name
      message_preview = payload.message_preview || ''
      message_id = payload.message_id || ''
      sender_id = payload.sender_id || ''
    } else {
      // Partial payload from database webhook - fetch additional data
      // Database webhook provides NEW row, so we have message data
      // Handle different possible payload formats
      const messageData = normalizedPayload
      
      // Try multiple possible field names
      message_id = messageData.id || messageData.message_id || messageData.messageId
      conversation_id = messageData.conversation_id || messageData.conversationId
      sender_id = messageData.from_id || messageData.fromId || messageData.sender_id || messageData.senderId
      
      // Log what we found
      console.log('🔍 Extracted fields:', {
        message_id,
        conversation_id,
        sender_id,
        has_id: !!messageData.id,
        has_conversation_id: !!messageData.conversation_id,
        has_from_id: !!messageData.from_id,
        payload_keys: Object.keys(messageData)
      })
      
      if (!message_id || !conversation_id || !sender_id) {
        const missing = []
        if (!message_id) missing.push('id/message_id')
        if (!conversation_id) missing.push('conversation_id')
        if (!sender_id) missing.push('from_id/sender_id')
        throw new Error(`Missing required message data from webhook: ${missing.join(', ')}. Received payload keys: ${Object.keys(messageData).join(', ')}`)
      }

      // Fetch sender name from profiles
      const { data: senderProfile, error: profileError } = await supabase
        .from('profiles')
        .select('name')
        .eq('id', sender_id)
        .single()

      sender_name = senderProfile?.name || 'Someone'
      
      // Get message preview
      const messageText = messageData.text || ''
      message_preview = messageText.length > 50 ? messageText.substring(0, 50) + '...' : messageText

      // Get recipient user IDs (all participants except sender)
      const { data: participants, error: participantsError } = await supabase
        .from('conversation_participants')
        .select('user_id, last_seen')
        .eq('conversation_id', conversation_id)
        .neq('user_id', sender_id)

      if (participantsError || !participants || participants.length === 0) {
        console.log('⏭️ No recipients found for conversation')
        return new Response(
          JSON.stringify({ skipped: true, reason: 'no_recipients' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Process all recipients and send pushes
      const allPushResults = []
      
      for (const participant of participants) {
        const currentRecipientId = participant.user_id

        // Check if this recipient is actively viewing
        if (participant.last_seen) {
          const lastSeen = new Date(participant.last_seen)
          const now = new Date()
          const secondsSinceLastSeen = (now.getTime() - lastSeen.getTime()) / 1000

          if (secondsSinceLastSeen < 60) {
            console.log(`⏭️ Skipping push for user ${currentRecipientId} - viewed ${secondsSinceLastSeen.toFixed(1)}s ago`)
            allPushResults.push({ recipient: currentRecipientId, skipped: true, reason: 'user_viewing' })
            continue
          }
        }

        // Send push for this recipient
        try {
          const result = await sendPushToRecipient(
            currentRecipientId,
            conversation_id,
            sender_name,
            message_preview,
            message_id,
            sender_id,
            supabase
          )
          allPushResults.push({ recipient: currentRecipientId, ...result })
        } catch (error) {
          console.error(`Error sending push to ${currentRecipientId}:`, error)
          allPushResults.push({ recipient: currentRecipientId, error: error.message })
        }
      }

      // Return summary of all pushes
      const successes = allPushResults.filter(r => r.sent).length
      const skipped = allPushResults.filter(r => r.skipped).length
      const errors = allPushResults.filter(r => r.error).length

      return new Response(
        JSON.stringify({
          processed: true,
          total_recipients: participants.length,
          successes,
          skipped,
          errors,
          results: allPushResults
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Full payload case - process single recipient
    console.log(`📨 Processing push notification for user ${recipient_user_id}, conversation ${conversation_id}`)

    console.log(`📨 Processing push notification for user ${recipient_user_id}, conversation ${conversation_id}`)

    // Double-check if recipient is actively viewing (defense in depth)
    // The trigger already checks this, but we verify again for safety
    const { data: participant, error: participantError } = await supabase
      .from('conversation_participants')
      .select('last_seen')
      .eq('conversation_id', conversation_id)
      .eq('user_id', recipient_user_id)
      .single()

    if (participantError) {
      console.error('Error checking participant:', participantError)
      // Continue anyway - don't block push if we can't check
    } else if (participant?.last_seen) {
      const lastSeen = new Date(participant.last_seen)
      const now = new Date()
      const secondsSinceLastSeen = (now.getTime() - lastSeen.getTime()) / 1000

      // If viewed within last 60 seconds, skip push (user is viewing)
      if (secondsSinceLastSeen < 60) {
        console.log(`⏭️ Skipping push - user viewed conversation ${secondsSinceLastSeen.toFixed(1)}s ago`)
        return new Response(
          JSON.stringify({ skipped: true, reason: 'user_viewing', seconds_ago: secondsSinceLastSeen }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Get recipient's push tokens
    const { data: tokens, error: tokenError } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', recipient_user_id)

    if (tokenError) {
      console.error('Error fetching push tokens:', tokenError)
      throw new Error(`Failed to fetch push tokens: ${tokenError.message}`)
    }

    if (!tokens || tokens.length === 0) {
      console.log(`⏭️ Skipping push - no push tokens found for user ${recipient_user_id}`)
      return new Response(
        JSON.stringify({ skipped: true, reason: 'no_tokens' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Send push using helper function
    const result = await sendPushToRecipient(
      recipient_user_id,
      conversation_id,
      sender_name,
      message_preview,
      message_id,
      sender_id,
      supabase
    )

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error sending push notification:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})

function normalizeWebhookPayload(payload: any): any {
  if (!payload || typeof payload !== 'object') {
    return payload
  }
  if (payload.record) {
    return payload.record
  }
  if (payload.new) {
    return payload.new
  }
  if (payload.data?.record) {
    return payload.data.record
  }
  if (payload.data?.new) {
    return payload.data.new
  }
  return payload
}

function resolveEventType(payload: any): string | undefined {
  return payload?.type || payload?.eventType || payload?.event_type || payload?.data?.type || payload?.data?.eventType || payload?.data?.event_type
}

function resolveTableName(payload: any): string | undefined {
  return payload?.table || payload?.data?.table || payload?.table_name || payload?.data?.table_name
}

async function sendPushToRecipient(
  recipientUserId: string,
  conversationId: string,
  senderName: string,
  messagePreview: string,
  messageId: string,
  senderId: string,
  supabase: any
): Promise<{ sent: boolean; devices?: number; successes?: number; failures?: number; skipped?: boolean; reason?: string }> {
  // Get recipient's push tokens
  const { data: tokens, error: tokenError } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', recipientUserId)

  if (tokenError) {
    console.error('Error fetching push tokens:', tokenError)
    throw new Error(`Failed to fetch push tokens: ${tokenError.message}`)
  }

  if (!tokens || tokens.length === 0) {
    console.log(`⏭️ Skipping push - no push tokens found for user ${recipientUserId}`)
    return { sent: false, skipped: true, reason: 'no_tokens' }
  }

  // Get unread message count for badge (all conversations, not just this one)
  const { count: unreadMessageCount } = await supabase
    .from('messages')
    .select('id', { count: 'exact', head: true })
    .neq('from_id', recipientUserId)
    .not('read_by', 'cs', `{${recipientUserId}}`)

  // Get unread notification count for badge (non-message notifications)
  const { count: unreadNotificationCount } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', recipientUserId)
    .eq('read', false)
    .not('type', 'in', '("message","added_to_conversation")')

  const badgeCount = (unreadMessageCount ?? 0) + (unreadNotificationCount ?? 0)

  // Prepare APNs payload
  const apnsPayload: APNsPayload = {
    aps: {
      alert: {
        title: `Message from ${senderName}`,
        body: messagePreview
      },
      sound: 'default',
      badge: badgeCount,
      priority: 10, // High priority for immediate delivery
      category: 'MESSAGE'
    },
    type: 'message',
    conversation_id: conversationId,
    message_id: messageId,
    sender_id: senderId
  }

  // Send push to all devices for this user
  const pushResults = await Promise.allSettled(
    tokens.map(async (tokenRow) => {
      return await sendAPNsPush(tokenRow.token, apnsPayload)
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

  console.log(`✅ Sent push notifications to user ${recipientUserId}: ${successes} succeeded, ${failures} failed`)

  return {
    sent: true,
    devices: tokens.length,
    successes,
    failures
  }
}

async function sendAPNsPush(token: string, payload: APNsPayload): Promise<void> {
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsKey = Deno.env.get('APNS_KEY') // Base64 encoded .p8 file content
  const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')
  const apnsProduction = Deno.env.get('APNS_PRODUCTION') === 'true'

  if (!apnsTeamId || !apnsKeyId || !apnsKey || !apnsBundleId) {
    throw new Error('Missing APNs environment variables')
  }

  // APNs endpoint (production or sandbox)
  const apnsUrl = apnsProduction
    ? `https://api.push.apple.com/3/device/${token}`
    : `https://api.sandbox.push.apple.com/3/device/${token}`

  // Create JWT token for APNs authentication
  const jwt = await createAPNsJWT(apnsTeamId, apnsKeyId, apnsKey)

  // Send to APNs
  const response = await fetch(apnsUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwt}`,
      'apns-topic': apnsBundleId,
      'apns-priority': '10', // High priority
      'apns-push-type': 'alert',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`APNs error (${response.status}): ${errorText}`)
  }

  // Handle APNs response codes
  const apnsId = response.headers.get('apns-id')
  console.log(`✅ APNs push sent successfully (ID: ${apnsId})`)
}

async function createAPNsJWT(teamId: string, keyId: string, key: string): Promise<string> {
  // Use djwt library for JWT creation with ES256
  const { create, getNumericDate } = await import('https://deno.land/x/djwt@v2.8/mod.ts')
  
  // Decode base64 key if needed
  let privateKeyPem: string
  try {
    // Try to decode as base64 first
    privateKeyPem = atob(key)
  } catch {
    // If not base64, use as-is (might already be decoded)
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

