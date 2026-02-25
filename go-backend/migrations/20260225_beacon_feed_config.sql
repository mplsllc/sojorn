-- Admin indexes for beacon_alerts table (filtered pagination at scale)
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_admin_list ON beacon_alerts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_source_status ON beacon_alerts (source, status);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_beacon_type ON beacon_alerts (beacon_type);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_severity ON beacon_alerts (severity);

-- Feed control state table
CREATE TABLE IF NOT EXISTS beacon_feed_config (
    source       TEXT PRIMARY KEY,
    enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    last_error   TEXT,
    alert_count  INT NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed known feeds
INSERT INTO beacon_feed_config (source) VALUES
  ('mn511'), ('mn511_camera'), ('mn511_sign'), ('mn511_weather'), ('iced')
ON CONFLICT DO NOTHING;
