-- Add SightEngine configuration column to ai_moderation_config
-- Stores per-type model selections, thresholds, and text moderation options
ALTER TABLE ai_moderation_config
  ADD COLUMN IF NOT EXISTS sightengine_config jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Seed default SightEngine config for image moderation types
UPDATE ai_moderation_config
SET sightengine_config = '{
  "image_models": {
    "nudity": {"enabled": true, "threshold": 0.7},
    "gore": {"enabled": true, "threshold": 0.7},
    "weapon": {"enabled": true, "threshold": 0.7},
    "violence": {"enabled": true, "threshold": 0.7},
    "offensive": {"enabled": true, "threshold": 0.7},
    "recreational_drug": {"enabled": true, "threshold": 0.7},
    "medical": {"enabled": true, "threshold": 0.7},
    "alcohol": {"enabled": false, "threshold": 0.7},
    "tobacco": {"enabled": false, "threshold": 0.7},
    "self-harm": {"enabled": true, "threshold": 0.7},
    "gambling": {"enabled": false, "threshold": 0.7},
    "money": {"enabled": false, "threshold": 0.7},
    "destruction": {"enabled": false, "threshold": 0.7},
    "military": {"enabled": false, "threshold": 0.7},
    "genai": {"enabled": false, "threshold": 0.7},
    "text-content": {"enabled": false, "threshold": 0.7},
    "qr-content": {"enabled": false, "threshold": 0.7}
  },
  "text_models": {
    "sexual": {"enabled": true, "threshold": 0.7},
    "discriminatory": {"enabled": true, "threshold": 0.7},
    "insulting": {"enabled": true, "threshold": 0.7},
    "violent": {"enabled": true, "threshold": 0.7},
    "toxic": {"enabled": true, "threshold": 0.7},
    "self-harm": {"enabled": true, "threshold": 0.7}
  },
  "text_categories": {
    "profanity": true,
    "personal": true,
    "link": true,
    "extremism": true,
    "weapon": false,
    "drug": false,
    "self-harm": true,
    "violence": true,
    "spam": true,
    "content-trade": true,
    "money-transaction": true
  },
  "nsfw_threshold": 0.4,
  "flag_threshold": 0.7
}'::jsonb
WHERE moderation_type IN ('image', 'group_image', 'beacon_image', 'video', 'text', 'group_text', 'beacon_text');
