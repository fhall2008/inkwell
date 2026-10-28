import {
  AuthUser,
  Env,
  bearer,
  clientIp,
  fail,
  hmacBase64Url,
  json,
  normaliseEmail,
  randomToken,
  rateLimit,
  readJson,
  safeEqual,
  sha256Hex,
} from "./util";

/**
 * Password handling. The device stretches the password with PBKDF2 (600,000 rounds) and splits the
 * 64-byte result in two: the first half encrypts the notes and never leaves the device; the second
 * half is the "login key" sent here. The server stores only a hash of the login key, so it can never
 * derive the encryption key.
 */
export const KDF_ITERATIONS = 600_000;
const SESSION_DAYS = 30;
const FIFTEEN_MINUTES = 15 * 60_000;

const loginHash = (loginKey: string) => sha256Hex(`inkwell-login-v1:${loginKey}`);

async function createSession(env: Env, userId: string) {
  const token = randomToken(32);
  const now = Date.now();
  const expires = now + SESSION_DAYS * 86_400_000;
  await env.DB.prepare("INSERT INTO sessions(token_hash, user_id, created_at, expires_at) VALUES(?1, ?2, ?3, ?4)")
    .bind(await sha256Hex(token), userId, now, expires)
    .run();
  return { token, expires };
}

/** Returns the signed-in user for a request, or null. */
export async function authenticate(request: Request, env: Env): Promise<AuthUser | null> {
  const token = bearer(request);
  if (!token) return null;
  return env.DB.prepare(
    `SELECT u.id AS id, u.email AS email, u.role AS role
     FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ?1 AND s.expires_at > ?2 AND u.status = 'active'`,
  )
    .bind(await sha256Hex(token), Date.now())
    .first<AuthUser>();
}

const isKeyLike = (v: unknown): v is string => typeof v === "string" && v.length >= 20 && v.length <= 200;
const isSaltLike = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{16,64}$/.test(v);

export async function handleAuth(request: Request, env: Env, pathname: string): Promise<Response> {
  const method = request.method;

  // Tells the device which salt to stretch the password with. Unknown emails get a stable fake salt.
  if (pathname === "/auth/prelogin" && method === "POST") {
    const body = await readJson<{ email?: unknown }>(request);
    const email = normaliseEmail(body?.email);
    if (!email) return fail(400, "Bad request");
    if (!(await rateLimit(env, `pre:${clientIp(request)}`, 60, FIFTEEN_MINUTES))) return fail(429, "Too many attempts.");
    const row = await env.DB.prepare("SELECT kdf_salt FROM users WHERE email = ?1").bind(email).first<{ kdf_salt: string }>();
    const salt = row?.kdf_salt ?? (await hmacBase64Url(env.SYNC_TOKEN ?? "unset", `salt:${email}`));
    return json({ salt, iterations: KDF_ITERATIONS });
  }

  if (pathname === "/auth/register" && method === "POST") {
    const body = await readJson<{ invite?: unknown; email?: unknown; salt?: unknown; loginKey?: unknown }>(request);
    const email = normaliseEmail(body?.email);
    if (!email || typeof body?.invite !== "string" || !isSaltLike(body.salt) || !isKeyLike(body.loginKey)) {
      return fail(400, "Bad request");
    }
    if (!(await rateLimit(env, `reg:${clientIp(request)}`, 10, 3_600_000))) return fail(429, "Too many attempts.");

    const code = body.invite.toUpperCase().replace(/[^A-Z0-9]/g, "");
    const invite = await env.DB.prepare("SELECT * FROM invites WHERE code_hash = ?1")
      .bind(await sha256Hex(code))
      .first<{ code_hash: string; email: string | null; role: string; purpose: string; expires_at: number; used_at: number | null }>();
    if (
      !invite ||
      invite.purpose !== "register" ||
      invite.used_at ||
      invite.expires_at < Date.now() ||
      (invite.email && invite.email !== email)
    ) {
      return fail(400, "That invite is invalid or has expired.");
    }
    const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ?1").bind(email).first();
    if (existing) return fail(409, "That email already has an account.");

    const id = randomToken(12);
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO users(id, email, role, kdf_salt, login_hash, status, created_at) VALUES(?1, ?2, ?3, ?4, ?5, 'active', ?6)",
      ).bind(id, email, invite.role, body.salt, await loginHash(body.loginKey), Date.now()),
      env.DB.prepare("UPDATE invites SET used_at = ?2 WHERE code_hash = ?1").bind(invite.code_hash, Date.now()),
    ]);
    const session = await createSession(env, id);
    return json({ ...session, user: { id, email, role: invite.role } }, 201);
  }

  // Forgotten password: an admin issues a reset code for the person's email. The person sets a new
  // password with it, then uses their recovery key on the device to re-wrap their encryption key.
  // The server never learns either secret, and the notes stay encrypted throughout.
  if (pathname === "/auth/reset" && method === "POST") {
    const body = await readJson<{ invite?: unknown; email?: unknown; salt?: unknown; loginKey?: unknown }>(request);
    const email = normaliseEmail(body?.email);
    if (!email || typeof body?.invite !== "string" || !isSaltLike(body.salt) || !isKeyLike(body.loginKey)) {
      return fail(400, "Bad request");
    }
    if (!(await rateLimit(env, `reg:${clientIp(request)}`, 10, 3_600_000))) return fail(429, "Too many attempts.");

    const code = body.invite.toUpperCase().replace(/[^A-Z0-9]/g, "");
    const invite = await env.DB.prepare("SELECT * FROM invites WHERE code_hash = ?1")
      .bind(await sha256Hex(code))
      .first<{ code_hash: string; email: string | null; purpose: string; expires_at: number; used_at: number | null }>();
    const user = await env.DB.prepare("SELECT id, email, role, status FROM users WHERE email = ?1")
      .bind(email)
      .first<{ id: string; email: string; role: string; status: string }>();
    if (
      !invite ||
      invite.purpose !== "reset" ||
      invite.used_at ||
      invite.expires_at < Date.now() ||
      invite.email !== email ||
      !user
    ) {
      return fail(400, "That reset code is invalid or has expired.");
    }
    if (user.status !== "active") return fail(403, "This account is disabled.");

    await env.DB.batch([
      env.DB.prepare("UPDATE users SET login_hash = ?2, kdf_salt = ?3 WHERE id = ?1")
        .bind(user.id, await loginHash(body.loginKey), body.salt),
      env.DB.prepare("DELETE FROM sessions WHERE user_id = ?1").bind(user.id),
      env.DB.prepare("UPDATE invites SET used_at = ?2 WHERE code_hash = ?1").bind(invite.code_hash, Date.now()),
    ]);
    const session = await createSession(env, user.id);
    return json({ ...session, user: { id: user.id, email: user.email, role: user.role } });
  }

  if (pathname === "/auth/login" && method === "POST") {
    const body = await readJson<{ email?: unknown; loginKey?: unknown }>(request);
    const email = normaliseEmail(body?.email);
    if (!email || !isKeyLike(body?.loginKey)) return fail(400, "Bad request");
    if (
      !(await rateLimit(env, `login:${email}`, 8, FIFTEEN_MINUTES)) ||
      !(await rateLimit(env, `loginip:${clientIp(request)}`, 40, FIFTEEN_MINUTES))
    ) {
      return fail(429, "Too many attempts. Try again in a few minutes.");
    }
    const user = await env.DB.prepare("SELECT id, email, role, status, login_hash FROM users WHERE email = ?1")
      .bind(email)
      .first<{ id: string; email: string; role: string; status: string; login_hash: string }>();
    const matches = await safeEqual(await loginHash(body.loginKey), user?.login_hash ?? "0".repeat(64));
    if (!user || !matches) return fail(401, "Wrong email or password.");
    if (user.status !== "active") return fail(403, "This account is disabled.");
    const session = await createSession(env, user.id);
    return json({ ...session, user: { id: user.id, email: user.email, role: user.role } });
  }

  // Everything below needs a signed-in user.
  const user = await authenticate(request, env);
  if (!user) return fail(401, "Unauthorised");

  if (pathname === "/auth/me" && method === "GET") return json({ user });

  if (pathname === "/auth/logout" && method === "POST") {
    await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?1").bind(await sha256Hex(bearer(request))).run();
    return json({ ok: true });
  }

  if (pathname === "/auth/password" && method === "POST") {
    const body = await readJson<{ currentLoginKey?: unknown; newLoginKey?: unknown; newSalt?: unknown }>(request);
    if (!isKeyLike(body?.currentLoginKey) || !isKeyLike(body?.newLoginKey) || !isSaltLike(body?.newSalt)) {
      return fail(400, "Bad request");
    }
    if (!(await rateLimit(env, `pw:${user.id}`, 8, FIFTEEN_MINUTES))) return fail(429, "Too many attempts.");
    const row = await env.DB.prepare("SELECT login_hash FROM users WHERE id = ?1").bind(user.id).first<{ login_hash: string }>();
    if (!row || !(await safeEqual(await loginHash(body.currentLoginKey), row.login_hash))) {
      return fail(401, "Wrong current password.");
    }
    const keep = await sha256Hex(bearer(request));
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET login_hash = ?2, kdf_salt = ?3 WHERE id = ?1")
        .bind(user.id, await loginHash(body.newLoginKey), body.newSalt),
      env.DB.prepare("DELETE FROM sessions WHERE user_id = ?1 AND token_hash != ?2").bind(user.id, keep),
    ]);
    return json({ ok: true });
  }

  return fail(404, "Not found");
}
