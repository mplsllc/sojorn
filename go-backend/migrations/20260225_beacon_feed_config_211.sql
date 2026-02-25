-- Seed 211 National Data Platform as a beacon feed source.
-- The resource_211_handler uses lazy on-demand caching (not periodic ingestion),
-- but this row allows admin visibility in the beacon-alerts panel.
INSERT INTO beacon_feed_config (source, enabled)
VALUES ('211', true)
ON CONFLICT (source) DO NOTHING;
