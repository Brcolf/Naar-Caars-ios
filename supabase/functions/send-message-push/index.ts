// Edge Function: send-message-push
// Listens for message push notifications and sends APNs push notifications
// Called via Supabase Database Webhook or HTTP request

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { corsHeaders, sendAPNsPush, resolveEventType, resolveTableName, processBatch } from '../_shared/apns.ts'
import { getBadgeCount, getBadgeCountsBatch } from '../_shared/badges.ts'
import { NOTIFICATION_TYPES } from '../_shared/notificationTypes.ts'

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
      payload = await req.json()
      console.log('📨 Received webhook payload (JSON):', JSON.stringify(payload, null, 2))
    } catch (jsonError) {
      try {
        const formData = await req.formData()
        payload = {}
        for (const [key, value] of formData.entries()) {
          payload[key] = value
        }
        console.log('📨 Received webhook payload (Form Data):', JSON.stringify(payload, null, 2))
      } catch (formError) {
        const text = await req.text()
        console.log('📨 Received webhook payload (Text):', text)
        try {
          payload = JSON.parse(text)
        } catch (parseError) {
          throw new Error(`Failed to parse request body. JSON error: ${jsonError}, Form error: ${formError}, Text: ${text.substring(0, 200)}`)
        }
      }
    }

    // Input validation
    if (payload.sender_name && payload.sender_name.length > 100) {
      payload.sender_name = payload.sender_name.substring(0, 100);
    }
    if (payload.message_preview && payload.message_preview.length > 500) {
      payload.message_preview = payload.message_preview.substring(0, 500);
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

    const hasFullPayload = Boolean(payload.recipient_user_id && payload.conversation_id && payload.sender_name)
    const fullPayloadSenderId = payload.sender_id || payload.from_id
    const shouldUseFullPayload =
      hasFullPayload && (!fullPayloadSenderId || payload.recipient_user_id !== fullPayloadSenderId)

    if (hasFullPayload && !shouldUseFullPayload) {
      console.warn(
        '⚠️ Ignoring full payload because recipient_user_id matches sender_id; ' +
          'falling back to recipient lookup from conversation participants.'
      )
    }

    if (shouldUseFullPayload) {
      // Full payload provided (from trigger with pg_notify or custom webhook)
      recipient_user_id = payload.recipient_user_id
      conversation_id = payload.conversation_id
      sender_name = payload.sender_name
      message_preview = payload.message_preview || ''
      message_id = payload.message_id || ''
      sender_id = payload.sender_id || ''
    } else {
      // Partial payload from database webhook - fetch additional data
      const messageData = normalizedPayload
      
      message_id = messageData.id || messageData.message_id || messageData.messageId
      conversation_id = messageData.conversation_id || messageData.conversationId
      sender_id = messageData.from_id || messageData.fromId || messageData.sender_id || messageData.senderId
      
      console.log('🔍 Extracted fields:', {
        message_id, conversation_id, sender_id,
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
      const { data: senderProfile } = await supabase
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

      // Filter out users who are actively viewing
      const eligibleParticipants = participants.filter(p => {
        if (!p.last_seen) return true
        const secondsSinceLastSeen = (Date.now() - new Date(p.last_seen).getTime()) / 1000
        if (secondsSinceLastSeen < 60) {
          console.log(`⏭️ Skipping push for user ${p.user_id} - viewed ${secondsSinceLastSeen.toFixed(1)}s ago`)
          return false
        }
        return true
      })

      // Pre-fetch badge counts and push tokens for all eligible recipients in batch
      const recipientIds = eligibleParticipants.map(p => p.user_id)
      const [badgeCounts, tokensByUser] = await Promise.all([
        getBadgeCountsBatch(supabase, recipientIds),
        batchFetchPushTokens(supabase, recipientIds)
      ])

      // Process all recipients in parallel with batching (max 10 concurrent)
      const allPushResults: any[] = []

      // Add skipped users
      for (const p of participants) {
        if (!eligibleParticipants.find(e => e.user_id === p.user_id)) {
          allPushResults.push({ recipient: p.user_id, skipped: true, reason: 'user_viewing' })
        }
      }

      const batchResults = await processBatch(eligibleParticipants, 10, async (participant) => {
        const badge = badgeCounts.get(participant.user_id) ?? 0
        const tokens = tokensByUser.get(participant.user_id) ?? []
        return await sendPushToRecipient(
          participant.user_id, conversation_id, sender_name, message_preview,
          message_id, sender_id, badge, supabase, tokens
        )
      })

      batchResults.forEach((result, i) => {
        const recipient = eligibleParticipants[i].user_id
        if (result.status === 'fulfilled') {
          allPushResults.push({ recipient, ...result.value })
        } else {
          allPushResults.push({ recipient, error: (result.reason as Error).message })
        }
      })

      const successes = allPushResults.filter(r => r.sent).length
      const skipped = allPushResults.filter(r => r.skipped).length
      const errors = allPushResults.filter(r => r.error).length

      return new Response(
        JSON.stringify({
          processed: true,
          total_recipients: participants.length,
          successes, skipped, errors,
          results: allPushResults
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Full payload case - process single recipient
    console.log(`📨 Processing push notification for user ${recipient_user_id}, conversation ${conversation_id}`)

    // Double-check if recipient is actively viewing
    const { data: participant, error: participantError } = await supabase
      .from('conversation_participants')
      .select('last_seen')
      .eq('conversation_id', conversation_id)
      .eq('user_id', recipient_user_id)
      .single()

    if (participantError) {
      console.error('Error checking participant:', participantError)
    } else if (participant?.last_seen) {
      const secondsSinceLastSeen = (Date.now() - new Date(participant.last_seen).getTime()) / 1000
      if (secondsSinceLastSeen < 60) {
        console.log(`⏭️ Skipping push - user viewed conversation ${secondsSinceLastSeen.toFixed(1)}s ago`)
        return new Response(
          JSON.stringify({ skipped: true, reason: 'user_viewing', seconds_ago: secondsSinceLastSeen }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Get badge count for this user
    const badgeCount = await getBadgeCount(supabase, recipient_user_id)

    const result = await sendPushToRecipient(
      recipient_user_id, conversation_id, sender_name, message_preview,
      message_id, sender_id, badgeCount, supabase
    )

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error sending push notification:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/** Batch-fetch push tokens for multiple users in a single query */
async function batchFetchPushTokens(
  supabase: any,
  userIds: string[]
): Promise<Map<string, string[]>> {
  const tokensByUser = new Map<string, string[]>()
  if (userIds.length === 0) return tokensByUser

  const { data: rows, error } = await supabase
    .from('push_tokens')
    .select('user_id, token')
    .in('user_id', userIds)

  if (error) {
    console.error('Failed to batch-fetch push tokens:', error.message)
    return tokensByUser
  }

  for (const row of (rows ?? [])) {
    const existing = tokensByUser.get(row.user_id) ?? []
    existing.push(row.token)
    tokensByUser.set(row.user_id, existing)
  }

  return tokensByUser
}

function normalizeWebhookPayload(payload: any): any {
  if (!payload || typeof payload !== 'object') return payload
  if (payload.record) return payload.record
  if (payload.new) return payload.new
  if (payload.data?.record) return payload.data.record
  if (payload.data?.new) return payload.data.new
  return payload
}

async function sendPushToRecipient(
  recipientUserId: string,
  conversationId: string,
  senderName: string,
  messagePreview: string,
  messageId: string,
  senderId: string,
  badgeCount: number,
  supabase: any,
  prefetchedTokens?: string[]
): Promise<{ sent: boolean; devices?: number; successes?: number; failures?: number; skipped?: boolean; reason?: string }> {
  // Use pre-fetched tokens if available, otherwise fetch individually (single-recipient path)
  let tokenStrings: string[]
  if (prefetchedTokens !== undefined) {
    tokenStrings = prefetchedTokens
  } else {
    const { data: tokenRows, error: tokenError } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', recipientUserId)

    if (tokenError) {
      throw new Error(`Failed to fetch push tokens: ${tokenError.message}`)
    }
    tokenStrings = (tokenRows ?? []).map((row: { token: string }) => row.token)
  }

  if (tokenStrings.length === 0) {
    console.log(`⏭️ Skipping push - no push tokens found for user ${recipientUserId}`)
    return { sent: false, skipped: true, reason: 'no_tokens' }
  }

  // Prepare APNs payload (badge count already provided)
  const apnsPayload: APNsPayload = {
    aps: {
      alert: { title: `Message from ${senderName}`, body: messagePreview },
      sound: 'default',
      badge: badgeCount,
      priority: 10,
      category: 'MESSAGE'
    },
    type: NOTIFICATION_TYPES.MESSAGE,
    conversation_id: conversationId,
    message_id: messageId,
    sender_id: senderId
  }

  // Send push to all devices for this user
  const pushResults = await Promise.allSettled(
    tokenStrings.map(async (token: string) => {
      return await sendAPNsPush(token, apnsPayload, supabase)
    })
  )

  const successes = pushResults.filter(r => r.status === 'fulfilled').length
  const failures = pushResults.filter(r => r.status === 'rejected').length

  pushResults.forEach((result, index) => {
    if (result.status === 'rejected') {
      console.error(`Failed to send push to token ${tokenStrings[index].substring(0, 8)}...:`, result.reason)
    }
  })

  console.log(`✅ Sent push notifications to user ${recipientUserId}: ${successes} succeeded, ${failures} failed`)

  return { sent: successes > 0, devices: tokenStrings.length, successes, failures }
}
