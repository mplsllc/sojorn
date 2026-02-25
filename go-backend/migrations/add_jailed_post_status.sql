-- Add 'jailed' to post_status enum for content hidden during account bans/suspensions.
-- Jailed posts are invisible in feeds but can be restored if the account is reinstated.
ALTER TYPE post_status ADD VALUE IF NOT EXISTS 'jailed';

-- Jail active posts belonging to any currently banned or suspended users (retroactive fix).
UPDATE posts
SET status = 'jailed'
WHERE status = 'active'
  AND deleted_at IS NULL
  AND author_id IN (
    SELECT id FROM users WHERE status IN ('banned', 'suspended')
  );

-- Jail active comments belonging to banned/suspended users.
UPDATE comments
SET status = 'jailed'
WHERE status = 'active'
  AND deleted_at IS NULL
  AND author_id IN (
    SELECT id FROM users WHERE status IN ('banned', 'suspended')
  );
