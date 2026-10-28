export interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  /** The admin token. Used only for the /admin endpoints. */
  SYNC_TOKEN?: string;
}

export interface AuthUser {
  id: string;
  email: string;
  role: string;
}

export const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, x-kind, x-base-version",
  "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
  "access-control-expose-headers": "x-version, x-kind",
  "access-control-max-age": "86400",
};

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

export function fail(status: number, message: string): Response {
  return json({ error: message }, status);
}

const enc = new TextEncoder();

export function toBase64Url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function randomToken(bytes = 32): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacBase64Url(key: string, message: string, bytes = 16): Promise<string> {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(message)));
  return toBase64Url(sig.slice(0, bytes));
}

/** Constant-time string comparison. */
export async function safeEqual(a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  return crypto.subtle.timingSafeEqual(x, y);
}

export async function readJson<T>(request: Request): Promise<T | null> {
  try {
    const text = await request.text();
    if (text.length > 10_000) return null;
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}

export function clientIp(request: Request): string {
  return request.headers.get("cf-connecting-ip") ?? "unknown";
}

export function normaliseEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const v = value.trim().toLowerCase();
  return v.length <= 200 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v) ? v : null;
}

export function bearer(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

export async function isAdmin(request: Request, env: Env): Promise<boolean> {
  if (!env.SYNC_TOKEN) return false;
  const given = bearer(request);
  return given.length > 0 && (await safeEqual(given, env.SYNC_TOKEN));
}

/** Fixed-window attempt counter. Returns false once `max` attempts are used in the window. */
export async function rateLimit(env: Env, key: string, max: number, windowMs: number): Promise<boolean> {
  const now = Date.now();
  const row = await env.DB.prepare(
    `INSERT INTO login_attempts(key, count, window_start) VALUES(?1, 1, ?2)
     ON CONFLICT(key) DO UPDATE SET
       count = CASE WHEN window_start < ?3 THEN 1 ELSE count + 1 END,
       window_start = CASE WHEN window_start < ?3 THEN ?2 ELSE window_start END
     RETURNING count`,
  )
    .bind(key, now, now - windowMs)
    .first<{ count: number }>();
  return (row?.count ?? 1) <= max;
}
