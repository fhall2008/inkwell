import { AuthUser, CORS, Env, fail, json } from "./util";

const KEEP_VERSIONS = 10;
const MAX_BYTES = 30 * 1024 * 1024;
const MAX_USER_BYTES = 2 * 1024 * 1024 * 1024; // 2 GB of stored versions per user
const ID_RE = /^[A-Za-z0-9_-]{1,80}$/;
const KINDS = new Set(["note", "image", "folders", "envelope", "template", "stamps"]);

interface FileRow {
  id: string;
  kind: string;
  version: number;
  size: number;
  deleted: number;
  updated_at: number;
  cursor: number;
}

export const blobKey = (userId: string, id: string, version: number) => `u/${userId}/${id}/${version}`;

export async function handleSync(request: Request, env: Env, pathname: string, url: URL, user: AuthUser): Promise<Response> {
  const method = request.method;

  if (pathname === "/api/changes" && method === "GET") {
    const since = Number(url.searchParams.get("since") ?? 0) || 0;
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 500) || 500, 1), 1000);
    const { results } = await env.DB.prepare(
      "SELECT id, kind, version, size, deleted, updated_at, cursor FROM files WHERE user_id = ?1 AND cursor > ?2 ORDER BY cursor LIMIT ?3",
    )
      .bind(user.id, since, limit + 1)
      .all<FileRow>();
    const more = results.length > limit;
    const changes = more ? results.slice(0, limit) : results;
    const cursor = changes.length ? changes[changes.length - 1].cursor : since;
    return json({ changes, cursor, more });
  }

  if (pathname === "/api/stats" && method === "GET") {
    const files = await env.DB.prepare(
      "SELECT COUNT(*) AS objects FROM files WHERE user_id = ?1 AND deleted = 0",
    ).bind(user.id).first<{ objects: number }>();
    const used = await env.DB.prepare(
      "SELECT COALESCE(SUM(size), 0) AS bytes FROM file_versions WHERE user_id = ?1",
    ).bind(user.id).first<{ bytes: number }>();
    return json({ objects: files?.objects ?? 0, bytes: used?.bytes ?? 0, limit: MAX_USER_BYTES });
  }

  const blob = pathname.match(/^\/api\/blob\/([^/]+)$/);
  if (blob) {
    const id = blob[1];
    if (!ID_RE.test(id)) return fail(400, "Bad id");
    if (method === "GET") return getBlob(env, user, id, url);
    if (method === "PUT") return putBlob(request, env, user, id);
    if (method === "DELETE") return deleteBlob(env, user, id);
  }

  const versions = pathname.match(/^\/api\/versions\/([^/]+)$/);
  if (versions && method === "GET") {
    const id = versions[1];
    if (!ID_RE.test(id)) return fail(400, "Bad id");
    const { results } = await env.DB.prepare(
      "SELECT version, size, created_at FROM file_versions WHERE user_id = ?1 AND id = ?2 ORDER BY version DESC",
    )
      .bind(user.id, id)
      .all();
    return json({ versions: results });
  }

  return fail(404, "Not found");
}

async function getBlob(env: Env, user: AuthUser, id: string, url: URL): Promise<Response> {
  const row = await env.DB.prepare("SELECT * FROM files WHERE user_id = ?1 AND id = ?2").bind(user.id, id).first<FileRow>();
  if (!row) return fail(404, "No such object");
  const asked = url.searchParams.get("version");
  if (row.deleted && !asked) return fail(404, "Deleted");
  const version = asked ? Number(asked) : row.version;
  if (!Number.isInteger(version) || version < 1) return fail(400, "Bad version");
  const object = await env.BUCKET.get(blobKey(user.id, id, version));
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

async function putBlob(request: Request, env: Env, user: AuthUser, id: string): Promise<Response> {
  const kind = request.headers.get("x-kind") ?? "";
  if (!KINDS.has(kind)) return fail(400, "Missing or unknown X-Kind");

  const body = await request.arrayBuffer();
  if (body.byteLength === 0) return fail(400, "Empty body");
  if (body.byteLength > MAX_BYTES) return fail(413, "Too large");

  const used = await env.DB.prepare("SELECT COALESCE(SUM(size), 0) AS bytes FROM file_versions WHERE user_id = ?1")
    .bind(user.id)
    .first<{ bytes: number }>();
  if ((used?.bytes ?? 0) + body.byteLength > MAX_USER_BYTES) return fail(413, "Storage limit reached");

  const current = await env.DB.prepare("SELECT kind, version FROM files WHERE user_id = ?1 AND id = ?2")
    .bind(user.id, id)
    .first<{ kind: string; version: number }>();
  if (current && current.kind !== kind) return fail(400, "Kind cannot change");

  const baseHeader = request.headers.get("x-base-version");
  const base = baseHeader === null ? null : Number(baseHeader);
  const version = (current?.version ?? 0) + 1;
  const now = Date.now();

  await env.BUCKET.put(blobKey(user.id, id, version), body, {
    httpMetadata: { contentType: "application/octet-stream" },
  });

  const cursorNow = "(SELECT value FROM cursors WHERE user_id = ?1)";
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO cursors(user_id, value) VALUES(?1, 1) ON CONFLICT(user_id) DO UPDATE SET value = value + 1",
    ).bind(user.id),
    env.DB.prepare(
      `INSERT INTO files(user_id, id, kind, version, size, deleted, updated_at, cursor)
       VALUES(?1, ?2, ?3, ?4, ?5, 0, ?6, ${cursorNow})
       ON CONFLICT(user_id, id) DO UPDATE SET
         version = ?4, size = ?5, deleted = 0, updated_at = ?6, cursor = ${cursorNow}`,
    ).bind(user.id, id, kind, version, body.byteLength, now),
    env.DB.prepare(
      "INSERT OR REPLACE INTO file_versions(user_id, id, version, size, created_at) VALUES(?1, ?2, ?3, ?4, ?5)",
    ).bind(user.id, id, version, body.byteLength, now),
  ]);

  await pruneVersions(env, user.id, id, version);

  // The caller edited from an older version. Its change is saved as the newest, and the version
  // it replaced stays in history so nothing is lost.
  const conflict = base !== null && current !== null && base !== current.version;
  return json({ id, version, conflict });
}

async function deleteBlob(env: Env, user: AuthUser, id: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT id FROM files WHERE user_id = ?1 AND id = ?2").bind(user.id, id).first();
  if (!row) return fail(404, "No such object");
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO cursors(user_id, value) VALUES(?1, 1) ON CONFLICT(user_id) DO UPDATE SET value = value + 1",
    ).bind(user.id),
    env.DB.prepare(
      "UPDATE files SET deleted = 1, updated_at = ?3, cursor = (SELECT value FROM cursors WHERE user_id = ?1) WHERE user_id = ?1 AND id = ?2",
    ).bind(user.id, id, Date.now()),
  ]);
  return json({ id, deleted: true });
}

async function pruneVersions(env: Env, userId: string, id: string, newest: number): Promise<void> {
  const cutoff = newest - KEEP_VERSIONS;
  if (cutoff < 1) return;
  const { results } = await env.DB.prepare(
    "SELECT version FROM file_versions WHERE user_id = ?1 AND id = ?2 AND version <= ?3",
  )
    .bind(userId, id, cutoff)
    .all<{ version: number }>();
  if (!results.length) return;
  await env.BUCKET.delete(results.map((r) => blobKey(userId, id, r.version)));
  await env.DB.prepare("DELETE FROM file_versions WHERE user_id = ?1 AND id = ?2 AND version <= ?3")
    .bind(userId, id, cutoff)
    .run();
}
