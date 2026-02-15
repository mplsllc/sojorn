-- Add category column to forum threads for sub-forums functionality
ALTER TABLE group_forum_threads ADD COLUMN IF NOT EXISTS category TEXT;
CREATE INDEX IF NOT EXISTS idx_group_forum_threads_category ON group_forum_threads(group_id, category) WHERE is_deleted = FALSE;
