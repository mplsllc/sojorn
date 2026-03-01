-- Groups schema fix: add columns referenced by handlers but missing from the
-- original migration, create group_posts junction table, and create
-- group_member_keys for E2EE key distribution.

-- Add missing columns to groups table.
-- All have safe defaults so existing rows are unaffected.
ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS type                VARCHAR(50) NOT NULL DEFAULT 'social',
  ADD COLUMN IF NOT EXISTS privacy             VARCHAR(20) NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS key_rotation_needed BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS key_version         INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS chat_enabled        BOOLEAN     NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS forum_enabled       BOOLEAN     NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS vault_enabled       BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_encrypted        BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS public_key          TEXT,
  ADD COLUMN IF NOT EXISTS settings            JSONB       NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS invite_code         TEXT UNIQUE,  -- NULLs are not equal in PG unique constraints; multiple NULL rows are fine
  ADD COLUMN IF NOT EXISTS radius_meters       INTEGER;

-- Mark existing neighborhood/geo groups with the correct type.
UPDATE groups SET type = 'neighborhood'
WHERE id IN (
  SELECT DISTINCT neighborhood_group_id FROM users
  WHERE neighborhood_group_id IS NOT NULL
);

-- group_posts: junction table kept in sync with posts.group_id.
-- GetGroupFeed() joins here rather than filtering posts.group_id directly
-- for query performance (index on group_id + added_at vs a full posts scan).
CREATE TABLE IF NOT EXISTS group_posts (
  group_id UUID        NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  post_id  UUID        NOT NULL REFERENCES posts(id)  ON DELETE CASCADE,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, post_id)
);

-- Backfill all existing posts that already have group_id set.
-- Verify after running:
--   SELECT (SELECT COUNT(*) FROM group_posts) AS junction_count,
--          (SELECT COUNT(*) FROM posts WHERE group_id IS NOT NULL) AS posts_with_group;
-- Both counts must match before deploying the binary.
INSERT INTO group_posts (group_id, post_id, added_at)
  SELECT group_id, id, created_at
  FROM posts
  WHERE group_id IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_group_posts_group_id ON group_posts (group_id, added_at DESC);

-- group_member_keys: per-member versioned encrypted group keys.
-- Used by GetGroupKeyStatus(), DistributeGroupKeys(), and InviteMember()
-- to store each member's copy of the group key (encrypted to their public key).
CREATE TABLE IF NOT EXISTS group_member_keys (
  group_id      UUID        NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id       UUID        NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  key_version   INTEGER     NOT NULL,
  encrypted_key TEXT        NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (group_id, user_id, key_version)
);

CREATE INDEX IF NOT EXISTS idx_group_member_keys_group ON group_member_keys (group_id, key_version);
