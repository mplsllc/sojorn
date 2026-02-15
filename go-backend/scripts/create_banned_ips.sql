-- Banned IPs table for ban evasion prevention
CREATE TABLE IF NOT EXISTS banned_ips (
    id SERIAL PRIMARY KEY,
    ip_address TEXT NOT NULL,
    user_id UUID REFERENCES users(id),
    reason TEXT,
    banned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_banned_ips_address ON banned_ips (ip_address);
CREATE INDEX IF NOT EXISTS idx_banned_ips_user ON banned_ips (user_id);
