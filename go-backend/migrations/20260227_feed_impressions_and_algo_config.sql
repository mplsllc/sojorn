-- Feed Impressions & Algorithm Config Migration
-- Creates user_feed_impressions for cooling periods, algorithm_config for admin tuning

-- User feed impressions (tracks which posts a user has seen for cooling)
CREATE TABLE IF NOT EXISTS user_feed_impressions (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    shown_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_user_feed_impressions_user ON user_feed_impressions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_feed_impressions_post ON user_feed_impressions(post_id);

-- Algorithm configuration (key-value store for admin-tunable weights)
CREATE TABLE IF NOT EXISTS algorithm_config (
    key VARCHAR(100) PRIMARY KEY,
    value VARCHAR(100) NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default configuration values
INSERT INTO algorithm_config (key, value, description) VALUES
    ('feed_recency_weight', '0.20', 'Weight for post recency in feed ranking'),
    ('feed_engagement_weight', '0.30', 'Weight for engagement metrics'),
    ('feed_harmony_weight', '0.10', 'Weight for author harmony score'),
    ('feed_diversity_weight', '0.10', 'Weight for content diversity'),
    ('feed_cooling_multiplier', '0.20', 'Score multiplier for previously-seen posts (0-1, lower = stronger penalty)'),
    ('feed_diversity_personal_pct', '60', 'Percentage of feed from top personal scores'),
    ('feed_diversity_category_pct', '20', 'Percentage of feed from under-represented categories'),
    ('feed_diversity_discovery_pct', '20', 'Percentage of feed from authors viewer does not follow'),
    ('moderation_auto_flag_threshold', '0.70', 'AI score threshold for auto-flagging'),
    ('moderation_auto_remove_threshold', '0.95', 'AI score threshold for auto-removal')
ON CONFLICT (key) DO NOTHING;

-- Additional index on post_feed_scores for algorithmic feed ordering
CREATE INDEX IF NOT EXISTS idx_post_feed_scores_score_desc ON post_feed_scores(score DESC);
