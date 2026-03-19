// Edge Function: revoke-apple-token
// Revokes an Apple Sign-In token per Apple's requirements.
// Called from the iOS app before account deletion or Apple ID unlinking.
//
// Note: verify_jwt is disabled because this project uses ES256 auth JWTs,
// which the edge function gateway cannot verify with the HS256 JWT_SECRET.
// Security relies on: (1) the function requires a valid Apple authorization
// code to do anything useful, and (2) the iOS app is authenticated before
// calling this function.
//
// Prerequisites:
//   - Secrets (shared with APNs push config): APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY_ID, APNS_KEY
//   - APNS_KEY must be the full .p8 PEM including BEGIN/END markers.
//   - The .p8 key must have "Sign in with Apple" capability enabled (not just APNs).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/** Structured response helper */
function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

/** Base64url-encode a Uint8Array */
function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const requestId = crypto.randomUUID();
  const log = (step: string, detail?: string) =>
    console.log(
      JSON.stringify({ request_id: requestId, step, ...(detail ? { detail } : {}) }),
    );
  const logError = (step: string, detail?: string) =>
    console.error(
      JSON.stringify({ request_id: requestId, step, ...(detail ? { detail } : {}) }),
    );

  try {
    // --- Validate request ---
    const body = await req.json();
    const authorizationCode: string | undefined = body.authorization_code;

    if (!authorizationCode) {
      logError("invalid_request", "Missing authorization_code in request body");
      return jsonResponse(
        { status: "invalid_request", error: "Missing authorization_code", request_id: requestId },
        400,
      );
    }

    log("request_received");

    // --- Validate secrets ---
    // These secrets are shared with APNs push configuration (already set in Supabase).
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const clientId = Deno.env.get("APNS_BUNDLE_ID");
    const keyId = Deno.env.get("APNS_KEY_ID");
    const privateKeyPem = Deno.env.get("APNS_KEY");

    const missing: string[] = [];
    if (!teamId) missing.push("APNS_TEAM_ID");
    if (!clientId) missing.push("APNS_BUNDLE_ID");
    if (!keyId) missing.push("APNS_KEY_ID");
    if (!privateKeyPem) missing.push("APNS_KEY");

    if (missing.length > 0) {
      logError("config_error", `Missing env vars: ${missing.join(", ")}`);
      return jsonResponse(
        { status: "config_error", error: "Apple Sign-In secrets not configured", request_id: requestId },
        500,
      );
    }

    log("secrets_loaded");

    // --- Generate client_secret JWT (ES256) ---
    const now = Math.floor(Date.now() / 1000);
    const header = { alg: "ES256", kid: keyId };
    const payload = {
      iss: teamId,
      iat: now,
      exp: now + 300,
      aud: "https://appleid.apple.com",
      sub: clientId,
    };

    const encoder = new TextEncoder();
    const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
    const payloadB64 = base64url(encoder.encode(JSON.stringify(payload)));
    const signingInput = `${headerB64}.${payloadB64}`;

    // Import the private key.
    // APNS_KEY may be base64-encoded PEM (as used by the push notification functions)
    // or raw PEM. Try base64 decode first; fall back to raw.
    let pemString: string;
    try {
      pemString = atob(privateKeyPem!);
    } catch {
      pemString = privateKeyPem!;
    }
    // Handle literal "\n" from env vars set via CLI
    pemString = pemString.replace(/\\n/g, "\n");
    const pemClean = pemString
      .replace(/-----BEGIN PRIVATE KEY-----/, "")
      .replace(/-----END PRIVATE KEY-----/, "")
      .replace(/\s/g, "");

    let key: CryptoKey;
    try {
      const keyData = Uint8Array.from(atob(pemClean), (c) => c.charCodeAt(0));
      key = await crypto.subtle.importKey(
        "pkcs8",
        keyData,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
      );
    } catch (keyError) {
      logError("key_import_failed", (keyError as Error).message);
      return jsonResponse(
        { status: "config_error", error: "Failed to import Apple private key — check APNS_KEY format", request_id: requestId },
        500,
      );
    }

    // Web Crypto ECDSA returns IEEE P1363 format (raw r||s, 64 bytes for P-256),
    // which is exactly what ES256 JWT expects — no DER conversion needed.
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      encoder.encode(signingInput),
    );
    const sigB64 = base64url(new Uint8Array(signature));
    const clientSecret = `${signingInput}.${sigB64}`;

    log("jwt_generated");

    // --- Step 1: Exchange authorization code for tokens ---
    log("token_exchange_request");
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId!,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
    });

    if (!tokenRes.ok) {
      const errBody = await tokenRes.text();
      logError("token_exchange_failed", `HTTP ${tokenRes.status}: ${errBody.substring(0, 500)}`);
      return jsonResponse(
        { status: "token_exchange_failed", error: "Apple token exchange failed", apple_status: tokenRes.status, request_id: requestId },
        502,
      );
    }

    const tokenData = await tokenRes.json();
    const refreshToken: string | undefined = tokenData.refresh_token;

    if (!refreshToken) {
      logError("token_exchange_failed", "No refresh_token in Apple response");
      return jsonResponse(
        { status: "token_exchange_failed", error: "No refresh_token received from Apple", request_id: requestId },
        502,
      );
    }

    log("token_exchange_success");

    // --- Step 2: Revoke the token ---
    log("revoke_request");
    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId!,
        client_secret: clientSecret,
        token: refreshToken,
        token_type_hint: "refresh_token",
      }),
    });

    if (!revokeRes.ok) {
      const errBody = await revokeRes.text();
      logError("revoke_failed", `HTTP ${revokeRes.status}: ${errBody.substring(0, 500)}`);
      return jsonResponse(
        { status: "revoke_failed", error: "Apple token revocation failed", apple_status: revokeRes.status, request_id: requestId },
        502,
      );
    }

    log("revoke_success");
    return jsonResponse(
      { status: "success", success: true, request_id: requestId },
      200,
    );
  } catch (error) {
    logError("unexpected_error", (error as Error).message);
    return jsonResponse(
      { status: "unexpected_error", error: (error as Error).message, request_id: requestId },
      500,
    );
  }
});
