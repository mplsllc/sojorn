// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ProfileLayoutHandler struct {
	db *pgxpool.Pool
}

func NewProfileLayoutHandler(db *pgxpool.Pool) *ProfileLayoutHandler {
	return &ProfileLayoutHandler{db: db}
}

// GetProfileLayout — GET /profile/layout
func (h *ProfileLayoutHandler) GetProfileLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var widgetsJSON, leftSidebarJSON, rightSidebarJSON []byte
	var theme string
	var accentColor, bannerImageURL *string
	var updatedAt time.Time

	err := h.db.QueryRow(c.Request.Context(), `
		SELECT widgets, theme, accent_color, banner_image_url, updated_at,
		       desktop_left_sidebar, desktop_right_sidebar
		FROM profile_layouts
		WHERE user_id = $1
	`, userIDStr).Scan(&widgetsJSON, &theme, &accentColor, &bannerImageURL, &updatedAt,
		&leftSidebarJSON, &rightSidebarJSON)

	if err != nil {
		// No layout yet — return empty default
		c.JSON(http.StatusOK, gin.H{
			"widgets":               []interface{}{},
			"theme":                 "default",
			"accent_color":          nil,
			"banner_image_url":      nil,
			"updated_at":            time.Now().Format(time.RFC3339),
			"desktop_left_sidebar":  []interface{}{},
			"desktop_right_sidebar": []interface{}{},
		})
		return
	}

	var widgets, leftSidebar, rightSidebar interface{}
	if err := json.Unmarshal(widgetsJSON, &widgets); err != nil {
		widgets = []interface{}{}
	}
	if err := json.Unmarshal(leftSidebarJSON, &leftSidebar); err != nil {
		leftSidebar = []interface{}{}
	}
	if err := json.Unmarshal(rightSidebarJSON, &rightSidebar); err != nil {
		rightSidebar = []interface{}{}
	}

	c.JSON(http.StatusOK, gin.H{
		"widgets":               widgets,
		"theme":                 theme,
		"accent_color":          accentColor,
		"banner_image_url":      bannerImageURL,
		"updated_at":            updatedAt.Format(time.RFC3339),
		"desktop_left_sidebar":  leftSidebar,
		"desktop_right_sidebar": rightSidebar,
	})
}

// GetPublicProfileLayout — GET /profiles/:id/layout
// Returns another user's profile layout (public-facing, for visitors).
func (h *ProfileLayoutHandler) GetPublicProfileLayout(c *gin.Context) {
	targetID := c.Param("id")

	var widgetsJSON, leftSidebarJSON, rightSidebarJSON []byte
	var theme string
	var accentColor, bannerImageURL *string
	var updatedAt time.Time

	err := h.db.QueryRow(c.Request.Context(), `
		SELECT widgets, theme, accent_color, banner_image_url, updated_at,
		       desktop_left_sidebar, desktop_right_sidebar
		FROM profile_layouts
		WHERE user_id = $1
	`, targetID).Scan(&widgetsJSON, &theme, &accentColor, &bannerImageURL, &updatedAt,
		&leftSidebarJSON, &rightSidebarJSON)

	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"widgets":               []interface{}{},
			"theme":                 "default",
			"accent_color":          nil,
			"banner_image_url":      nil,
			"updated_at":            time.Now().Format(time.RFC3339),
			"desktop_left_sidebar":  []interface{}{},
			"desktop_right_sidebar": []interface{}{},
		})
		return
	}

	var widgets, leftSidebar, rightSidebar interface{}
	if err := json.Unmarshal(widgetsJSON, &widgets); err != nil {
		widgets = []interface{}{}
	}
	if err := json.Unmarshal(leftSidebarJSON, &leftSidebar); err != nil {
		leftSidebar = []interface{}{}
	}
	if err := json.Unmarshal(rightSidebarJSON, &rightSidebar); err != nil {
		rightSidebar = []interface{}{}
	}

	c.JSON(http.StatusOK, gin.H{
		"widgets":               widgets,
		"theme":                 theme,
		"accent_color":          accentColor,
		"banner_image_url":      bannerImageURL,
		"updated_at":            updatedAt.Format(time.RFC3339),
		"desktop_left_sidebar":  leftSidebar,
		"desktop_right_sidebar": rightSidebar,
	})
}

// SaveProfileLayout — PUT /profile/layout
func (h *ProfileLayoutHandler) SaveProfileLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var req struct {
		Widgets            interface{} `json:"widgets"`
		Theme              string      `json:"theme"`
		AccentColor        *string     `json:"accent_color"`
		BannerImageURL     *string     `json:"banner_image_url"`
		DesktopLeftSidebar  interface{} `json:"desktop_left_sidebar"`
		DesktopRightSidebar interface{} `json:"desktop_right_sidebar"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Theme == "" {
		req.Theme = "default"
	}
	if req.Widgets == nil {
		req.Widgets = []interface{}{}
	}
	if req.DesktopLeftSidebar == nil {
		req.DesktopLeftSidebar = []interface{}{}
	}
	if req.DesktopRightSidebar == nil {
		req.DesktopRightSidebar = []interface{}{}
	}

	widgetsJSON, err := json.Marshal(req.Widgets)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid widgets format"})
		return
	}
	leftJSON, err := json.Marshal(req.DesktopLeftSidebar)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid desktop_left_sidebar format"})
		return
	}
	rightJSON, err := json.Marshal(req.DesktopRightSidebar)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid desktop_right_sidebar format"})
		return
	}

	now := time.Now()
	_, err = h.db.Exec(c.Request.Context(), `
		INSERT INTO profile_layouts (user_id, widgets, theme, accent_color, banner_image_url,
		                             desktop_left_sidebar, desktop_right_sidebar, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (user_id) DO UPDATE SET
			widgets               = EXCLUDED.widgets,
			theme                 = EXCLUDED.theme,
			accent_color          = EXCLUDED.accent_color,
			banner_image_url      = EXCLUDED.banner_image_url,
			desktop_left_sidebar  = EXCLUDED.desktop_left_sidebar,
			desktop_right_sidebar = EXCLUDED.desktop_right_sidebar,
			updated_at            = EXCLUDED.updated_at
	`, userIDStr, widgetsJSON, req.Theme, req.AccentColor, req.BannerImageURL,
		leftJSON, rightJSON, now)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save layout"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"widgets":               req.Widgets,
		"theme":                 req.Theme,
		"accent_color":          req.AccentColor,
		"banner_image_url":      req.BannerImageURL,
		"desktop_left_sidebar":  req.DesktopLeftSidebar,
		"desktop_right_sidebar": req.DesktopRightSidebar,
		"updated_at":            now.Format(time.RFC3339),
	})
}
