// Shared request authentication for edge functions invoked by database webhooks.
//
// Two callers are accepted:
//   1. Trusted internal callers that present the service-role key as a bearer token
//      (manual invocations, cron sweeps).
//   2. Database webhooks created by public.invoke_edge_webhook(), which send the
//      Vault-stored shared secret in an x-webhook-secret header. The secret is checked
//      through the service_role-only RPC verify_webhook_secret(), so no API key has to
//      be embedded in a trigger definition and key rotation cannot break delivery.

export async function isAuthorizedWebhookRequest(
  req: Request,
  supabase: any,
  serviceRoleKey: string
): Promise<boolean> {
  const authHeader = req.headers.get('authorization') ?? ''
  if (serviceRoleKey && authHeader === `Bearer ${serviceRoleKey}`) {
    return true
  }

  const webhookSecret = req.headers.get('x-webhook-secret') ?? ''
  if (!webhookSecret) {
    return false
  }

  try {
    const { data, error } = await supabase.rpc('verify_webhook_secret', { p_secret: webhookSecret })
    if (error) {
      console.error('verify_webhook_secret failed:', error.message)
      return false
    }
    return data === true
  } catch (err) {
    console.error('verify_webhook_secret threw:', err)
    return false
  }
}

export function unauthorizedResponse(corsHeaders: Record<string, string>): Response {
  return new Response(
    JSON.stringify({ error: 'Unauthorized' }),
    { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}
