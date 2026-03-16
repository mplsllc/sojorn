-- ActivityPub: add ap_id columns for federated identity
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS ap_id TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS ap_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_ap_id ON profiles (ap_id) WHERE ap_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_ap_id ON posts (ap_id) WHERE ap_id IS NOT NULL;
