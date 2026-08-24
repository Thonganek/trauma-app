import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization") || "";

  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Server configuration is incomplete" }, 500);
  if (!authorization.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data: callerData, error: callerError } = await adminClient.auth.getUser(token);
  const caller = callerData.user;

  if (callerError || !caller) return json({ error: "Invalid session" }, 401);
  if (caller.app_metadata?.role !== "admin") return json({ error: "Admin permission required" }, 403);

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (payload.action === "list") {
    const { data, error } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (error) return json({ error: error.message }, 400);
    const users = data.users
      .map((user) => ({
        id: user.id,
        username: user.app_metadata?.username || user.email?.split("@")[0] || "",
        email: user.email || "",
        displayName: user.user_metadata?.display_name || "",
        role: user.app_metadata?.role || "staff",
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at || null,
      }))
      .sort((a, b) => a.username.localeCompare(b.username));
    return json({ users });
  }

  if (payload.action === "create") {
    const username = String(payload.username || "").trim().toLowerCase();
    const displayName = String(payload.displayName || "").trim().slice(0, 80);
    const password = String(payload.password || "");
    const role = payload.role === "admin" ? "admin" : "staff";

    if (!/^[a-z0-9._-]{3,32}$/.test(username)) {
      return json({ error: "Username must use 3-32 lowercase letters, numbers, dots, hyphens or underscores" }, 400);
    }
    if (password.length < 8 || password.length > 128) {
      return json({ error: "Password must contain 8-128 characters" }, 400);
    }

    const email = `${username}@traumalink.app`;
    const { data, error } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { username, role },
      user_metadata: { display_name: displayName },
    });
    if (error) return json({ error: error.message }, 400);

    return json({
      user: {
        id: data.user.id,
        username,
        email,
        displayName,
        role,
        createdAt: data.user.created_at,
      },
    }, 201);
  }

  return json({ error: "Unsupported action" }, 400);
});
