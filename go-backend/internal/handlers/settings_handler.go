// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"github.com/rs/zerolog/log"
)

type SettingsHandler struct {
	userRepo  *repository.UserRepository
	notifRepo *repository.NotificationRepository
}

func NewSettingsHandler(userRepo *repository.UserRepository, notifRepo *repository.NotificationRepository) *SettingsHandler {
	return &SettingsHandler{userRepo: userRepo, notifRepo: notifRepo}
}

func (h *SettingsHandler) GetPrivacySettings(c *gin.Context) {
	userIdStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	settings, err := h.userRepo.GetPrivacySettings(c.Request.Context(), userIdStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get settings"})
		return
	}

	c.JSON(http.StatusOK, settings)
}

func (h *SettingsHandler) UpdatePrivacySettings(c *gin.Context) {
	userIdStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIdStr.(string))

	var ps models.PrivacySettings
	if err := c.ShouldBindJSON(&ps); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	ps.UserID = userID // Ensure ID matches authenticated user

	if err := h.userRepo.UpdatePrivacySettings(c.Request.Context(), &ps); err != nil {
		log.Error().Err(err).Msg("Failed to update privacy settings")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update settings", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, ps)
}

func (h *SettingsHandler) GetUserSettings(c *gin.Context) {
	userIdStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	settings, err := h.userRepo.GetUserSettings(c.Request.Context(), userIdStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get settings"})
		return
	}

	c.JSON(http.StatusOK, settings)
}

func (h *SettingsHandler) UpdateUserSettings(c *gin.Context) {
	userIdStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIdStr.(string))

	var us models.UserSettings
	if err := c.ShouldBindJSON(&us); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	us.UserID = userID

	// Block NSFW toggle for users under 18
	if us.NSFWEnabled != nil && *us.NSFWEnabled {
		profile, err := h.userRepo.GetProfileByID(c.Request.Context(), userID.String())
		if err == nil && profile != nil && profile.BirthYear > 0 {
			now := time.Now()
			age := now.Year() - profile.BirthYear
			if int(now.Month()) < profile.BirthMonth {
				age--
			}
			if age < 18 {
				c.JSON(http.StatusForbidden, gin.H{
					"error": "You must be at least 18 years old to enable sensitive content. This is required by law in most jurisdictions.",
					"code":  "age_restricted_nsfw",
				})
				return
			}
		}
	}

	if err := h.userRepo.UpdateUserSettings(c.Request.Context(), &us); err != nil {
		log.Error().Err(err).Msg("Failed to update user settings")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update settings", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, us)
}

func (h *SettingsHandler) RegisterDevice(c *gin.Context) {
	userIdStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	userID, _ := uuid.Parse(userIdStr.(string))

	var req models.UserFCMToken
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}
	req.UserID = userID

	if err := h.notifRepo.UpsertFCMToken(c.Request.Context(), &req); err != nil {
		log.Error().Err(err).Msg("Failed to register device")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to register device", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Device registered"})
}

func (h *SettingsHandler) UnregisterDevice(c *gin.Context) {
	userIdStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	userID, _ := uuid.Parse(userIdStr.(string))

	var req struct {
		FCMToken string `json:"fcm_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if err := h.notifRepo.DeleteFCMToken(c.Request.Context(), userID.String(), req.FCMToken); err != nil {
		log.Error().Err(err).Msg("Failed to unregister device")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unregister device", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Device unregistered"})
}
