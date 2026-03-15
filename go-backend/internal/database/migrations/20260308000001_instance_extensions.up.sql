-- Extension system: tracks which optional features are enabled on this instance.
CREATE TABLE IF NOT EXISTS instance_extensions (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    enabled     BOOLEAN NOT NULL DEFAULT false,
    enabled_at  TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    config      JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Instance-level configuration (name, description, branding, registration mode).
CREATE TABLE IF NOT EXISTS instance_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Seed default instance config.
INSERT INTO instance_config (key, value) VALUES
    ('instance_name', 'Sojorn'),
    ('instance_description', 'A self-hosted social network'),
    ('instance_logo_url', ''),
    ('instance_accent_color', ''),
    ('registration_mode', 'open')
ON CONFLICT (key) DO NOTHING;
