-- Dashboard layouts: customizable home page widget configurations per user.
-- Each user can arrange widgets in left sidebar, right sidebar, and feed topbar.

CREATE TABLE IF NOT EXISTS dashboard_layouts (
    user_id       UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    left_sidebar  JSONB NOT NULL DEFAULT '[]'::jsonb,
    right_sidebar JSONB NOT NULL DEFAULT '[]'::jsonb,
    feed_topbar   JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
