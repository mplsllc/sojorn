// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type CapsuleHandler struct {
	pool *pgxpool.Pool
}

func NewCapsuleHandler(pool *pgxpool.Pool) *CapsuleHandler {
	return &CapsuleHandler{pool: pool}
}

// ── My Groups ────────────────────────────────────────────────────────────

// ListMyGroups returns all groups the authenticated user belongs to
func (h *CapsuleHandler) ListMyGroups(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT g.id, g.name, g.description, g.type, g.privacy, g.radius_meters,
		       COALESCE(g.avatar_url, '') AS avatar_url,
		       g.member_count, g.is_active, g.is_encrypted,
		       COALESCE(g.settings::text, '{}') AS settings,
		       g.key_version, COALESCE(g.category, 'general') AS category, g.created_at,
		       gm.role, COALESCE(gm.encrypted_group_key, '') AS encrypted_group_key
		FROM groups g
		JOIN group_members gm ON gm.group_id = g.id
		WHERE gm.user_id = $1 AND g.is_active = TRUE
		ORDER BY g.created_at DESC
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch groups"})
		return
	}
	defer rows.Close()

	var groups []gin.H
	for rows.Next() {
		var id uuid.UUID
		var name, desc, typ, privacy, avatarURL, settings, category, role, encKey string
		var radius, memberCount, keyVersion int
		var isActive, isEncrypted bool
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &desc, &typ, &privacy, &radius,
			&avatarURL, &memberCount, &isActive, &isEncrypted, &settings, &keyVersion, &category, &createdAt,
			&role, &encKey); err != nil {
			continue
		}
		groups = append(groups, gin.H{
			"id": id, "name": name, "description": desc, "type": typ,
			"privacy": privacy, "radius_meters": radius, "avatar_url": avatarURL,
			"member_count": memberCount, "is_encrypted": isEncrypted,
			"settings": settings, "key_version": keyVersion, "category": category, "created_at": createdAt,
			"role": role, "encrypted_group_key": encKey,
		})
	}
	if groups == nil {
		groups = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"groups": groups})
}

// ── Discover Groups (browse all public, non-encrypted groups) ────────────

// DiscoverGroups returns public groups the user can join, optionally filtered by category
func (h *CapsuleHandler) DiscoverGroups(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	category := c.Query("category") // optional filter
	limitStr := c.DefaultQuery("limit", "50")
	limit, _ := strconv.Atoi(limitStr)
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	query := `
		SELECT g.id, g.name, g.description, g.type, g.privacy,
		       COALESCE(g.avatar_url, '') AS avatar_url,
		       g.member_count, g.is_encrypted,
		       COALESCE(g.settings::text, '{}') AS settings,
		       g.key_version, COALESCE(g.category, 'general') AS category, g.created_at,
		       EXISTS(SELECT 1 FROM group_members gm WHERE gm.group_id = g.id AND gm.user_id = $1) AS is_member
		FROM groups g
		WHERE g.is_active = TRUE
		  AND g.is_encrypted = FALSE
		  AND g.privacy = 'public'
	`
	args := []interface{}{userID}
	argIdx := 2

	if category != "" && category != "all" {
		query += fmt.Sprintf(" AND g.category = $%d", argIdx)
		args = append(args, category)
		argIdx++
	}

	query += " ORDER BY g.member_count DESC LIMIT " + strconv.Itoa(limit)

	rows, err := h.pool.Query(c.Request.Context(), query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch groups"})
		return
	}
	defer rows.Close()

	var groups []gin.H
	for rows.Next() {
		var id uuid.UUID
		var name, desc, typ, privacy, avatarURL, settings, cat string
		var memberCount, keyVersion int
		var isEncrypted, isMember bool
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &desc, &typ, &privacy, &avatarURL,
			&memberCount, &isEncrypted, &settings, &keyVersion, &cat, &createdAt, &isMember); err != nil {
			continue
		}
		groups = append(groups, gin.H{
			"id": id, "name": name, "description": desc, "type": typ,
			"privacy": privacy, "avatar_url": avatarURL,
			"member_count": memberCount, "is_encrypted": isEncrypted,
			"settings": settings, "key_version": keyVersion,
			"category": cat, "created_at": createdAt, "is_member": isMember,
		})
	}
	if groups == nil {
		groups = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"groups": groups})
}

// ── Private Capsule Endpoints ────────────────────────────────────────────
// CRITICAL: The server NEVER decrypts payload. It only checks membership
// and returns encrypted blobs.

// CreateCapsule creates a new private encrypted group
func (h *CapsuleHandler) CreateCapsule(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Name              string `json:"name"`
		Description       string `json:"description"`
		PublicKey         string `json:"public_key"`
		EncryptedGroupKey string `json:"encrypted_group_key"`
		Settings          string `json:"settings"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Name == "" || req.PublicKey == "" || req.EncryptedGroupKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name, public_key, and encrypted_group_key required"})
		return
	}
	settings := req.Settings
	if settings == "" {
		settings = `{"chat":true,"forum":true,"files":false}`
	}

	ctx := c.Request.Context()
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction failed"})
		return
	}
	defer tx.Rollback(ctx)

	var groupID uuid.UUID
	var createdAt time.Time
	err = tx.QueryRow(ctx, `
		INSERT INTO groups (name, description, type, privacy, is_encrypted, public_key, settings, member_count, key_version)
		VALUES ($1, $2, 'private_capsule', 'private', TRUE, $3, $4::jsonb, 1, 1)
		RETURNING id, created_at
	`, req.Name, req.Description, req.PublicKey, settings).Scan(&groupID, &createdAt)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "A group with this name already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create capsule"})
		return
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role, encrypted_group_key, key_version)
		VALUES ($1, $2, 'owner', $3, 1)
	`, groupID, userID, req.EncryptedGroupKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add owner"})
		return
	}

	// Also store in capsule_keys for the owner
	_, _ = tx.Exec(ctx, `
		INSERT INTO capsule_keys (user_id, group_id, encrypted_key_blob, key_version)
		VALUES ($1, $2, $3, 1)
		ON CONFLICT (user_id, group_id) DO UPDATE SET encrypted_key_blob = $3, key_version = 1
	`, userID, groupID, req.EncryptedGroupKey)

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"capsule": gin.H{
		"id": groupID, "name": req.Name, "description": req.Description,
		"type": "private_capsule", "is_encrypted": true, "key_version": 1,
		"member_count": 1, "created_at": createdAt,
	}})
}

// GetCapsule returns capsule metadata + the user's encrypted group key
func (h *CapsuleHandler) GetCapsule(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	ctx := c.Request.Context()

	// Verify membership and get encrypted key
	var role, encKey string
	var keyVersion int
	err = h.pool.QueryRow(ctx, `
		SELECT role, COALESCE(encrypted_group_key, ''), key_version
		FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role, &encKey, &keyVersion)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member of this capsule"})
		return
	}

	var name, desc, pubKey, settings string
	var memberCount, gKeyVersion int
	var isEncrypted bool
	var createdAt time.Time
	err = h.pool.QueryRow(ctx, `
		SELECT name, description, COALESCE(public_key, ''), COALESCE(settings::text, '{}'),
		       member_count, key_version, is_encrypted, created_at
		FROM groups WHERE id = $1
	`, groupID).Scan(&name, &desc, &pubKey, &settings, &memberCount, &gKeyVersion, &isEncrypted, &createdAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "capsule not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"capsule": gin.H{
			"id": groupID, "name": name, "description": desc,
			"type": "private_capsule", "is_encrypted": isEncrypted,
			"public_key": pubKey, "settings": settings,
			"member_count": memberCount, "key_version": gKeyVersion,
			"created_at": createdAt,
		},
		"membership": gin.H{
			"role": role, "key_version": keyVersion,
		},
		"encrypted_group_key": encKey,
	})
}

// RotateKeys triggers a key rotation — admin re-encrypts and distributes new keys
func (h *CapsuleHandler) RotateKeys(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	ctx := c.Request.Context()

	var role string
	err = h.pool.QueryRow(ctx, `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role)
	if err != nil || role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only owner can rotate keys"})
		return
	}

	var req struct {
		NewPublicKey string            `json:"new_public_key"`
		MemberKeys   map[string]string `json:"member_keys"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	tx, err := h.pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction failed"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		UPDATE groups SET key_version = key_version + 1, public_key = $2, updated_at = NOW()
		WHERE id = $1
	`, groupID, req.NewPublicKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update group key"})
		return
	}

	for uid, encKey := range req.MemberKeys {
		memberID, parseErr := uuid.Parse(uid)
		if parseErr != nil {
			continue
		}
		tx.Exec(ctx, `
			UPDATE group_members SET encrypted_group_key = $3, key_version = (
				SELECT key_version FROM groups WHERE id = $1
			) WHERE group_id = $1 AND user_id = $2
		`, groupID, memberID, encKey)
		// Also update capsule_keys
		tx.Exec(ctx, `
			INSERT INTO capsule_keys (user_id, group_id, encrypted_key_blob, key_version)
			VALUES ($1, $2, $3, (SELECT key_version FROM groups WHERE id = $2))
			ON CONFLICT (user_id, group_id) DO UPDATE
			SET encrypted_key_blob = $3, key_version = (SELECT key_version FROM groups WHERE id = $2), updated_at = NOW()
		`, memberID, groupID, encKey)
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "keys_rotated"})
}

