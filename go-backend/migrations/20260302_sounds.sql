-- In-house soundbank: stores both user-original audio from Quips and
-- curated library tracks uploaded via the admin panel.
--
-- bucket='user'    → audio extracted from user Quips (R2: sojorn-media/quip-audio/)
-- bucket='library' → curated admin-uploaded tracks (R2: sojorn-media/library-audio/)

CREATE TABLE IF NOT EXISTS sounds (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  uploader_id    UUID        REFERENCES users(id) ON DELETE SET NULL,
  source_post_id UUID        REFERENCES posts(id) ON DELETE SET NULL,
  title          TEXT        NOT NULL,     -- "Original Sound • @handle" or curated name
  r2_key         TEXT        NOT NULL,
  bucket         TEXT        NOT NULL DEFAULT 'user', -- 'user' or 'library'
  duration_ms    INTEGER,
  use_count      INTEGER     NOT NULL DEFAULT 0,
  is_active      BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sounds_use_count ON sounds(use_count DESC);
CREATE INDEX IF NOT EXISTS idx_sounds_bucket    ON sounds(bucket, is_active);
