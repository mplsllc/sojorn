CREATE TABLE IF NOT EXISTS content_strikes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    content_snippet TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_strikes_user_id ON content_strikes(user_id);
CREATE INDEX IF NOT EXISTS idx_content_strikes_created_at ON content_strikes(created_at);

-- Add suspended_until column to users if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='suspended_until') THEN
        ALTER TABLE users ADD COLUMN suspended_until TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;
