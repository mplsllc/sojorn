-- Unified beacon alerts table
-- Ingests data from MN511, IcedCoffee, and merges with user beacons at query time.
-- External alerts are upserted by (source, external_id) to prevent duplicates.

CREATE TABLE IF NOT EXISTS beacon_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id     TEXT,
    source          TEXT NOT NULL,
    beacon_type     TEXT NOT NULL DEFAULT 'hazard',
    severity        TEXT NOT NULL DEFAULT 'medium',
    title           TEXT NOT NULL DEFAULT '',
    body            TEXT NOT NULL DEFAULT '',
    lat             DOUBLE PRECISION NOT NULL,
    lng             DOUBLE PRECISION NOT NULL,
    location        GEOGRAPHY(Point, 4326),
    radius          INT NOT NULL DEFAULT 500,
    image_url       TEXT,
    video_url       TEXT,
    is_official     BOOLEAN NOT NULL DEFAULT FALSE,
    official_source TEXT,
    author_id       TEXT,
    author_handle   TEXT,
    author_display  TEXT,
    status          TEXT NOT NULL DEFAULT 'active',
    incident_status TEXT NOT NULL DEFAULT 'active',
    confidence      DOUBLE PRECISION DEFAULT 1.0,
    vouch_count     INT NOT NULL DEFAULT 0,
    report_count    INT NOT NULL DEFAULT 0,
    tags            TEXT[] DEFAULT '{}',
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_beacon_alerts_location ON beacon_alerts USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_status ON beacon_alerts (status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_expires ON beacon_alerts (expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_beacon_alerts_source ON beacon_alerts (source);

-- Trigger to auto-set location from lat/lng on insert/update
CREATE OR REPLACE FUNCTION beacon_alerts_set_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location := ST_SetSRID(ST_Point(NEW.lng, NEW.lat), 4326)::geography;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_beacon_alerts_set_location ON beacon_alerts;
CREATE TRIGGER trg_beacon_alerts_set_location
    BEFORE INSERT OR UPDATE ON beacon_alerts
    FOR EACH ROW
    EXECUTE FUNCTION beacon_alerts_set_location();
