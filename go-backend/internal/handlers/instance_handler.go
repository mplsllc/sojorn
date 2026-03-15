// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
)

// InstanceHandler serves the public instance capabilities endpoint.
type InstanceHandler struct {
	db       *pgxpool.Pool
	registry *extension.Registry
}

// NewInstanceHandler creates a new InstanceHandler.
func NewInstanceHandler(db *pgxpool.Pool, registry *extension.Registry) *InstanceHandler {
	return &InstanceHandler{db: db, registry: registry}
}

// GetInstance returns instance metadata and enabled extensions.
// This endpoint is unauthenticated so the app can query it before login.
func (h *InstanceHandler) GetInstance(c *gin.Context) {
	ctx := c.Request.Context()

	// Load instance config from DB.
	rows, err := h.db.Query(ctx, `SELECT key, value FROM instance_config`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load instance config"})
		return
	}
	defer rows.Close()

	cfg := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			continue
		}
		cfg[k] = v
	}

	c.JSON(http.StatusOK, gin.H{
		"name":          cfg["instance_name"],
		"description":   cfg["instance_description"],
		"logo_url":      cfg["instance_logo_url"],
		"accent_color":  cfg["instance_accent_color"],
		"registration":  cfg["registration_mode"],
		"version":       "1.0.0",
		"extensions":    h.registry.EnabledMap(),
	})
}

// AdminGetExtensions returns all registered extensions with their state.
func (h *InstanceHandler) AdminGetExtensions(c *gin.Context) {
	c.JSON(http.StatusOK, h.registry.All())
}

// AdminToggleExtension enables or disables an extension.
func (h *InstanceHandler) AdminToggleExtension(c *gin.Context) {
	id := c.Param("id")

	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	if err := h.registry.SetEnabled(c.Request.Context(), id, req.Enabled); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"id": id, "enabled": req.Enabled})
}

// AdminGetInstanceConfig returns the instance config for the admin settings page.
func (h *InstanceHandler) AdminGetInstanceConfig(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.db.Query(ctx, `SELECT key, value FROM instance_config`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load config"})
		return
	}
	defer rows.Close()

	cfg := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			continue
		}
		cfg[k] = v
	}
	c.JSON(http.StatusOK, cfg)
}

// AdminUpdateInstanceConfig updates instance config key-value pairs.
func (h *InstanceHandler) AdminUpdateInstanceConfig(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	ctx := c.Request.Context()
	for k, v := range req {
		_, err := h.db.Exec(ctx,
			`INSERT INTO instance_config (key, value) VALUES ($1, $2)
			 ON CONFLICT (key) DO UPDATE SET value = $2`, k, v)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update config"})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"updated": len(req)})
}
