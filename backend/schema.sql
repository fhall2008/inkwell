-- Accounts. Safe to run on every deploy (nothing is dropped).
-- The older single-user tables (objects, versions, counter) are no longer used.

CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,
  email      TEXT NOT NULL UNIQUE,
  role       TEXT NOT NULL DEFAULT 'user',      -- 'user' | 'admin'
  kdf_salt   TEXT NOT NULL,                     -- salt the client uses to stretch the password
  login_hash TEXT NOT NULL,                     -- SHA-256 of the client-derived login key
  status     TEXT NOT NULL DEFAULT 'active',    -- 'active' | 'disabled' | 'deleting'
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS invites (
  code_hash  TEXT PRIMARY KEY,
  email      TEXT,                              -- optional: restrict the invite to one address
  role       TEXT NOT NULL DEFAULT 'user',
  purpose    TEXT NOT NULL DEFAULT 'register',  -- 'register' (new account) | 'reset' (forgotten password)
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at    INTEGER
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS login_attempts (
  key          TEXT PRIMARY KEY,
  count        INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);

-- Per-user encrypted files.
CREATE TABLE IF NOT EXISTS files (
  user_id    TEXT NOT NULL,
  id         TEXT NOT NULL,
  kind       TEXT NOT NULL,
  version    INTEGER NOT NULL,
  size       INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  cursor     INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX IF NOT EXISTS files_cursor ON files(user_id, cursor);

CREATE TABLE IF NOT EXISTS file_versions (
  user_id    TEXT NOT NULL,
  id         TEXT NOT NULL,
  version    INTEGER NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, id, version)
);

CREATE TABLE IF NOT EXISTS cursors (
  user_id TEXT PRIMARY KEY,
  value   INTEGER NOT NULL
);
