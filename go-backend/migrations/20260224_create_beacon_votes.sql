-- Beacon vouch/report tables for community validation of beacon posts.
-- Referenced by GetNearbyBeacons, VouchBeacon, ReportBeacon, RemoveBeaconVote.

CREATE TABLE IF NOT EXISTS public.beacon_vouches (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beacon_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (beacon_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.beacon_reports (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beacon_id  UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (beacon_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_beacon_vouches_beacon ON public.beacon_vouches(beacon_id);
CREATE INDEX IF NOT EXISTS idx_beacon_reports_beacon ON public.beacon_reports(beacon_id);
