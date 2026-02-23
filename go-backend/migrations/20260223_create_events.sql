-- Copyright (c) 2026 MPLS LLC
-- Events system — Phase 3 of the Sojorn ecosystem.
--
-- Architecture (clean-room, inspired by Hi.Events schema design):
--   events           — the event itself (organizer, time, place, capacity)
--   event_rsvps      — per-user attendance intent (going / interested / not_going)
--
-- Events integrate with:
--   - Beacon map      : events with lat/long get a 🎉 marker type
--   - Home feed       : events from followed users + joined groups surface as EventCard
--   - Group boards    : creating an event auto-posts to the group's Feed tab
--   - Notifications   : RSVP changes notify the organizer
--   - Profile widgets : "Upcoming events" widget pulls from event_rsvps WHERE user_id = me

CREATE TABLE IF NOT EXISTS public.events (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  group_id          UUID        REFERENCES public.groups(id) ON DELETE SET NULL,
  title             VARCHAR(255) NOT NULL,
  description       TEXT,
  start_time        TIMESTAMPTZ NOT NULL,
  end_time          TIMESTAMPTZ,
  location_name     VARCHAR(255),
  location_lat      DOUBLE PRECISION,
  location_long     DOUBLE PRECISION,
  cover_image_url   TEXT,
  category          VARCHAR(50)  NOT NULL DEFAULT 'general',
  -- Category values: general, social, sports, education, arts, fundraiser,
  --                  government, religious, community, marketplace
  status            VARCHAR(20)  NOT NULL DEFAULT 'published',
  -- Status values: draft, published, cancelled, completed
  capacity          INT,          -- NULL = unlimited attendance
  rsvp_count        INT          NOT NULL DEFAULT 0, -- denormalised for cheap reads
  is_online         BOOLEAN      NOT NULL DEFAULT FALSE,
  online_url        TEXT,
  deleted_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    UUID        NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status      VARCHAR(20) NOT NULL DEFAULT 'going',
  -- Status values: going, interested, not_going
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, user_id)
);

-- Spatial index for map pin queries ("events near me")
CREATE INDEX IF NOT EXISTS events_location_idx
  ON public.events (location_lat, location_long)
  WHERE location_lat IS NOT NULL AND location_long IS NOT NULL
    AND status = 'published' AND deleted_at IS NULL;

-- Time index for feed queries ("upcoming events")
CREATE INDEX IF NOT EXISTS events_start_time_idx
  ON public.events (start_time ASC)
  WHERE status = 'published' AND deleted_at IS NULL;

-- Per-organiser index for profile widget
CREATE INDEX IF NOT EXISTS events_organizer_idx
  ON public.events (organizer_id, start_time ASC)
  WHERE deleted_at IS NULL;

-- RSVP lookup (user's upcoming events)
CREATE INDEX IF NOT EXISTS event_rsvps_user_idx
  ON public.event_rsvps (user_id, event_id);

-- Trigger: keep rsvp_count denormalised on events table
CREATE OR REPLACE FUNCTION update_event_rsvp_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'going' THEN
    UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
  ELSIF TG_OP = 'DELETE' AND OLD.status = 'going' THEN
    UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = OLD.event_id;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'going' AND NEW.status != 'going' THEN
      UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = NEW.event_id;
    ELSIF OLD.status != 'going' AND NEW.status = 'going' THEN
      UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_rsvp_count ON public.event_rsvps;
CREATE TRIGGER trg_event_rsvp_count
  AFTER INSERT OR UPDATE OR DELETE ON public.event_rsvps
  FOR EACH ROW EXECUTE FUNCTION update_event_rsvp_count();
