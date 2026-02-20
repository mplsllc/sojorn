package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"github.com/rs/zerolog/log"
)

type AppealHandler struct {
	appealService *services.AppealService
}

func NewAppealHandler(appealService *services.AppealService) *AppealHandler {
	return &AppealHandler{
		appealService: appealService,
	}
}

// GetUserViolations returns the current user's violation history
func (h *AppealHandler) GetUserViolations(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	// Parse pagination
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	if limit > 100 {
		limit = 100
	}

	violations, err := h.appealService.GetUserViolations(c.Request.Context(), userID, limit, offset)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get user violations")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get violations"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"violations": violations,
		"limit":      limit,
		"offset":     offset,
	})
}

// GetUserViolationSummary returns a summary of user's violation status
func (h *AppealHandler) GetUserViolationSummary(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	summary, err := h.appealService.GetUserViolationSummary(c.Request.Context(), userID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get user violation summary")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get violation summary"})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// CreateAppeal creates an appeal for a violation
func (h *AppealHandler) CreateAppeal(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var req models.UserAppealRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate appeal reason length
	if len(req.AppealReason) < 10 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Appeal reason must be at least 10 characters"})
		return
	}

	if len(req.AppealReason) > 1000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Appeal reason must be less than 1000 characters"})
		return
	}

	// Create appeal
	appeal, err := h.appealService.CreateAppeal(c.Request.Context(), userID, &req)
	if err != nil {
		log.Error().Err(err).Msg("Failed to create appeal")
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"appeal": appeal})
}

// GetAppeal returns details of a specific appeal
func (h *AppealHandler) GetAppeal(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	// Get violation first to check if user owns it
	violationID, err := uuid.Parse(c.Query("violation_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid violation ID"})
		return
	}

	violations, err := h.appealService.GetUserViolations(c.Request.Context(), userID, 1, 0)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get user violations")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get violations"})
		return
	}

	// Check if user has access to this violation
	hasAccess := false
	for _, violation := range violations {
		if violation.ID == violationID {
			hasAccess = true
			break
		}
	}

	if !hasAccess {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
		return
	}

	appeal, err := h.appealService.GetAppealForViolation(c.Request.Context(), violationID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get appeal")
		c.JSON(http.StatusNotFound, gin.H{"error": "Appeal not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"appeal": appeal})
}

