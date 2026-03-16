// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"golang.org/x/crypto/bcrypt"
)

// InstanceHandler serves the public instance capabilities endpoint.
type InstanceHandler struct {
	db        *pgxpool.Pool
	registry  *extension.Registry
	jwtSecret string
}

// NewInstanceHandler creates a new InstanceHandler.
func NewInstanceHandler(db *pgxpool.Pool, registry *extension.Registry, jwtSecret string) *InstanceHandler {
	return &InstanceHandler{db: db, registry: registry, jwtSecret: jwtSecret}
}

// SetupStatus returns whether the instance has been configured (i.e. an admin exists).
func (h *InstanceHandler) SetupStatus(c *gin.Context) {
	ctx := c.Request.Context()
	var count int
	err := h.db.QueryRow(ctx, `SELECT count(*) FROM profiles WHERE role = 'admin'`).Scan(&count)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check setup status"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"configured": count > 0})
}

// setupRequest is the JSON body for the one-time instance setup endpoint.
type setupRequest struct {
	Handle              string `json:"handle"`
	Email               string `json:"email"`
	Password            string `json:"password"`
	InstanceName        string `json:"instance_name"`
	InstanceDescription string `json:"instance_description"`
	RegistrationMode    string `json:"registration_mode"`
}

// Setup is a ONE-TIME endpoint that creates the first admin account and configures instance settings.
func (h *InstanceHandler) Setup(c *gin.Context) {
	ctx := c.Request.Context()

	// 1. Check if any admin already exists
	var adminCount int
	if err := h.db.QueryRow(ctx, `SELECT count(*) FROM profiles WHERE role = 'admin'`).Scan(&adminCount); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check admin status"})
		return
	}
	if adminCount > 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "Instance already configured"})
		return
	}

	// 2. Parse request body
	var req setupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	// 3. Validate fields
	req.Handle = strings.TrimSpace(req.Handle)
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	if req.Handle == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "handle is required"})
		return
	}
	if req.Email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "email is required"})
		return
	}
	if _, err := mail.ParseAddress(req.Email); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid email address"})
		return
	}
	if len(req.Password) < 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be at least 8 characters"})
		return
	}

	// 4. Hash password
	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(req.Password), 10)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	// 5. Create user + profile in a transaction
	userID := uuid.New()
	now := time.Now().UTC()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO public.users (id, email, encrypted_password, status, mfa_enabled, created_at, updated_at)
		VALUES ($1, $2, $3, 'active', false, $4, $4)
	`, userID, req.Email, string(hashedBytes), now)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "a user with that email already exists"})
			return
		}
		log.Error().Err(err).Msg("Setup: failed to create user")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO public.profiles (id, handle, display_name, role, is_verified, is_official, has_completed_onboarding)
		VALUES ($1, $2, $3, 'admin', true, true, true)
	`, userID, req.Handle, req.Handle)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "a user with that handle already exists"})
			return
		}
		log.Error().Err(err).Msg("Setup: failed to create profile")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create profile"})
		return
	}

	// 6. Save instance config
	configPairs := map[string]string{}
	if req.InstanceName != "" {
		configPairs["instance_name"] = req.InstanceName
	}
	if req.InstanceDescription != "" {
		configPairs["instance_description"] = req.InstanceDescription
	}
	if req.RegistrationMode != "" {
		configPairs["registration_mode"] = req.RegistrationMode
	}

	for k, v := range configPairs {
		_, err := tx.Exec(ctx,
			`INSERT INTO instance_config (key, value) VALUES ($1, $2)
			 ON CONFLICT (key) DO UPDATE SET value = $2`, k, v)
		if err != nil {
			log.Error().Err(err).Str("key", k).Msg("Setup: failed to save instance config")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save instance config"})
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		log.Error().Err(err).Msg("Setup: failed to commit transaction")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to complete setup"})
		return
	}

	// 7. Generate JWT token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  userID.String(),
		"exp":  time.Now().Add(15 * time.Minute).Unix(),
		"role": "authenticated",
	})
	tokenString, err := token.SignedString([]byte(h.jwtSecret))
	if err != nil {
		log.Error().Err(err).Msg("Setup: failed to generate JWT")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	log.Info().Str("handle", req.Handle).Str("email", req.Email).Msg("Setup: admin account created via setup wizard")

	// 8. Return token and user info
	c.JSON(http.StatusOK, gin.H{
		"token": tokenString,
		"user": gin.H{
			"id":     userID.String(),
			"handle": req.Handle,
			"role":   "admin",
		},
	})
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
		"contact_email": cfg["contact_email"],
		"terms_url":     cfg["terms_url"],
		"privacy_url":   cfg["privacy_url"],
		"version":       "1.0.0",
		"extensions":    h.registry.EnabledMap(),
	})
}

// GetAbout returns public "about this instance" information including stats.
func (h *InstanceHandler) GetAbout(c *gin.Context) {
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

	// Gather stats.
	var userCount, postCount, monthlyActiveUsers int

	_ = h.db.QueryRow(ctx,
		`SELECT count(*) FROM profiles WHERE status = 'active'`).Scan(&userCount)

	_ = h.db.QueryRow(ctx,
		`SELECT count(*) FROM posts WHERE status = 'active'`).Scan(&postCount)

	_ = h.db.QueryRow(ctx,
		`SELECT count(DISTINCT author_id) FROM posts WHERE created_at > NOW() - INTERVAL '30 days'`).Scan(&monthlyActiveUsers)

	c.JSON(http.StatusOK, gin.H{
		"name":                 cfg["instance_name"],
		"description":          cfg["instance_description"],
		"contact_email":        cfg["contact_email"],
		"terms_url":            cfg["terms_url"],
		"privacy_url":          cfg["privacy_url"],
		"version":              "1.0.0",
		"extensions":           h.registry.EnabledMap(),
		"stats": gin.H{
			"user_count":          userCount,
			"post_count":          postCount,
			"monthly_active_users": monthlyActiveUsers,
		},
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
