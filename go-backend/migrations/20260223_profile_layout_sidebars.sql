-- Add desktop sidebar columns to profile_layouts table.
-- Stores widget configurations for left/right profile page sidebars.
ALTER TABLE profile_layouts
  ADD COLUMN IF NOT EXISTS desktop_left_sidebar  JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS desktop_right_sidebar JSONB NOT NULL DEFAULT '[]';
