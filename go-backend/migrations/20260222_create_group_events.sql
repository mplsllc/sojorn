-- Group Events: allow groups to host events that can appear in user dashboards.
-- Public events are discoverable by location for the "Upcoming Shows" widget.

CREATE TABLE IF NOT EXISTS group_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_by      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    location_name   TEXT,
    lat             DOUBLE PRECISION,
    long            DOUBLE PRECISION,
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ,
    is_public       BOOLEAN NOT NULL DEFAULT false,
    cover_image_url TEXT,
    max_attendees   INT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS group_event_rsvps (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id   UUID NOT NULL REFERENCES group_events(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    status     TEXT NOT NULL DEFAULT 'going' CHECK (status IN ('going', 'interested', 'not_going')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_group_events_group ON group_events(group_id);
CREATE INDEX IF NOT EXISTS idx_group_events_starts ON group_events(starts_at);
CREATE INDEX IF NOT EXISTS idx_group_events_public ON group_events(is_public) WHERE is_public = true;
CREATE INDEX IF NOT EXISTS idx_group_event_rsvps_event ON group_event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_group_event_rsvps_user ON group_event_rsvps(user_id);
