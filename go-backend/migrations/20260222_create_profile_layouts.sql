-- Profile layouts: MySpace-style customizable profile pages.
-- Stores widget config, theme, accent color, and banner for each user.

CREATE TABLE IF NOT EXISTS profile_layouts (
    user_id          UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    widgets          JSONB NOT NULL DEFAULT '[]'::jsonb,
    theme            TEXT NOT NULL DEFAULT 'default',
    accent_color     TEXT,
    banner_image_url TEXT,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
