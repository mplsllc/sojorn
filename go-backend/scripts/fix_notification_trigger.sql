CREATE OR REPLACE FUNCTION update_unread_notification_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.archived_at IS NULL THEN
        UPDATE profiles SET unread_notification_count = unread_notification_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.is_read = FALSE AND (NEW.is_read = TRUE OR NEW.archived_at IS NOT NULL) THEN
            UPDATE profiles SET unread_notification_count = GREATEST(0, unread_notification_count - 1) WHERE id = NEW.user_id;
        END IF;
    ELSIF TG_OP = 'DELETE' AND OLD.is_read = FALSE AND OLD.archived_at IS NULL THEN
        UPDATE profiles SET unread_notification_count = GREATEST(0, unread_notification_count - 1) WHERE id = OLD.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
