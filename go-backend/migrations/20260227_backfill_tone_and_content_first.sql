-- Backfill tone_label from cis_score for all existing posts.
-- Uses the same mapping as post_handler.go:
--   cis >= 0.90 → positive
--   cis >= 0.70 → neutral
--   cis >= 0.50 → mixed
--   cis >= 0.30 → negative
--   cis <  0.30 → hostile

UPDATE posts SET tone_label = CASE
    WHEN cis_score >= 0.90 THEN 'positive'
    WHEN cis_score >= 0.70 THEN 'neutral'
    WHEN cis_score >= 0.50 THEN 'mixed'
    WHEN cis_score >= 0.30 THEN 'negative'
    ELSE 'hostile'
END
WHERE cis_score IS NOT NULL
  AND (tone_label IS NULL OR tone_label = 'neutral');

-- Also backfill comments
UPDATE comments SET tone_label = CASE
    WHEN cis_score >= 0.90 THEN 'positive'
    WHEN cis_score >= 0.70 THEN 'neutral'
    WHEN cis_score >= 0.50 THEN 'mixed'
    WHEN cis_score >= 0.30 THEN 'negative'
    ELSE 'hostile'
END
WHERE cis_score IS NOT NULL
  AND (tone_label IS NULL OR tone_label = 'neutral');

-- Content-first algorithm: update config weights to zero out account-level signals.
-- Posts are scored purely on content merit, not the account posting them.
UPDATE algorithm_config SET value = '0.28', description = 'Weight for engagement in feed ranking (content-first)' WHERE key = 'feed_engagement_weight';
UPDATE algorithm_config SET value = '0.22', description = 'Weight for content quality in feed ranking (content-first)' WHERE key = 'feed_quality_weight';
UPDATE algorithm_config SET value = '0.20', description = 'Weight for recency in feed ranking (content-first)' WHERE key = 'feed_recency_weight';
UPDATE algorithm_config SET value = '0.15', description = 'Weight for content tone in feed ranking (content-first)' WHERE key = 'feed_tone_weight';
UPDATE algorithm_config SET value = '0.0', description = 'Weight for network connections — disabled (content-first: posts stand on their own)' WHERE key = 'feed_network_weight';
UPDATE algorithm_config SET value = '0.0', description = 'Weight for author harmony — disabled (content-first: posts stand on their own)' WHERE key = 'feed_harmony_weight';
UPDATE algorithm_config SET value = '0.0', description = 'Weight for moderation penalty — disabled (content-first: hostile content caught by tone)' WHERE key = 'feed_moderation_penalty_weight';

-- Insert engagement/recency/harmony weights if they don't exist yet (Phase 1A might not have seeded them)
INSERT INTO algorithm_config (key, value, description) VALUES
    ('feed_engagement_weight', '0.28', 'Weight for engagement in feed ranking (content-first)'),
    ('feed_recency_weight', '0.20', 'Weight for recency in feed ranking (content-first)'),
    ('feed_harmony_weight', '0.0', 'Weight for author harmony — disabled (content-first)')
ON CONFLICT (key) DO NOTHING;
