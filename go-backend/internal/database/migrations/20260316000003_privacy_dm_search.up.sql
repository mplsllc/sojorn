ALTER TABLE profile_privacy_settings ADD COLUMN IF NOT EXISTS allow_dms_from TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE profile_privacy_settings ADD COLUMN IF NOT EXISTS searchable_by_handle BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE profile_privacy_settings ADD COLUMN IF NOT EXISTS searchable_by_email BOOLEAN NOT NULL DEFAULT false;
