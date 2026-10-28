/**
 * Inkwell sync service.
 *
 * Stores opaque, already-encrypted blobs in R2 and tracks them in D1.
 * The server never sees plaintext: titles, handwriting, images and the key envelope
 * are all encrypted on the device before upload.
 *
 * Every /api request needs:  Authorization: Bearer <SYNC_TOKEN>
 *
 *   GET    /api/changes?since=<cursor>&limit=<n>   what changed since a cursor
 *   GET    /api/blob/<id>[?version=<n>]            download a blob (latest by default)
 *   PUT    /api/blob/<id>                          upload a new version
 *            headers: X-Kind: note|image|folders|envelope|template
 *                     X-Base-Version: <n>  (optional; the version you edited from)
 *   DELETE /api/blob/<id>                          soft delete (blobs purged after 30 days)
 *   GET    /api/versions/<id>                      list kept versions
 *   GET    /api/stats                              object count and bytes stored
 */

export interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  SYNC_TOKEN?: string;
}

const KEEP_VERSIONS = 10;
const MAX_BYTES = 30 * 1024 * 1024;
const PURGE_AFTER_DAYS = 30;
const ID_RE = /^[A-Za-z0-9_-]{1,80}$/;
const KINDS = new Set(["note", "image", "folders", "envelope", "template"]);

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, x-kind, x-base-version",
  "access-control-allow-methods": "GET, PUT, DELETE, OPTIONS",
  "access-control-expose-headers": "x-version, x-kind",
  "access-control-max-age": "86400",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function fail(status: number, message: string): Response {
  return json({ error: message }, status);
}

/** Constant-time check of the bearer token. */
async function authorised(request: Request, env: Env): Promise<boolean> {
  const secret = env.SYNC_TOKEN;
  if (!secret) return false;
  const header = request.headers.get("authorization") ?? "";
  const given = header.startsWith("Bearer ") ? header.slice(7) : "";
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(secret)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

interface ObjectRow {
  id: string;
  kind: string;
  version: number;
  size: number;
  deleted: number;
  updated_at: number;
  cursor: number;
}

const blobKey = (id: string, version: number) => `blobs/${id}/${version}`;

/** Bumps the global change counter inside the same atomic batch as the write that follows. */
const bumpCursor = (env: Env) =>
  env.DB.prepare(
    "INSERT INTO counter(name, value) VALUES('cursor', 1) ON CONFLICT(name) DO UPDATE SET value = value + 1",
  );

const CURSOR_NOW = "(SELECT value FROM counter WHERE name = 'cursor')";

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  const { pathname } = url;
  const method = request.method;

  if (pathname === "/api/changes" && method === "GET") {
    const since = Number(url.searchParams.get("since") ?? 0) || 0;
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 500) || 500, 1), 1000);
    const { results } = await env.DB.prepare(
      "SELECT id, kind, version, size, deleted, updated_at, cursor FROM objects WHERE cursor > ?1 ORDER BY cursor LIMIT ?2",
    )
      .bind(since, limit + 1)
      .all<ObjectRow>();
    const more = results.length > limit;
    const changes = more ? results.slice(0, limit) : results;
    const cursor = changes.length ? changes[changes.length - 1].cursor : since;
    return json({ changes, cursor, more });
  }

  if (pathname === "/api/stats" && method === "GET") {
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS objects, COALESCE(SUM(size), 0) AS bytes FROM objects WHERE deleted = 0",
    ).first<{ objects: number; bytes: number }>();
    return json(row ?? { objects: 0, bytes: 0 });
  }

  const blob = pathname.match(/^\/api\/blob\/([^/]+)$/);
  if (blob) {
    const id = blob[1];
    if (!ID_RE.test(id)) return fail(400, "Bad id");
    if (method === "GET") return getBlob(env, id, url);
    if (method === "PUT") return putBlob(request, env, id);
    if (method === "DELETE") return deleteBlob(env, id);
  }

  const versions = pathname.match(/^\/api\/versions\/([^/]+)$/);
  if (versions && method === "GET") {
    const id = versions[1];
    if (!ID_RE.test(id)) return fail(400, "Bad id");
    const { results } = await env.DB.prepare(
      "SELECT version, size, created_at FROM versions WHERE id = ?1 ORDER BY version DESC",
    )
      .bind(id)
      .all();
    return json({ versions: results });
  }

  return fail(404, "Not found");
}

async function getBlob(env: Env, id: string, url: URL): Promise<Response> {
  const row = await env.DB.prepare("SELECT * FROM objects WHERE id = ?1").bind(id).first<ObjectRow>();
  if (!row) return fail(404, "No such object");
  const asked = url.searchParams.get("version");
  if (row.deleted && !asked) return fail(404, "Deleted");
  const version = asked ? Number(asked) : row.version;
  if (!Number.isInteger(version) || version < 1) return fail(400, "Bad version");
  const object = await env.BUCKET.get(blobKey(id, version));
  if (!object) return fail(404, "Version not kept");
  return new Response(object.body, {
    headers: {
      ...CORS,
      "content-type": "application/octet-stream",
      "x-version": String(version),
      "x-kind": row.kind,
    },
  });
}

async function putBlob(request: Request, env: Env, id: string): Promise<Response> {
  const kind = request.headers.get("x-kind") ?? "";
  if (!KINDS.has(kind)) return fail(400, "Missing or unknown X-Kind");

  const body = await request.arrayBuffer();
  if (body.byteLength === 0) return fail(400, "Empty body");
  if (body.byteLength > MAX_BYTES) return fail(413, "Too large");

  const current = await env.DB.prepare("SELECT kind, version FROM objects WHERE id = ?1")
    .bind(id)
    .first<{ kind: string; version: number }>();
  if (current && current.kind !== kind) return fail(400, "Kind cannot change");

  const baseHeader = request.headers.get("x-base-version");
  const base = baseHeader === null ? null : Number(baseHeader);
  const version = (current?.version ?? 0) + 1;
  const now = Date.now();

  await env.BUCKET.put(blobKey(id, version), body, {
    httpMetadata: { contentType: "application/octet-stream" },
  });

  await env.DB.batch([
    bumpCursor(env),
    env.DB.prepare(
      `INSERT INTO objects(id, kind, version, size, deleted, updated_at, cursor)
       VALUES(?1, ?2, ?3, ?4, 0, ?5, ${CURSOR_NOW})
       ON CONFLICT(id) DO UPDATE SET
         version = ?3, size = ?4, deleted = 0, updated_at = ?5, cursor = ${CURSOR_NOW}`,
    ).bind(id, kind, version, body.byteLength, now),
    env.DB.prepare("INSERT OR REPLACE INTO versions(id, version, size, created_at) VALUES(?1, ?2, ?3, ?4)")
      .bind(id, version, body.byteLength, now),
  ]);

  await pruneVersions(env, id, version);

  // The caller edited from an older version: its change is saved as the newest, and the
  // version it replaced stays in history so nothing is lost.
  const conflict = base !== null && current !== null && base !== current.version;
  return json({ id, version, conflict });
}

async function deleteBlob(env: Env, id: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT id FROM objects WHERE id = ?1").bind(id).first();
  if (!row) return fail(404, "No such object");
  await env.DB.batch([
    bumpCursor(env),
    env.DB.prepare(
      `UPDATE objects SET deleted = 1, updated_at = ?2, cursor = ${CURSOR_NOW} WHERE id = ?1`,
    ).bind(id, Date.now()),
  ]);
  return json({ id, deleted: true });
}

async function pruneVersions(env: Env, id: string, newest: number): Promise<void> {
  const cutoff = newest - KEEP_VERSIONS;
  if (cutoff < 1) return;
  const { results } = await env.DB.prepare("SELECT version FROM versions WHERE id = ?1 AND version <= ?2")
    .bind(id, cutoff)
    .all<{ version: number }>();
  if (!results.length) return;
  await env.BUCKET.delete(results.map((r) => blobKey(id, r.version)));
  await env.DB.prepare("DELETE FROM versions WHERE id = ?1 AND version <= ?2").bind(id, cutoff).run();
}

/** Nightly: drop the stored data of notes deleted more than 30 days ago. The tombstone stays
 *  so a device that was offline still learns the note was deleted. */
async function maintenance(env: Env): Promise<void> {
  const cutoff = Date.now() - PURGE_AFTER_DAYS * 86_400_000;
  const { results } = await env.DB.prepare(
    "SELECT id FROM objects WHERE deleted = 1 AND size > 0 AND updated_at < ?1 LIMIT 100",
  )
    .bind(cutoff)
    .all<{ id: string }>();

  for (const { id } of results) {
    const versions = await env.DB.prepare("SELECT version FROM versions WHERE id = ?1")
      .bind(id)
      .all<{ version: number }>();
    if (versions.results.length) {
      await env.BUCKET.delete(versions.results.map((v) => blobKey(id, v.version)));
    }
    await env.DB.batch([
      env.DB.prepare("DELETE FROM versions WHERE id = ?1").bind(id),
      env.DB.prepare("UPDATE objects SET size = 0 WHERE id = ?1").bind(id),
    ]);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("Inkwell sync is running.", { headers: { ...CORS, "content-type": "text/plain" } });
    }
    if (!(await authorised(request, env))) return fail(401, "Unauthorised");

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
