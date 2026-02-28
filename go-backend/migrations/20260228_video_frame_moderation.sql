-- Track whether a video post has been frame-moderated.
-- NULL = not yet moderated (eligible for backfill).
-- Non-NULL = moderation completed at this timestamp.
ALTER TABLE posts ADD COLUMN IF NOT EXISTS frames_moderated_at TIMESTAMPTZ;

-- Config: number of frames to extract per video for moderation
INSERT INTO algorithm_config (key, value, description) VALUES
    ('video_moderation_frame_count', '5', 'Number of frames to extract from videos for SightEngine moderation')
ON CONFLICT (key) DO NOTHING;
