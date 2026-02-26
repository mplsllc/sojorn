-- Add scoping columns to reports table for neighborhood and group context
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES groups(id);
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS neighborhood_id UUID REFERENCES neighborhood_seeds(id);

CREATE INDEX IF NOT EXISTS idx_reports_group_id ON public.reports(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_neighborhood_id ON public.reports(neighborhood_id) WHERE neighborhood_id IS NOT NULL;
