// Deploy: supabase functions deploy send-push --no-verify-jwt
// Sadece veritabanı trigger'ları çağırır; yetki `x-push-secret` header'ı ile doğrulanır.
// Gerekli secret'lar: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY, PUSH_WEBHOOK_SECRET
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import * as jose from "npm:jose@5";

interface PushPayload {
  recipient_user_id: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

interface DeviceToken {
  token: string;
  apns_env: "sandbox" | "production";
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Apple provider token'ı 20-60 dk arasında yeniden kullanılmalı; her istekte imzalamak
// TooManyProviderTokenUpdates hatasına yol açar.
let cachedJwt: { token: string; issuedAt: number } | null = null;

async function getApnsJwt(keyId: string, teamId: string, privateKey: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 45 * 60) return cachedJwt.token;

  const ecKey = await jose.importPKCS8(privateKey, "ES256");
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .sign(ecKey);
  cachedJwt = { token, issuedAt: now };
  return token;
}

// Sabit zamanlı karşılaştırma
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const provided = req.headers.get("x-push-secret") ?? "";
  if (!webhookSecret || !safeEqual(provided, webhookSecret)) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const bundleId = Deno.env.get("APNS_BUNDLE_ID");
    let privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!keyId || !teamId || !bundleId || !privateKey) {
      return json({ error: "APNs secrets missing in Supabase environment" }, 500);
    }

    // Normalizing private key formatting if newlines were lost
    if (!privateKey.includes("-----BEGIN PRIVATE KEY-----")) {
      privateKey = `-----BEGIN PRIVATE KEY-----\n${privateKey}\n-----END PRIVATE KEY-----`;
    }

    const payload: PushPayload = await req.json();
    if (!payload.recipient_user_id || !/^[0-9a-f-]{36}$/i.test(payload.recipient_user_id)) {
      return json({ error: "Invalid recipient" }, 400);
    }

    const restHeaders = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
    const tokenRes = await fetch(
      `${supabaseUrl}/rest/v1/device_tokens?user_id=eq.${payload.recipient_user_id}&select=token,apns_env`,
      { headers: restHeaders },
    );
    const tokens: DeviceToken[] = await tokenRes.json();
    const device = tokens?.[0];

    if (!device?.token) {
      return json({ error: "Device token not found for recipient" }, 404);
    }

    const jwt = await getApnsJwt(keyId, teamId, privateKey);
    const host = device.apns_env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

    const res = await fetch(`https://${host}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: payload.title, body: payload.body },
          sound: "default",
        },
        data: payload.data || {},
      }),
    });

    if (!res.ok) {
      const details = await res.text();
      // Uygulama silinmiş veya token geçersiz: bir daha denemeyelim
      if (res.status === 410 || details.includes("BadDeviceToken") || details.includes("Unregistered")) {
        await fetch(`${supabaseUrl}/rest/v1/device_tokens?user_id=eq.${payload.recipient_user_id}`, {
          method: "DELETE",
          headers: restHeaders,
        });
      }
      return json({ error: "Failed to send APNs push", details }, 502);
    }

    return json({ message: "Notification sent successfully" });
  } catch (err: unknown) {
    return json({ error: (err as Error).message }, 500);
  }
});
