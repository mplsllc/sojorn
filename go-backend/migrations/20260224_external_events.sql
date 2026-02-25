-- External event tracking for auto-imported events from Eventbrite, Ticketmaster, etc.

-- Add source column to group_events to distinguish user-created from auto-imported
ALTER TABLE group_events ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'user';

-- Track external event IDs to avoid duplicate imports
CREATE TABLE IF NOT EXISTS external_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source          TEXT NOT NULL,          -- 'eventbrite', 'ticketmaster'
    external_id     TEXT NOT NULL,          -- platform-specific event ID
    group_event_id  UUID REFERENCES group_events(id) ON DELETE SET NULL,
    external_url    TEXT,                   -- link to original event page
    raw_data        JSONB,                  -- original API response for debugging
    last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_external_events_source ON external_events(source, external_id);
CREATE INDEX IF NOT EXISTS idx_external_events_group ON external_events(group_event_id);
