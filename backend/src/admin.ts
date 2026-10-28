import { Env, fail, isAdmin, json, normaliseEmail, readJson, sha256Hex } from "./util";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 characters, no 0/O/1/I

function makeCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let code = "";
  for (const b of bytes) code += CODE_ALPHABET[b % 32];
  return code.match(/.{4}/g)!.join("-");
}

/** Admin endpoints. They need the admin token (the SYNC_TOKEN secret), not a user session. */
export async function handleAdmin(request: Request, env: Env, pathname: string): Promise<Response> {
  if (!(await isAdmin(request, env))) return fail(401, "Unauthorised");
  const method = request.method;

  if (pathname === "/admin/invites" && method === "POST") {
    const body = (await readJson<{ email?: unknown; role?: unknown; days?: unknown }>(request)) ?? {};
    const email = body.email === undefined || body.email === "" ? null : normaliseEmail(body.email);
    if (body.email !== undefined && body.email !== "" && !email) return fail(400, "Bad email");
    const role = body.role === "admin" ? "admin" : "user";
    const days = Math.min(Math.max(Number(body.days) || 7, 1), 30);
    const code = makeCode();
    const now = Date.now();
    const expires = now + days * 86_400_000;
    await env.DB.prepare("INSERT INTO invites(code_hash, email, role, created_at, expires_at) VALUES(?1, ?2, ?3, ?4, ?5)")
      .bind(await sha256Hex(code.replace(/-/g, "")), email, role, now, expires)
      .run();
    return json({ code, email, role, expires }, 201);
  }

  if (pathname === "/admin/users" && method === "GET") {
    const { results } = await env.DB.prepare(
      `SELECT u.id, u.email, u.role, u.status, u.created_at,
              (SELECT COALESCE(SUM(v.size), 0) FROM file_versions v WHERE v.user_id = u.id) AS bytes
       FROM users u ORDER BY u.created_at`,
    ).all();
    return json({ users: results });
  }

  const match = pathname.match(/^\/admin\/users\/([A-Za-z0-9_-]{1,40})(?:\/(disable|enable))?$/);
  if (match) {
    const id = match[1];
    const action = match[2];
    if (method === "POST" && action === "disable") {
      await env.DB.batch([
        env.DB.prepare("UPDATE users SET status = 'disabled' WHERE id = ?1 AND status = 'active'").bind(id),
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?1").bind(id),
      ]);
      return json({ ok: true });
    }
    if (method === "POST" && action === "enable") {
      await env.DB.prepare("UPDATE users SET status = 'active' WHERE id = ?1 AND status = 'disabled'").bind(id).run();
      return json({ ok: true });
    }
    if (method === "DELETE" && !action) {
      await env.DB.batch([
        env.DB.prepare("UPDATE users SET status = 'deleting' WHERE id = ?1").bind(id),
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?1").bind(id),
      ]);
      const complete = await purgeUser(env, id);
      return json({ ok: true, complete });
    }
  }

  return fail(404, "Not found");
}

/** Deletes all of a user's stored data and then the account. Returns false if more remains
 *  (the nightly job carries on). */
export async function purgeUser(env: Env, userId: string): Promise<boolean> {
  let cursor: string | undefined;
  for (let i = 0; i < 15; i++) {
    const list = await env.BUCKET.list({ prefix: `u/${userId}/`, limit: 1000, cursor });
    if (list.objects.length) await env.BUCKET.delete(list.objects.map((o) => o.key));
    if (!list.truncated) {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM files WHERE user_id = ?1").bind(userId),
        env.DB.prepare("DELETE FROM file_versions WHERE user_id = ?1").bind(userId),
        env.DB.prepare("DELETE FROM cursors WHERE user_id = ?1").bind(userId),
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?1").bind(userId),
        env.DB.prepare("DELETE FROM users WHERE id = ?1").bind(userId),
      ]);
      return true;
    }
    cursor = list.cursor;
  }
  return false;
}
