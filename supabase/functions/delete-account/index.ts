// Deploy: supabase functions deploy delete-account
// (JWT doğrulaması açık kalır: sadece giriş yapmış kullanıcı kendi hesabını silebilir.)
// Kullanıcının auth kaydını siler; profil ve bağlı tüm veriler ON DELETE CASCADE ile silinir.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Token'ın sahibini sunucu doğrular; istemcinin gönderdiği bir user id'ye güvenilmez
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return json({ error: "Unauthorized" }, 401);

  const { error } = await admin.auth.admin.deleteUser(userData.user.id);
  if (error) return json({ error: error.message }, 500);

  return json({ deleted: true });
});
