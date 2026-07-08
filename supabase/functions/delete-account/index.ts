// THE SEMINAR — account deletion Edge Function (CONTRACTS §4.2).
//
// POST /functions/v1/delete-account — auth: user JWT, no body.
// Deletes all rows owned by the caller (enrollments cascade to
// sessions/turns/essays; highlights; reading_progress; usage_daily), then
// deletes the auth user via the admin API (service role).
// Response: { "deleted": true }. Errors: 4xx/5xx JSON.

import { callerClient, serviceClient } from "../_shared/retrieval.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "POST only" });
  }

  // Verify the caller's JWT.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(401, { error: "missing Authorization header" });
  }
  let userId: string;
  try {
    const caller = callerClient(authHeader);
    const { data, error } = await caller.auth.getUser();
    if (error || !data?.user) {
      return jsonResponse(401, { error: "invalid or expired JWT" });
    }
    userId = data.user.id;
  } catch (e) {
    return jsonResponse(401, { error: `auth failed: ${(e as Error).message}` });
  }

  const admin = serviceClient();

  try {
    // Enrollments cascade to sessions -> turns and to essays (0001/0002 FKs).
    const deletions: [string, string][] = [
      ["enrollments", "user_id"],
      ["highlights", "user_id"],
      ["reading_progress", "user_id"],
      ["usage_daily", "user_id"],
      ["profile_evidence", "user_id"],
      ["reader_profiles", "user_id"],
    ];
    for (const [table, column] of deletions) {
      const { error } = await admin.from(table).delete().eq(column, userId);
      if (error) {
        return jsonResponse(500, {
          error: `failed to delete ${table}: ${error.message}`,
        });
      }
    }

    // Finally, delete the auth user itself (also cascades any stragglers via
    // the auth.users ON DELETE CASCADE FKs).
    const { error: adminErr } = await admin.auth.admin.deleteUser(userId);
    if (adminErr) {
      return jsonResponse(500, {
        error: `failed to delete auth user: ${adminErr.message}`,
      });
    }

    return jsonResponse(200, { deleted: true });
  } catch (e) {
    return jsonResponse(500, { error: (e as Error).message ?? "internal error" });
  }
});
