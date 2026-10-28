/**
 * Inkwell sync service with accounts.
 *
 * Stores opaque, already-encrypted blobs in R2 and tracks them in D1, separately for each user.
 * The server never sees plaintext: titles, handwriting, images and each user's key envelope are
 * encrypted on the device before upload.
 *
 *   /auth/prelogin  POST  {email}                                -> {salt, iterations}
 *   /auth/register  POST  {invite, email, salt, loginKey}        -> {token, expires, user}
 *   /auth/reset     POST  {invite, email, salt, loginKey}        -> {token, expires, user}  (forgotten password)
 *   /auth/login     POST  {email, loginKey}                      -> {token, expires, user}
 *   /auth/me        GET   (session)                              -> {user}
 *   /auth/logout    POST  (session)
 *   /auth/password  POST  (session) {currentLoginKey, newLoginKey, newSalt}
 *
 *   /api/...        needs "Authorization: Bearer <session token>"
 *     GET    /api/changes?since=<cursor>&limit=<n>
 *     GET    /api/blob/<id>[?version=<n>]
 *     PUT    /api/blob/<id>        headers: X-Kind, X-Base-Version (optional)
 *     DELETE /api/blob/<id>
 *     GET    /api/versions/<id>
 *     GET    /api/stats
 *
 *   /admin/...      needs "Authorization: Bearer <admin token>" (the SYNC_TOKEN secret)
 *     POST   /admin/invites          {email?, role?, days?, purpose?: "register" | "reset"}
 *     GET    /admin/users
 *     POST   /admin/users/<id>/disable | /enable
 *     DELETE /admin/users/<id>
 */

import { handleAdmin, purgeUser } from "./admin";
import { authenticate, handleAuth } from "./auth";
import { blobKey, handleSync } from "./sync";
import { CORS, Env, fail } from "./util";

const PURGE_AFTER_DAYS = 30;

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  const { pathname } = url;
  if (pathname.startsWith("/auth/")) return handleAuth(request, env, pathname);
  if (pathname.startsWith("/admin/")) return handleAdmin(request, env, pathname);
  if (pathname.startsWith("/api/")) {
    const user = await authenticate(request, env);
    if (!user) return fail(401, "Unauthorised");
    return handleSync(request, env, pathname, url, user);
  }
  return fail(404, "Not found");
}

/** Nightly clean-up. */
async function maintenance(env: Env): Promise<void> {
  const now = Date.now();

  // Drop stored data of notes deleted more than 30 days ago. The tombstone stays so a device that
  // was offline still learns the note was deleted.
  const cutoff = now - PURGE_AFTER_DAYS * 86_400_000;
  const { results } = await env.DB.prepare(
    "SELECT user_id, id FROM files WHERE deleted = 1 AND size > 0 AND updated_at < ?1 LIMIT 100",
  )
    .bind(cutoff)
    .all<{ user_id: string; id: string }>();
  for (const { user_id, id } of results) {
    const versions = await env.DB.prepare("SELECT version FROM file_versions WHERE user_id = ?1 AND id = ?2")
      .bind(user_id, id)
      .all<{ version: number }>();
    if (versions.results.length) {
      await env.BUCKET.delete(versions.results.map((v) => blobKey(user_id, id, v.version)));
    }
    await env.DB.batch([
      env.DB.prepare("DELETE FROM file_versions WHERE user_id = ?1 AND id = ?2").bind(user_id, id),
      env.DB.prepare("UPDATE files SET size = 0 WHERE user_id = ?1 AND id = ?2").bind(user_id, id),
    ]);
  }

  // Finish deleting any accounts whose removal didn't complete in one go.
  const pending = await env.DB.prepare("SELECT id FROM users WHERE status = 'deleting' LIMIT 3").all<{ id: string }>();
  for (const { id } of pending.results) await purgeUser(env, id);

  // Housekeeping.
  await env.DB.batch([
    env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?1").bind(now),
    env.DB.prepare("DELETE FROM invites WHERE expires_at < ?1").bind(now - 7 * 86_400_000),
    env.DB.prepare("DELETE FROM login_attempts WHERE window_start < ?1").bind(now - 86_400_000),
  ]);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("Inkwell sync is running.", { headers: { ...CORS, "content-type": "text/plain" } });
    }

    try {
      return await route(request, env, url);
    } catch (error) {
      console.error(error);
      return fail(500, "Server error");
    }
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(maintenance(env));
  },
} satisfies ExportedHandler<Env>;
