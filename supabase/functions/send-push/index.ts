import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import * as jose from "npm:jose@5";

interface PushPayload {
  recipient_user_id?: string;
  push_token?: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

serve(async (req) => {
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const bundleId = Deno.env.get("APNS_BUNDLE_ID");
    let privateKey = Deno.env.get("APNS_PRIVATE_KEY");

    if (!keyId || !teamId || !bundleId || !privateKey) {
      return new Response(
        JSON.stringify({ error: "APNs secrets missing in Supabase environment" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Normalizing private key formatting if newlines were lost
    if (!privateKey.includes("-----BEGIN PRIVATE KEY-----")) {
      privateKey = `-----BEGIN PRIVATE KEY-----\n${privateKey}\n-----END PRIVATE KEY-----`;
    }

    const payload: PushPayload = await req.json();
    let deviceToken = payload.push_token;

    // If recipient_user_id is passed instead of push_token, query profiles table
    if (!deviceToken && payload.recipient_user_id) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      
      const profileRes = await fetch(
        `${supabaseUrl}/rest/v1/profiles?id=eq.${payload.recipient_user_id}&select=push_token`,
        {
          headers: {
            apikey: supabaseServiceKey,
            Authorization: `Bearer ${supabaseServiceKey}`,
          },
        }
      );
      
      const profiles = await profileRes.json();
      if (profiles && profiles.length > 0) {
        deviceToken = profiles[0].push_token;
      }
    }

    if (!deviceToken) {
      return new Response(
        JSON.stringify({ error: "Device token not found for recipient" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // Sign APNs JWT
    const ecKey = await jose.importPKCS8(privateKey, "ES256");
    const jwt = await new jose.SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyId })
      .setIssuer(teamId)
      .setIssuedAt()
      .sign(ecKey);

    const apnsBody = JSON.stringify({
      aps: {
        alert: {
          title: payload.title,
          body: payload.body,
        },
        sound: "default",
        badge: 1,
      },
      data: payload.data || {},
    });

    // Try sandbox first, then production if sandbox rejects
    const endpoints = [
      `https://api.sandbox.push.apple.com/3/device/${deviceToken}`,
      `https://api.push.apple.com/3/device/${deviceToken}`,
    ];

    let lastResponse = null;
    let success = false;

    for (const url of endpoints) {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: apnsBody,
      });

      if (res.ok) {
        success = true;
        break;
      } else {
        lastResponse = await res.text();
      }
    }

    if (!success) {
      return new Response(
        JSON.stringify({ error: "Failed to send APNs push", details: lastResponse }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ message: "Notification sent successfully" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
