// All encryption happens here, in the browser. The server only ever sees ciphertext.
//
//   password  --PBKDF2-SHA256 (600k rounds, per-user salt)-->  64 bytes
//   bytes 0..31   encKey    wraps the master key; never leaves the device
//   bytes 32..63  loginKey  sent to the server, which stores only a hash of it
//
//   master key (random 32 bytes) encrypts every note, image and the folder list (AES-256-GCM).
//   The master key is stored in an "envelope", wrapped once by encKey and once by the recovery key.

const enc = new TextEncoder();
const dec = new TextDecoder();

export const KDF_ITERATIONS = 600000;

// ---------- encoding ----------

export function toB64(bytes) {
  let s = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  return btoa(s);
}

export function fromB64(str) {
  const bin = atob(str);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function toB64Url(bytes) {
  return toB64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64Url(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return fromB64(s);
}

export const randomBytes = (n) => crypto.getRandomValues(new Uint8Array(n));

// ---------- recovery key text (32 bytes <-> 13 groups of 4 characters) ----------

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function encodeRecoveryKey(bytes) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
      value &= (1 << bits) - 1;
    }
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out.match(/.{1,4}/g).join('-');
}

export function decodeRecoveryKey(text) {
  const clean = text.toUpperCase().replace(/[^A-Z0-9]/g, '');
  let bits = 0;
  let value = 0;
  const out = [];
  for (const ch of clean) {
    const idx = ALPHABET.indexOf(ch);
    if (idx < 0) throw new Error('That recovery key has a character that is not allowed.');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
      value &= (1 << bits) - 1;
    }
  }
  if (out.length < 32) throw new Error('That recovery key is too short.');
  return new Uint8Array(out.slice(0, 32));
}

// ---------- password stretching ----------

export async function stretch(password, saltB64Url, iterations = KDF_ITERATIONS) {
  const base = await crypto.subtle.importKey('raw', enc.encode(password.normalize('NFKC')), 'PBKDF2', false, ['deriveBits']);
  const bits = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: fromB64Url(saltB64Url), iterations }, base, 512),
  );
  return { encKey: bits.slice(0, 32), loginKey: toB64(bits.slice(32)) };
}

// ---------- AES-GCM ----------

const aesKey = (raw, usages) => crypto.subtle.importKey('raw', raw, 'AES-GCM', false, usages);

/** nonce (12 bytes) followed by ciphertext. `aad` ties the ciphertext to what it is. */
export async function seal(rawKey, plaintext, aad) {
  const nonce = randomBytes(12);
  const ct = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: enc.encode(aad) }, await aesKey(rawKey, ['encrypt']), plaintext),
  );
  const out = new Uint8Array(12 + ct.length);
  out.set(nonce);
  out.set(ct, 12);
  return out;
}

export async function open(rawKey, sealed, aad) {
  if (sealed.length < 29) throw new Error('Data is too short to be valid.');
  const pt = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: sealed.slice(0, 12), additionalData: enc.encode(aad) },
    await aesKey(rawKey, ['decrypt']),
    sealed.slice(12),
  );
  return new Uint8Array(pt);
}

export const sealBlob = (master, kind, id, bytes) => seal(master, bytes, `${kind}:${id}`);
export const openBlob = (master, kind, id, sealed) => open(master, sealed, `${kind}:${id}`);

export const sealJson = (master, kind, id, obj) => sealBlob(master, kind, id, enc.encode(JSON.stringify(obj)));
export async function openJson(master, kind, id, sealed) {
  return JSON.parse(dec.decode(await openBlob(master, kind, id, sealed)));
}

// ---------- envelope ----------

const AAD_PW = 'inkwell-envelope-v1:pw';
const AAD_REC = 'inkwell-envelope-v1:rec';

/** Makes a fresh master key and recovery key for a new account. */
export async function createEnvelope(encKey) {
  const master = randomBytes(32);
  const recovery = randomBytes(32);
  const envelope = {
    v: 1,
    pw: toB64(await seal(encKey, master, AAD_PW)),
    rec: toB64(await seal(recovery, master, AAD_REC)),
  };
  return { master, envelope, recoveryKey: encodeRecoveryKey(recovery) };
}

/** Tries the current wrap, then the pending one left behind by an interrupted password change. */
export async function unwrapWithPassword(envelope, encKey) {
  for (const wrapped of [envelope.pw, envelope.pw2]) {
    if (!wrapped) continue;
    try {
      return await open(encKey, fromB64(wrapped), AAD_PW);
    } catch {
      /* try the next one */
    }
  }
  throw new Error('Could not unlock your notes with that password.');
}

/** Step 1 of a password change: keep the old wrap and add one for the new password, so either works
 *  until the change has gone through. */
export async function addPendingPassword(envelope, master, newEncKey) {
  return { ...envelope, pw2: toB64(await seal(newEncKey, master, AAD_PW)) };
}

export async function unwrapWithRecovery(envelope, recoveryText) {
  const recovery = decodeRecoveryKey(recoveryText);
  try {
    return await open(recovery, fromB64(envelope.rec), AAD_REC);
  } catch {
    throw new Error('That recovery key does not match this account.');
  }
}

/** Makes `newEncKey` the only password wrap. */
export async function rewrapPassword(envelope, master, newEncKey) {
  const { pw2, ...rest } = envelope;
  return { ...rest, pw: toB64(await seal(newEncKey, master, AAD_PW)) };
}

/** Replaces the recovery key. Returns the new envelope and the new key to show the person. */
export async function rewrapRecovery(envelope, master) {
  const recovery = randomBytes(32);
  return {
    envelope: { ...envelope, rec: toB64(await seal(recovery, master, AAD_REC)) },
    recoveryKey: encodeRecoveryKey(recovery),
  };
}

export const jsonBytes = (obj) => enc.encode(JSON.stringify(obj));
export const parseJsonBytes = (bytes) => JSON.parse(dec.decode(bytes));
