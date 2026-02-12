// Shared APNs utilities for edge functions
// Contains: CORS headers, APNs push sending, JWT creation, key import

export const corsHeaders = {
  'Access-Control-Allow-Origin': Deno.env.get('ALLOWED_ORIGIN') ?? '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Send an APNs push notification to a specific device token.
 * Optionally cleans up invalid tokens (410 response) if supabase client is provided.
 */
export async function sendAPNsPush(
  token: string,
  payload: Record<string, any>,
  supabase?: any
): Promise<void> {
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsKey = Deno.env.get('APNS_KEY')
  const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')
  const apnsProduction = Deno.env.get('APNS_PRODUCTION') === 'true'

  if (!apnsTeamId || !apnsKeyId || !apnsKey || !apnsBundleId) {
    throw new Error('Missing APNs environment variables')
  }

  // Create JWT token for APNs authentication
  const jwt = await createAPNsJWT(apnsTeamId, apnsKeyId, apnsKey)

  // Determine push type
  let pushType = 'alert'
  if (payload.aps?.['content-available'] === 1 && !payload.aps?.alert) {
    pushType = 'background'
  }

  const endpointModes = apnsProduction
    ? ['production', 'sandbox'] as const
    : ['sandbox', 'production'] as const

  let lastError: Error | null = null

  for (const mode of endpointModes) {
    const apnsUrl =
      mode === 'production'
        ? `https://api.push.apple.com/3/device/${token}`
        : `https://api.sandbox.push.apple.com/3/device/${token}`

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

    if (response.ok) {
      const apnsId = response.headers.get('apns-id')
      console.log(`✅ APNs push sent successfully via ${mode} (ID: ${apnsId})`)
      return
    }

    const errorText = await response.text()
    let errorReason = ''
    try {
      errorReason = JSON.parse(errorText)?.reason ?? ''
    } catch {
      errorReason = ''
    }

    if (response.status === 410 && supabase) {
      // Token is no longer valid - remove it
      console.log(`🗑️ Removing invalid token: ${token.substring(0, 8)}...`)
      await supabase
        .from('push_tokens')
        .delete()
        .eq('token', token)
    }

    const modeError = new Error(`APNs ${mode} error (${response.status}): ${errorText}`)
    lastError = modeError

    const isEnvironmentMismatch =
      response.status === 400 &&
      (errorReason === 'BadDeviceToken' || errorReason === 'DeviceTokenNotForTopic')
    if (isEnvironmentMismatch) {
      console.warn(`⚠️ APNs ${mode} rejected token with ${errorReason}; trying alternate environment.`)
      continue
    }

    throw modeError
  }

  throw lastError ?? new Error('APNs push failed in all environments')
}

/**
 * Create a JWT token for APNs authentication using ES256 algorithm.
 */
export async function createAPNsJWT(teamId: string, keyId: string, key: string): Promise<string> {
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

  const header = { alg: 'ES256' as const, kid: keyId }
  const payload = { iss: teamId, iat: getNumericDate(new Date()) }

  return await create(header, payload, cryptoKey)
}

/**
 * Import a PEM-encoded EC private key for ES256 signing.
 */
export async function importECPrivateKey(pemKey: string): Promise<CryptoKey> {
  const keyData = pemKey
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  const binaryKey = Uint8Array.from(atob(keyData), c => c.charCodeAt(0))

  return await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )
}

/**
 * Resolve event type from various webhook payload formats.
 */
export function resolveEventType(payload: any): string | undefined {
  return payload?.type || payload?.eventType || payload?.event_type ||
    payload?.data?.type || payload?.data?.eventType || payload?.data?.event_type
}

/**
 * Resolve table name from various webhook payload formats.
 */
export function resolveTableName(payload: any): string | undefined {
  return payload?.table || payload?.table_name ||
    payload?.data?.table || payload?.data?.table_name
}

/**
 * Process items in batches with concurrency control.
 */
export async function processBatch<T, R>(
  items: T[],
  batchSize: number,
  fn: (item: T) => Promise<R>
): Promise<PromiseSettledResult<R>[]> {
  const allResults: PromiseSettledResult<R>[] = []
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize)
    const results = await Promise.allSettled(batch.map(fn))
    allResults.push(...results)
  }
  return allResults
}
