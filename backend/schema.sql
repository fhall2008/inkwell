CREATE TABLE IF NOT EXISTS objects (
  id         TEXT PRIMARY KEY,
  kind       TEXT NOT NULL,
  version    INTEGER NOT NULL,
  size       INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  cursor     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS objects_cursor ON objects(cursor);

CREATE TABLE IF NOT EXISTS versions (
  id         TEXT NOT NULL,
  version    INTEGER NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (id, version)
);

CREATE TABLE IF NOT EXISTS counter (
  name  TEXT PRIMARY KEY,
  value INTEGER NOT NULL
);
