// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

type CategoryHandler struct {
	repo repository.CategoryRepository
}

func NewCategoryHandler(repo repository.CategoryRepository) *CategoryHandler {
	return &CategoryHandler{repo: repo}
}

func (h *CategoryHandler) GetCategories(c *gin.Context) {
	categories, err := h.repo.GetAllCategories(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch categories"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

type CategorySettingRequest struct {
	CategoryID string `json:"category_id" binding:"required"`
	Enabled    bool   `json:"enabled"`
}

type SetCategorySettingsRequest struct {
	Settings []CategorySettingRequest `json:"settings"`
}

func (h *CategoryHandler) SetUserCategorySettings(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req SetCategorySettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Convert to repository format
	settings := make([]repository.CategorySettingInput, len(req.Settings))
	for i, s := range req.Settings {
		settings[i].CategoryID = s.CategoryID
		settings[i].Enabled = s.Enabled
	}

	err := h.repo.SetUserCategorySettings(c.Request.Context(), userIDStr.(string), settings)
	if err != nil {
		internalError(c, "Failed to save settings", err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Settings saved"})
}

func (h *CategoryHandler) GetUserCategorySettings(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	settings, err := h.repo.GetUserCategorySettings(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch settings"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"settings": settings})
}
