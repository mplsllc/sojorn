package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/patbritton/sojorn-backend/internal/models"
	"github.com/patbritton/sojorn-backend/internal/repository"
	"github.com/patbritton/sojorn-backend/internal/services"
	"github.com/patbritton/sojorn-backend/pkg/utils"
	"github.com/rs/zerolog/log"
)

type NotificationHandler struct {
	notifRepo    *repository.NotificationRepository
	notifService *services.NotificationService
}

func NewNotificationHandler(notifRepo *repository.NotificationRepository, notifService *services.NotificationService) *NotificationHandler {
	return &NotificationHandler{
		notifRepo:    notifRepo,
		notifService: notifService,
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
