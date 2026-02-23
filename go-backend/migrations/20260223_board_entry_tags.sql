-- Add forum-style tag to board entries (discussion, question, resolved, announcement, poll)
ALTER TABLE board_entries ADD COLUMN IF NOT EXISTS tag VARCHAR(20);

-- Index for tag filtering
CREATE INDEX IF NOT EXISTS idx_board_entries_tag ON board_entries (tag) WHERE tag IS NOT NULL;
