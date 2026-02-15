-- Drop old restrictive CHECK and add one matching the actual statuses used
ALTER TABLE moderation_flags DROP CONSTRAINT IF EXISTS moderation_flags_status_check;
ALTER TABLE moderation_flags ADD CONSTRAINT moderation_flags_status_check
  CHECK (status = ANY (ARRAY['pending', 'approved', 'rejected', 'escalated', 'dismissed', 'actioned']));
