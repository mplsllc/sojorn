// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type DashboardLayoutHandler struct {
	db *pgxpool.Pool
}

func NewDashboardLayoutHandler(db *pgxpool.Pool) *DashboardLayoutHandler {
	return &DashboardLayoutHandler{db: db}
}

// Default layout returned when user has no saved config.
var defaultDashboardLayout = gin.H{
	"left_sidebar": []gin.H{
		{"type": "profile_card", "order": 0, "is_enabled": true},
		{"type": "top8_friends", "order": 1, "is_enabled": true},
	},
	"right_sidebar": []gin.H{
		{"type": "upcoming_events", "order": 0, "is_enabled": true},
		{"type": "whos_online", "order": 1, "is_enabled": true},
	},
	"feed_topbar": []interface{}{},
	"updated_at":  time.Now().Format(time.RFC3339),
}

// GetDashboardLayout — GET /dashboard/layout
func (h *DashboardLayoutHandler) GetDashboardLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var leftJSON, rightJSON, topbarJSON []byte
	var updatedAt time.Time

	err := h.db.QueryRow(c.Request.Context(), `
		SELECT left_sidebar, right_sidebar, feed_topbar, updated_at
		FROM dashboard_layouts
		WHERE user_id = $1
	`, userIDStr).Scan(&leftJSON, &rightJSON, &topbarJSON, &updatedAt)

	if err != nil {
		// No layout yet — return defaults
		c.JSON(http.StatusOK, defaultDashboardLayout)
		return
	}

	var left, right, topbar interface{}
	if err := json.Unmarshal(leftJSON, &left); err != nil {
		left = []interface{}{}
	}
	if err := json.Unmarshal(rightJSON, &right); err != nil {
		right = []interface{}{}
	}
	if err := json.Unmarshal(topbarJSON, &topbar); err != nil {
		topbar = []interface{}{}
	}

	c.JSON(http.StatusOK, gin.H{
		"left_sidebar":  left,
		"right_sidebar": right,
		"feed_topbar":   topbar,
		"updated_at":    updatedAt.Format(time.RFC3339),
	})
}

// GetUserDashboardLayout — GET /users/:userId/dashboard-layout
// Returns another user's dashboard layout (read-only, for profile mirroring).
func (h *DashboardLayoutHandler) GetUserDashboardLayout(c *gin.Context) {
	targetID := c.Param("id")

	var leftJSON, rightJSON, topbarJSON []byte
	var updatedAt time.Time

	err := h.db.QueryRow(c.Request.Context(), `
		SELECT left_sidebar, right_sidebar, feed_topbar, updated_at
		FROM dashboard_layouts
		WHERE user_id = $1
	`, targetID).Scan(&leftJSON, &rightJSON, &topbarJSON, &updatedAt)

	if err != nil {
		c.JSON(http.StatusOK, defaultDashboardLayout)
		return
	}

	var left, right, topbar interface{}
	if err := json.Unmarshal(leftJSON, &left); err != nil {
		left = []interface{}{}
	}
	if err := json.Unmarshal(rightJSON, &right); err != nil {
		right = []interface{}{}
	}
	if err := json.Unmarshal(topbarJSON, &topbar); err != nil {
		topbar = []interface{}{}
	}

	c.JSON(http.StatusOK, gin.H{
		"left_sidebar":  left,
		"right_sidebar": right,
		"feed_topbar":   topbar,
		"updated_at":    updatedAt.Format(time.RFC3339),
	})
}

// SaveDashboardLayout — PUT /dashboard/layout
func (h *DashboardLayoutHandler) SaveDashboardLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var req struct {
		LeftSidebar  interface{} `json:"left_sidebar"`
		RightSidebar interface{} `json:"right_sidebar"`
		FeedTopbar   interface{} `json:"feed_topbar"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	leftJSON, err := json.Marshal(req.LeftSidebar)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid left_sidebar format"})
		return
	}
	rightJSON, err := json.Marshal(req.RightSidebar)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid right_sidebar format"})
		return
	}
	topbarJSON, err := json.Marshal(req.FeedTopbar)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid feed_topbar format"})
		return
	}

	now := time.Now()
	_, err = h.db.Exec(c.Request.Context(), `
		INSERT INTO dashboard_layouts (user_id, left_sidebar, right_sidebar, feed_topbar, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id) DO UPDATE SET
			left_sidebar  = EXCLUDED.left_sidebar,
			right_sidebar = EXCLUDED.right_sidebar,
			feed_topbar   = EXCLUDED.feed_topbar,
			updated_at    = EXCLUDED.updated_at
	`, userIDStr, leftJSON, rightJSON, topbarJSON, now)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save layout"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"left_sidebar":  req.LeftSidebar,
		"right_sidebar": req.RightSidebar,
		"feed_topbar":   req.FeedTopbar,
		"updated_at":    now.Format(time.RFC3339),
	})
}
