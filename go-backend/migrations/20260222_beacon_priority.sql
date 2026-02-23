-- Beacon priority flag: set automatically when vouch_count >= 3
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_priority BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_posts_beacon_priority ON public.posts(is_priority) WHERE is_beacon = true AND is_priority = true;
