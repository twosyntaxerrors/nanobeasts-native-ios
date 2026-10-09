-- Nanobeasts friends leaderboard. Apply with:
--   wrangler d1 execute nanobeasts-friends --remote --file=schema.sql

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  avatar_key TEXT,
  time_zone TEXT NOT NULL DEFAULT 'UTC',
  invite_code TEXT NOT NULL UNIQUE,
  apple_refresh_token TEXT,
  created_at INTEGER NOT NULL,
  steps_updated_at INTEGER
);

-- Only a SHA-256 of each session token is stored.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id);

-- Each friendship is stored in both directions.
CREATE TABLE IF NOT EXISTS friendships (
  user_id TEXT NOT NULL,
  friend_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, friend_id)
);

-- One row per user per local calendar day ("YYYY-MM-DD" in the user's time zone).
CREATE TABLE IF NOT EXISTS daily_steps (
  user_id TEXT NOT NULL,
  day TEXT NOT NULL,
  steps INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, day)
);
