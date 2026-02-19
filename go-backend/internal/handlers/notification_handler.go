package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

type NotificationHandler struct {
	notifRepo    *repository.NotificationRepository
	notifService *services.NotificationService
	pool         *pgxpool.Pool
}

func NewNotificationHandler(notifRepo *repository.NotificationRepository, notifService *services.NotificationService, pool *pgxpool.Pool) *NotificationHandler {
	return &NotificationHandler{
		notifRepo:    notifRepo,
		notifService: notifService,
		pool:         pool,
	}
}

// GetNotifications retrieves paginated notifications for the user
// GET /api/v1/notifications
func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)
	grouped := c.Query("grouped") == "true"
	includeArchived := c.Query("include_archived") == "true"

	var notifications []models.Notification
	var err error

	if grouped {
		notifications, err = h.notifRepo.GetGroupedNotifications(c.Request.Context(), userIDStr.(string), limit, offset, includeArchived)
	} else {
		notifications, err = h.notifRepo.GetNotifications(c.Request.Context(), userIDStr.(string), limit, offset, includeArchived)
	}

	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch notifications")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch notifications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notifications": notifications})
}

// GetUnreadCount returns the unread notification count
// GET /api/v1/notifications/unread
func (h *NotificationHandler) GetUnreadCount(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	count, err := h.notifRepo.GetUnreadCount(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch unread count"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"count": count})
}

// GetBadgeCount returns the badge count for app icon badges
// GET /api/v1/notifications/badge
func (h *NotificationHandler) GetBadgeCount(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	badge, err := h.notifRepo.GetUnreadBadge(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch badge count"})
		return
	}

	c.JSON(http.StatusOK, badge)
}

// MarkAsRead marks a single notification as read
// PUT /api/v1/notifications/:id/read
func (h *NotificationHandler) MarkAsRead(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	notificationID := c.Param("id")
	if _, err := uuid.Parse(notificationID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	err := h.notifRepo.MarkAsRead(c.Request.Context(), notificationID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark notification as read"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// BulkMarkAsRead marks a list of notifications as read
// POST /api/v1/notifications/read
func (h *NotificationHandler) BulkMarkAsRead(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req struct {
		IDs []string `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	err := h.notifRepo.MarkNotificationsAsRead(c.Request.Context(), req.IDs, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark notifications as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// Archive archives a list of notifications
// POST /api/v1/notifications/archive
func (h *NotificationHandler) Archive(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req struct {
		IDs []string `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	err := h.notifRepo.ArchiveNotifications(c.Request.Context(), req.IDs, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to archive notifications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ArchiveAll archives all unarchived notifications
// POST /api/v1/notifications/archive-all
func (h *NotificationHandler) ArchiveAll(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	err := h.notifRepo.ArchiveAllNotifications(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to archive all notifications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// MarkAllAsRead marks all notifications as read
// PUT /api/v1/notifications/read-all
func (h *NotificationHandler) MarkAllAsRead(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	err := h.notifRepo.MarkAllAsRead(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark all as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeleteNotification deletes a notification
// DELETE /api/v1/notifications/:id
func (h *NotificationHandler) DeleteNotification(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	notificationID := c.Param("id")
	if _, err := uuid.Parse(notificationID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	err := h.notifRepo.DeleteNotification(c.Request.Context(), notificationID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete notification"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetNotificationPreferences returns the user's notification preferences
// GET /api/v1/notifications/preferences
func (h *NotificationHandler) GetNotificationPreferences(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	prefs, err := h.notifRepo.GetNotificationPreferences(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch preferences"})
		return
	}

	c.JSON(http.StatusOK, prefs)
}

// UpdateNotificationPreferences updates the user's notification preferences
// PUT /api/v1/notifications/preferences
func (h *NotificationHandler) UpdateNotificationPreferences(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	userID, _ := uuid.Parse(userIDStr.(string))

	var prefs models.NotificationPreferences
	if err := c.ShouldBindJSON(&prefs); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	prefs.UserID = userID

	if err := h.notifRepo.UpdateNotificationPreferences(c.Request.Context(), &prefs); err != nil {
		log.Error().Err(err).Msg("Failed to update notification preferences")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update preferences"})
		return
	}

	c.JSON(http.StatusOK, prefs)
}

// RegisterDevice registers an FCM token for push notifications
// POST /api/v1/notifications/device
func (h *NotificationHandler) RegisterDevice(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	userID, _ := uuid.Parse(userIDStr.(string))

	var req models.UserFCMToken
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	req.UserID = userID

	if err := h.notifRepo.UpsertFCMToken(c.Request.Context(), &req); err != nil {
		log.Error().Err(err).Msg("Failed to register device")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to register device"})
		return
	}

	log.Info().
		Str("user_id", userID.String()).
		Str("platform", req.Platform).
		Msg("FCM token registered")

	c.JSON(http.StatusOK, gin.H{"message": "Device registered"})
}

// UnregisterDevice removes an FCM token
// DELETE /api/v1/notifications/device
func (h *NotificationHandler) UnregisterDevice(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req struct {
		FCMToken string `json:"fcm_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if err := h.notifRepo.DeleteFCMToken(c.Request.Context(), userIDStr.(string), req.FCMToken); err != nil {
		log.Error().Err(err).Msg("Failed to unregister device")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unregister device"})
		return
	}

	log.Info().
		Str("user_id", userIDStr.(string)).
		Msg("FCM token unregistered")

	c.JSON(http.StatusOK, gin.H{"message": "Device unregistered"})
}

// UnregisterAllDevices removes all FCM tokens for the user (logout from all devices)
// DELETE /api/v1/notifications/devices
func (h *NotificationHandler) UnregisterAllDevices(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	if err := h.notifRepo.DeleteAllFCMTokensForUser(c.Request.Context(), userIDStr.(string)); err != nil {
		log.Error().Err(err).Msg("Failed to unregister all devices")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unregister devices"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All devices unregistered"})
}

// ActivityLogItem represents a single activity in the user's own activity log
type ActivityLogItem struct {
	ActivityType    string     `json:"activity_type"`
	EntityID        string     `json:"entity_id"`
	CreatedAt       time.Time  `json:"created_at"`
	Body            string     `json:"body,omitempty"`
	ImageURL        string     `json:"image_url,omitempty"`
	TargetName      string     `json:"target_name,omitempty"`
	TargetHandle    string     `json:"target_handle,omitempty"`
	TargetAvatarURL string     `json:"target_avatar_url,omitempty"`
	GroupName       string     `json:"group_name,omitempty"`
	GroupID         string     `json:"group_id,omitempty"`
	Emoji           string     `json:"emoji,omitempty"`
}

// GetActivityLog returns the current user's own activity (posts, comments, reactions, follows given, etc.)
// GET /api/v1/users/me/activity
func (h *NotificationHandler) GetActivityLog(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	limit := utils.GetQueryInt(c, "limit", 30)
	offset := utils.GetQueryInt(c, "offset", 0)
	userID := userIDStr.(string)

	ctx := c.Request.Context()

	// UNION query across all activity types sorted by created_at DESC
	rows, err := h.pool.Query(ctx, `
		(
			-- Standard posts (non-beacon, no parent)
			SELECT 'post' AS activity_type, p.id::text AS entity_id, p.created_at,
			       LEFT(p.body, 120) AS body, COALESCE(p.image_url, '') AS image_url,
			       '' AS target_name, '' AS target_handle, '' AS target_avatar_url,
			       '' AS group_name, '' AS group_id, '' AS emoji
			FROM public.posts p
			WHERE p.author_id = $1::uuid
			  AND COALESCE(p.is_beacon, FALSE) = FALSE
			  AND p.chain_parent_id IS NULL
			  AND p.deleted_at IS NULL AND p.status = 'active'
		)
		UNION ALL
		(
			-- Chain replies / Quips (posts with a parent)
			SELECT 'reply' AS activity_type, p.id::text, p.created_at,
			       LEFT(p.body, 120), COALESCE(p.image_url, ''),
			       COALESCE(pr.display_name, pr.handle, '') AS target_name,
			       COALESCE(pr.handle, '') AS target_handle,
			       COALESCE(pr.avatar_url, '') AS target_avatar_url,
			       '', '', ''
			FROM public.posts p
			JOIN public.posts pp ON pp.id = p.chain_parent_id
			JOIN public.profiles pr ON pr.id = pp.author_id
			WHERE p.author_id = $1::uuid
			  AND p.chain_parent_id IS NOT NULL
			  AND p.deleted_at IS NULL AND p.status = 'active'
		)
		UNION ALL
		(
			-- Beacons
			SELECT 'beacon' AS activity_type, p.id::text, p.created_at,
			       LEFT(p.body, 120), COALESCE(p.image_url, ''),
			       '', '', '', '', '', ''
			FROM public.posts p
			WHERE p.author_id = $1::uuid
			  AND COALESCE(p.is_beacon, FALSE) = TRUE
			  AND p.deleted_at IS NULL AND p.status = 'active'
		)
		UNION ALL
		(
			-- Comments (public.comments table)
			SELECT 'comment' AS activity_type, c.id::text, c.created_at,
			       LEFT(c.body, 120), '',
			       COALESCE(pr.display_name, pr.handle, '') AS target_name,
			       COALESCE(pr.handle, '') AS target_handle,
			       COALESCE(pr.avatar_url, '') AS target_avatar_url,
			       '', '', ''
			FROM public.comments c
			JOIN public.posts p ON p.id = c.post_id
			JOIN public.profiles pr ON pr.id = p.author_id
			WHERE c.author_id = $1::uuid AND c.status = 'active'
		)
		UNION ALL
		(
			-- Follows given
			SELECT 'follow' AS activity_type, f.following_id::text, f.created_at,
			       '', '',
			       COALESCE(pr.display_name, pr.handle, '') AS target_name,
			       COALESCE(pr.handle, '') AS target_handle,
			       COALESCE(pr.avatar_url, '') AS target_avatar_url,
			       '', '', ''
			FROM public.follows f
			JOIN public.profiles pr ON pr.id = f.following_id
			WHERE f.follower_id = $1::uuid AND f.status = 'accepted'
		)
		UNION ALL
		(
			-- Group posts created
			SELECT 'group_post' AS activity_type, gp.id::text, gp.created_at,
			       LEFT(gp.body, 120), COALESCE(gp.image_url, ''),
			       '', '', '',
			       COALESCE(g.name, '') AS group_name, g.id::text AS group_id, ''
			FROM group_posts gp
			JOIN groups g ON g.id = gp.group_id
			WHERE gp.author_id = $1::uuid AND gp.is_deleted = FALSE
		)
		UNION ALL
		(
			-- Group comments
			SELECT 'group_comment' AS activity_type, gc.id::text, gc.created_at,
			       LEFT(gc.body, 120), '',
			       '', '', '',
			       COALESCE(g.name, '') AS group_name, g.id::text AS group_id, ''
			FROM group_post_comments gc
			JOIN group_posts gp ON gp.id = gc.post_id
			JOIN groups g ON g.id = gp.group_id
			WHERE gc.author_id = $1::uuid AND gc.is_deleted = FALSE
		)
		UNION ALL
		(
			-- Group joins
			SELECT 'group_join' AS activity_type, gm.group_id::text, gm.joined_at,
			       '', '', '', '', '',
			       COALESCE(g.name, '') AS group_name, g.id::text AS group_id, ''
			FROM group_members gm
			JOIN groups g ON g.id = gm.group_id
			WHERE gm.user_id = $1::uuid
		)
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch activity log")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch activity log"})
		return
	}
	defer rows.Close()

	var activities []ActivityLogItem
	for rows.Next() {
		var item ActivityLogItem
		if err := rows.Scan(
			&item.ActivityType, &item.EntityID, &item.CreatedAt,
			&item.Body, &item.ImageURL,
			&item.TargetName, &item.TargetHandle, &item.TargetAvatarURL,
			&item.GroupName, &item.GroupID, &item.Emoji,
		); err != nil {
			log.Warn().Err(err).Msg("Failed to scan activity log row")
			continue
		}
		activities = append(activities, item)
	}
	if activities == nil {
		activities = []ActivityLogItem{}
	}

	c.JSON(http.StatusOK, gin.H{"activities": activities})
}

// GetActivityLogItem returns context about a specific notification's linked content
// GET /api/v1/users/me/activity?type=...&entity_id=...
// (reuses GetActivityLog with filtering — already handled by client-side display)

// RecentActivity returns a compact summary for the profile page (last 5 actions)
// GET /api/v1/users/me/recent-activity
func (h *NotificationHandler) RecentActivity(c *gin.Context) {
	c.Request.URL.RawQuery = "limit=5&offset=0"
	h.GetActivityLog(c)
}

