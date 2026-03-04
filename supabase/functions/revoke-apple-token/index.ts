// Edge Function: revoke-apple-token
// Revokes an Apple Sign-In token per Apple's account deletion requirements.
// Called from the iOS app before account deletion.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { authorization_code } = await req.json();
    if (!authorization_code) {
      return new Response(
        JSON.stringify({ error: "Missing authorization_code" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const teamId = Deno.env.get("APPLE_TEAM_ID");
    const clientId = Deno.env.get("APPLE_CLIENT_ID");
    const keyId = Deno.env.get("APPLE_KEY_ID");
    const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY");

    if (!teamId || !clientId || !keyId || !privateKeyPem) {
      return new Response(
        JSON.stringify({ error: "Apple Sign-In secrets not configured" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Generate client_secret JWT
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
    const headerB64 = btoa(String.fromCharCode(...encoder.encode(JSON.stringify(header))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const payloadB64 = btoa(String.fromCharCode(...encoder.encode(JSON.stringify(payload))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    const signingInput = `${headerB64}.${payloadB64}`;

    // Import the private key
    const pemClean = privateKeyPem
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, "");
    const keyData = Uint8Array.from(atob(pemClean), (c) => c.charCodeAt(0));

    const key = await crypto.subtle.importKey(
      "pkcs8",
      keyData,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"]
    );

    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      encoder.encode(signingInput)
    );

    // Convert DER signature to raw r||s format for JWT
    const sigArray = new Uint8Array(signature);
    const sigB64 = btoa(String.fromCharCode(...sigArray))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    const clientSecret = `${signingInput}.${sigB64}`;

    // Step 1: Exchange authorization code for tokens
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code: authorization_code,
        grant_type: "authorization_code",
      }),
    });

    if (!tokenRes.ok) {
      const err = await tokenRes.text();
      console.error("Token exchange failed:", err);
      return new Response(
        JSON.stringify({ error: "Token exchange failed", details: err }),
        { status: 502, headers: corsHeaders }
      );
    }

    const { refresh_token } = await tokenRes.json();

    if (!refresh_token) {
      return new Response(
        JSON.stringify({ error: "No refresh_token received from Apple" }),
        { status: 502, headers: corsHeaders }
      );
    }

    // Step 2: Revoke the token
    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        token: refresh_token,
        token_type_hint: "refresh_token",
      }),
    });

    if (!revokeRes.ok) {
      const err = await revokeRes.text();
      console.error("Revocation failed:", err);
      return new Response(
        JSON.stringify({ error: "Revocation failed", details: err }),
        { status: 502, headers: corsHeaders }
      );
    }

    console.log("Apple token revoked successfully");
    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error("Error in revoke-apple-token:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: corsHeaders }
    );
  }
});
