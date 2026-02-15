package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/patbritton/sojorn-backend/internal/models"
	"github.com/rs/zerolog/log"
)

type NotificationRepository struct {
	pool *pgxpool.Pool
}

func NewNotificationRepository(pool *pgxpool.Pool) *NotificationRepository {
	return &NotificationRepository{pool: pool}
}

// ============================================================================
// FCM Token Management
// ============================================================================

func (r *NotificationRepository) UpsertFCMToken(ctx context.Context, token *models.UserFCMToken) error {
	query := `
		INSERT INTO public.user_fcm_tokens (user_id, token, device_type, created_at, last_updated)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, token) 
		DO UPDATE SET 
			device_type = EXCLUDED.device_type,
			last_updated = EXCLUDED.last_updated
	`
	_, err := r.pool.Exec(ctx, query,
		token.UserID,
		token.FCMToken,
		token.Platform,
		time.Now(),
		time.Now(),
	)
	return err
}

func (r *NotificationRepository) GetFCMTokensForUser(ctx context.Context, userID string) ([]string, error) {
	query := `
		SELECT token
		FROM public.user_fcm_tokens
		WHERE user_id = $1::uuid
	`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			return nil, err
		}
		tokens = append(tokens, token)
	}

	return tokens, nil
}

func (r *NotificationRepository) DeleteFCMToken(ctx context.Context, userID string, token string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM public.user_fcm_tokens
		WHERE user_id = $1::uuid AND token = $2
	`, userID, token)
	return err
}

func (r *NotificationRepository) DeleteAllFCMTokensForUser(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM public.user_fcm_tokens WHERE user_id = $1::uuid
	`, userID)
	return err
}

// ============================================================================
// Notification CRUD
// ============================================================================

func (r *NotificationRepository) CreateNotification(ctx context.Context, notif *models.Notification) error {
	query := `
		INSERT INTO public.notifications (user_id, type, actor_id, post_id, comment_id, is_read, metadata, group_key, priority)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, created_at
	`

	priority := notif.Priority
	if priority == "" {
		priority = models.PriorityNormal
	}

	err := r.pool.QueryRow(ctx, query,
		notif.UserID, notif.Type, notif.ActorID, notif.PostID, notif.CommentID, notif.IsRead, notif.Metadata, notif.GroupKey, priority,
	).Scan(&notif.ID, &notif.CreatedAt)

	return err
}

func (r *NotificationRepository) GetNotifications(ctx context.Context, userID string, limit, offset int, includeArchived bool) ([]models.Notification, error) {
	whereClause := "WHERE n.user_id = $1::uuid AND n.archived_at IS NULL AND n.type != 'message'"
	if includeArchived {
		whereClause = "WHERE n.user_id = $1::uuid AND n.archived_at IS NOT NULL AND n.type != 'message'"
	}

	query := `
		SELECT 
			n.id, n.user_id, n.type, n.actor_id, n.post_id, n.comment_id, n.is_read, n.created_at, n.archived_at, n.metadata,
			COALESCE(n.group_key, '') as group_key,
			COALESCE(n.priority, 'normal') as priority,
			pr.handle, pr.display_name, COALESCE(pr.avatar_url, ''),
			po.image_url,
			LEFT(po.body, 100) as post_body
		FROM public.notifications n
		JOIN public.profiles pr ON n.actor_id = pr.id
		LEFT JOIN public.posts po ON n.post_id = po.id
		` + whereClause + `
		ORDER BY n.created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	notifications := []models.Notification{}
	for rows.Next() {
		var n models.Notification
		var groupKey string
		var postImageURL *string
		var postBody *string
		err := rows.Scan(
			&n.ID, &n.UserID, &n.Type, &n.ActorID, &n.PostID, &n.CommentID, &n.IsRead, &n.CreatedAt, &n.ArchivedAt, &n.Metadata,
			&groupKey, &n.Priority,
			&n.ActorHandle, &n.ActorDisplayName, &n.ActorAvatarURL,
			&postImageURL, &postBody,
		)
		if err != nil {
			return nil, err
		}
		if groupKey != "" {
			n.GroupKey = &groupKey
		}
		n.PostImageURL = postImageURL
		n.PostBody = postBody
		notifications = append(notifications, n)
	}
	return notifications, nil
}

// GetGroupedNotifications returns notifications with grouping (e.g., "5 people liked your post")
func (r *NotificationRepository) GetGroupedNotifications(ctx context.Context, userID string, limit, offset int, includeArchived bool) ([]models.Notification, error) {
	whereClause := "WHERE n.user_id = $1::uuid AND n.archived_at IS NULL AND n.type != 'message'"
	if includeArchived {
		whereClause = "WHERE n.user_id = $1::uuid AND n.archived_at IS NOT NULL AND n.type != 'message'"
	}

	query := `
		WITH ranked AS (
			SELECT 
				n.*,
				pr.handle as actor_handle,
				pr.display_name as actor_display_name,
				COALESCE(pr.avatar_url, '') as actor_avatar_url,
				po.image_url as post_image_url,
				LEFT(po.body, 100) as post_body,
				COUNT(*) OVER (PARTITION BY n.group_key) as group_count,
				ROW_NUMBER() OVER (PARTITION BY n.group_key ORDER BY n.created_at DESC) as rn
			FROM public.notifications n
			JOIN public.profiles pr ON n.actor_id = pr.id
			LEFT JOIN public.posts po ON n.post_id = po.id
			` + whereClause + `
		)
		SELECT 
			id, user_id, type, actor_id, post_id, comment_id, is_read, created_at, archived_at, metadata,
			COALESCE(group_key, '') as group_key,
			COALESCE(priority, 'normal') as priority,
			actor_handle, actor_display_name, actor_avatar_url,
			post_image_url, post_body,
			group_count
		FROM ranked
		WHERE rn = 1 OR group_key IS NULL
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := r.pool.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	notifications := []models.Notification{}
	for rows.Next() {
		var n models.Notification
		var groupKey string
		err := rows.Scan(
			&n.ID, &n.UserID, &n.Type, &n.ActorID, &n.PostID, &n.CommentID, &n.IsRead, &n.CreatedAt, &n.ArchivedAt, &n.Metadata,
			&groupKey, &n.Priority,
			&n.ActorHandle, &n.ActorDisplayName, &n.ActorAvatarURL,
			&n.PostImageURL, &n.PostBody,
			&n.GroupCount,
		)
		if err != nil {
			return nil, err
		}
		if groupKey != "" {
			n.GroupKey = &groupKey
		}
		notifications = append(notifications, n)
	}
	return notifications, nil
}

func (r *NotificationRepository) MarkAsRead(ctx context.Context, notificationID, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.notifications SET is_read = TRUE 
		WHERE id = $1::uuid AND user_id = $2::uuid
	`, notificationID, userID)
	return err
}

func (r *NotificationRepository) MarkAllAsRead(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.notifications SET is_read = TRUE 
		WHERE user_id = $1::uuid AND is_read = FALSE
	`, userID)
	return err
}

func (r *NotificationRepository) DeleteNotification(ctx context.Context, notificationID, userID string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM public.notifications 
		WHERE id = $1::uuid AND user_id = $2::uuid
	`, notificationID, userID)
	return err
}

func (r *NotificationRepository) MarkNotificationsAsRead(ctx context.Context, ids []string, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.notifications SET is_read = TRUE 
		WHERE id = ANY($1::uuid[]) AND user_id = $2::uuid
	`, ids, userID)
	return err
}

func (r *NotificationRepository) ArchiveNotifications(ctx context.Context, ids []string, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.notifications SET archived_at = NOW(), is_read = TRUE 
		WHERE id = ANY($1::uuid[]) AND user_id = $2::uuid
	`, ids, userID)
	if err != nil {
		return err
	}
	// Recalculate badge count excluding archived and message types
	_, err = r.pool.Exec(ctx, `
		UPDATE profiles SET unread_notification_count = (
			SELECT COUNT(*) FROM notifications WHERE user_id = $1::uuid AND is_read = FALSE AND archived_at IS NULL AND type != 'message'
		) WHERE id = $1::uuid
	`, userID)
	return err
}

func (r *NotificationRepository) ArchiveAllNotifications(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.notifications SET archived_at = NOW(), is_read = TRUE 
		WHERE user_id = $1::uuid AND archived_at IS NULL
	`, userID)
	if err != nil {
		return err
	}
	// Reset badge count — all notifications are now archived and read
	_, err = r.pool.Exec(ctx, `
		UPDATE profiles SET unread_notification_count = 0 WHERE id = $1::uuid
	`, userID)
	return err
}

func (r *NotificationRepository) GetUnreadCount(ctx context.Context, userID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM public.notifications 
		WHERE user_id = $1::uuid AND is_read = FALSE AND archived_at IS NULL AND type != 'message'
	`, userID).Scan(&count)
	return count, err
}

func (r *NotificationRepository) GetUnreadBadge(ctx context.Context, userID string) (*models.UnreadBadge, error) {
	badge := &models.UnreadBadge{}

	// Get notification count (live query, excludes archived and chat messages)
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM public.notifications 
		WHERE user_id = $1::uuid AND is_read = FALSE AND archived_at IS NULL AND type != 'message'
	`, userID).Scan(&badge.NotificationCount)
	if err != nil {
		return nil, err
	}

	// Get unread message count
	err = r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM encrypted_messages 
		WHERE receiver_id = $1::uuid AND is_read = FALSE
	`, userID).Scan(&badge.MessageCount)
	if err != nil {
		// Table might not exist or column missing, ignore
		badge.MessageCount = 0
	}

	badge.TotalCount = badge.NotificationCount + badge.MessageCount
	return badge, nil
}

// ============================================================================
// Notification Preferences
// ============================================================================

func (r *NotificationRepository) GetNotificationPreferences(ctx context.Context, userID string) (*models.NotificationPreferences, error) {
	prefs := &models.NotificationPreferences{}

	err := r.pool.QueryRow(ctx, `
		SELECT 
			user_id, push_enabled, push_likes, push_comments, push_replies, push_mentions,
			push_follows, push_follow_requests, push_messages, push_saves, push_beacons,
			email_enabled, email_digest_frequency, quiet_hours_enabled,
			quiet_hours_start::text, quiet_hours_end::text, show_badge_count,
			created_at, updated_at
		FROM notification_preferences
		WHERE user_id = $1::uuid
	`, userID).Scan(
		&prefs.UserID, &prefs.PushEnabled, &prefs.PushLikes, &prefs.PushComments, &prefs.PushReplies, &prefs.PushMentions,
		&prefs.PushFollows, &prefs.PushFollowRequests, &prefs.PushMessages, &prefs.PushSaves, &prefs.PushBeacons,
		&prefs.EmailEnabled, &prefs.EmailDigestFrequency, &prefs.QuietHoursEnabled,
		&prefs.QuietHoursStart, &prefs.QuietHoursEnd, &prefs.ShowBadgeCount,
		&prefs.CreatedAt, &prefs.UpdatedAt,
	)

	if err != nil {
		// Return defaults if not found
		return r.createDefaultPreferences(ctx, userID)
	}

	return prefs, nil
}

func (r *NotificationRepository) createDefaultPreferences(ctx context.Context, userID string) (*models.NotificationPreferences, error) {
	userUUID, err := uuid.Parse(userID)
	if err != nil {
		return nil, err
	}

	prefs := &models.NotificationPreferences{
		UserID:               userUUID,
		PushEnabled:          true,
		PushLikes:            true,
		PushComments:         true,
		PushReplies:          true,
		PushMentions:         true,
		PushFollows:          true,
		PushFollowRequests:   true,
		PushMessages:         true,
		PushSaves:            true,
		PushBeacons:          true,
		EmailEnabled:         false,
		EmailDigestFrequency: "never",
		QuietHoursEnabled:    false,
		ShowBadgeCount:       true,
		CreatedAt:            time.Now(),
		UpdatedAt:            time.Now(),
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO notification_preferences (user_id, push_enabled, push_likes, push_comments, push_replies, push_mentions,
			push_follows, push_follow_requests, push_messages, push_saves, push_beacons,
			email_enabled, email_digest_frequency, quiet_hours_enabled, show_badge_count)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
		ON CONFLICT (user_id) DO NOTHING
	`,
		prefs.UserID, prefs.PushEnabled, prefs.PushLikes, prefs.PushComments, prefs.PushReplies, prefs.PushMentions,
		prefs.PushFollows, prefs.PushFollowRequests, prefs.PushMessages, prefs.PushSaves, prefs.PushBeacons,
		prefs.EmailEnabled, prefs.EmailDigestFrequency, prefs.QuietHoursEnabled, prefs.ShowBadgeCount,
	)

	return prefs, err
}

func (r *NotificationRepository) UpdateNotificationPreferences(ctx context.Context, prefs *models.NotificationPreferences) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO notification_preferences (
			user_id, push_enabled, push_likes, push_comments, push_replies, push_mentions,
			push_follows, push_follow_requests, push_messages, push_saves, push_beacons,
			email_enabled, email_digest_frequency, quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
			show_badge_count, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15::time, $16::time, $17, NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			push_enabled = EXCLUDED.push_enabled,
			push_likes = EXCLUDED.push_likes,
			push_comments = EXCLUDED.push_comments,
			push_replies = EXCLUDED.push_replies,
			push_mentions = EXCLUDED.push_mentions,
			push_follows = EXCLUDED.push_follows,
			push_follow_requests = EXCLUDED.push_follow_requests,
			push_messages = EXCLUDED.push_messages,
			push_saves = EXCLUDED.push_saves,
			push_beacons = EXCLUDED.push_beacons,
			email_enabled = EXCLUDED.email_enabled,
			email_digest_frequency = EXCLUDED.email_digest_frequency,
			quiet_hours_enabled = EXCLUDED.quiet_hours_enabled,
			quiet_hours_start = EXCLUDED.quiet_hours_start,
			quiet_hours_end = EXCLUDED.quiet_hours_end,
			show_badge_count = EXCLUDED.show_badge_count,
			updated_at = NOW()
	`,
		prefs.UserID, prefs.PushEnabled, prefs.PushLikes, prefs.PushComments, prefs.PushReplies, prefs.PushMentions,
		prefs.PushFollows, prefs.PushFollowRequests, prefs.PushMessages, prefs.PushSaves, prefs.PushBeacons,
		prefs.EmailEnabled, prefs.EmailDigestFrequency, prefs.QuietHoursEnabled, prefs.QuietHoursStart, prefs.QuietHoursEnd,
		prefs.ShowBadgeCount,
	)
	return err
}

// ShouldSendPush checks user preferences and quiet hours to determine if push should be sent
func (r *NotificationRepository) ShouldSendPush(ctx context.Context, userID, notificationType string) (bool, error) {
	prefs, err := r.GetNotificationPreferences(ctx, userID)
	if err != nil {
		log.Warn().Err(err).Str("user_id", userID).Msg("Failed to get notification preferences, defaulting to send")
		return true, nil
	}

	if !prefs.PushEnabled {
		return false, nil
	}

	// Check quiet hours
	if prefs.QuietHoursEnabled && prefs.QuietHoursStart != nil && prefs.QuietHoursEnd != nil {
		if r.isInQuietHours(*prefs.QuietHoursStart, *prefs.QuietHoursEnd) {
			return false, nil
		}
	}

	// Check specific notification type
	switch notificationType {
	case models.NotificationTypeLike:
		return prefs.PushLikes, nil
	case models.NotificationTypeComment:
		return prefs.PushComments, nil
	case models.NotificationTypeReply:
		return prefs.PushReplies, nil
	case models.NotificationTypeMention:
		return prefs.PushMentions, nil
	case models.NotificationTypeFollow:
		return prefs.PushFollows, nil
	case models.NotificationTypeFollowRequest:
		return prefs.PushFollowRequests, nil
	case models.NotificationTypeMessage:
		return prefs.PushMessages, nil
	case models.NotificationTypeSave:
		return prefs.PushSaves, nil
	case models.NotificationTypeBeaconVouch, models.NotificationTypeBeaconReport:
		return prefs.PushBeacons, nil
	default:
		return true, nil
	}
}

func (r *NotificationRepository) isInQuietHours(start, end string) bool {
	now := time.Now().UTC()
	currentTime := now.Format("15:04:05")

	// Simple string comparison for time ranges
	// Handle cases where quiet hours span midnight
	if start > end {
		// Spans midnight: 22:00 -> 08:00
		return currentTime >= start || currentTime <= end
	}
	// Same day: 23:00 -> 23:59
	return currentTime >= start && currentTime <= end
}

// ============================================================================
// Mention Extraction
// ============================================================================

// ExtractMentions finds @username patterns in text and returns user IDs
func (r *NotificationRepository) ExtractMentions(ctx context.Context, text string) ([]uuid.UUID, error) {
	// Extract @mentions using regex
	mentions := extractMentionHandles(text)
	if len(mentions) == 0 {
		return nil, nil
	}

	// Look up user IDs for handles
	query := `SELECT id FROM profiles WHERE handle = ANY($1)`
	rows, err := r.pool.Query(ctx, query, mentions)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userIDs []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			continue
		}
		userIDs = append(userIDs, id)
	}

	return userIDs, nil
}

func extractMentionHandles(text string) []string {
	var mentions []string
	inMention := false
	current := ""

	for i, r := range text {
		if r == '@' {
			inMention = true
			current = ""
			continue
		}

		if inMention {
			// Valid handle characters: alphanumeric and underscore
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
				current += string(r)
			} else {
				if len(current) > 0 {
					mentions = append(mentions, current)
				}
				inMention = false
				current = ""
			}
		}

		// Check end of string
		if i == len(text)-1 && inMention && len(current) > 0 {
			mentions = append(mentions, current)
		}
	}

	return mentions
}

// ============================================================================
// Notification Cleanup
// ============================================================================

// DeleteOldNotifications removes notifications older than the specified days
func (r *NotificationRepository) DeleteOldNotifications(ctx context.Context, daysOld int) (int64, error) {
	result, err := r.pool.Exec(ctx, `
		DELETE FROM notifications 
		WHERE created_at < NOW() - INTERVAL '1 day' * $1
	`, daysOld)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// ArchiveOldNotifications marks old notifications as archived instead of deleting
func (r *NotificationRepository) ArchiveOldNotifications(ctx context.Context, daysOld int) (int64, error) {
	result, err := r.pool.Exec(ctx, `
		UPDATE notifications 
		SET archived_at = NOW()
		WHERE created_at < NOW() - INTERVAL '1 day' * $1 AND archived_at IS NULL
	`, daysOld)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// ============================================================================
// Helper for building metadata JSON
// ============================================================================

func BuildNotificationMetadata(data map[string]interface{}) json.RawMessage {
	if data == nil {
		return json.RawMessage("{}")
	}
	bytes, err := json.Marshal(data)
	if err != nil {
		return json.RawMessage("{}")
	}
	return bytes
}
