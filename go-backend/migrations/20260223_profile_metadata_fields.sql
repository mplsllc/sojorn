-- Profile metadata fields: Mastodon-style key-value pairs (max 8 fields).
-- Also used for custom profile fields.
-- Stored as JSONB array: [{"key": "Pronouns", "value": "they/them", "verified": false}, ...]
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS metadata_fields JSONB DEFAULT '[]'::jsonb;
