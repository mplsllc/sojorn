CREATE TABLE IF NOT EXISTS invite_tokens (
    token TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    used_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invite_tokens_unused ON invite_tokens (token) WHERE used_by IS NULL;
