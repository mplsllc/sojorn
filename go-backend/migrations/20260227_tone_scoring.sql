-- Phases 2-5: Tone, Video, Harmony, Moderation scoring columns and config

-- Phase 2: Tone score column
ALTER TABLE post_feed_scores ADD COLUMN IF NOT EXISTS tone_score DOUBLE PRECISION DEFAULT 0;

-- Phase 3: Video boost column + post_views table
ALTER TABLE post_feed_scores ADD COLUMN IF NOT EXISTS video_boost_score DOUBLE PRECISION DEFAULT 0;

CREATE TABLE IF NOT EXISTS post_views (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    view_count INTEGER DEFAULT 1,
    total_duration_ms INTEGER DEFAULT 0,
    last_watch_pct INTEGER DEFAULT 0,
    viewed_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_post_views_post_id ON post_views(post_id);

-- Phase 4: Harmony score column
ALTER TABLE post_feed_scores ADD COLUMN IF NOT EXISTS harmony_score DOUBLE PRECISION DEFAULT 0;

-- Phase 5: Moderation penalty column
ALTER TABLE post_feed_scores ADD COLUMN IF NOT EXISTS moderation_penalty DOUBLE PRECISION DEFAULT 0;

-- Seed all new config keys (Phases 2-5)
INSERT INTO algorithm_config (key, value, description) VALUES
    ('feed_tone_weight', '0.10', 'Weight for content tone in feed ranking'),
    ('feed_quality_weight', '0.15', 'Weight for content quality in feed ranking'),
    ('feed_network_weight', '0.10', 'Weight for network connections in feed ranking'),
    ('feed_personalization_weight', '0.07', 'Weight for personalization in feed ranking'),
    ('tone_positive_boost', '0.15', 'Score boost for positive tone posts'),
    ('tone_negative_penalty', '0.15', 'Score penalty for negative tone posts'),
    ('tone_hostile_penalty', '0.40', 'Score penalty for hostile tone posts'),
    ('feed_video_boost_weight', '0.08', 'Weight for video watch-time boost'),
    ('video_base_boost', '0.05', 'Base score boost for all video content'),
    ('harmony_floor', '0.20', 'Minimum harmony factor for new users'),
    ('feed_moderation_penalty_weight', '0.10', 'Weight for moderation penalty'),
    ('moderation_strike_penalty', '0.15', 'Score penalty per active strike'),
    ('moderation_flag_penalty', '0.10', 'Score penalty per pending flag'),
    ('moderation_flag_penalty_cap', '0.30', 'Maximum total flag penalty')
ON CONFLICT (key) DO NOTHING;
