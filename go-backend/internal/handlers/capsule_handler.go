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

// CreateGroup creates a non-encrypted public or private group
func (h *CapsuleHandler) CreateGroup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		Privacy     string `json:"privacy"`  // "public" or "private"
		Category    string `json:"category"` // general, hobby, sports, professional, local_business, support, education
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name required"})
		return
	}
	if req.Privacy != "public" && req.Privacy != "private" {
		req.Privacy = "public"
	}
	validCategories := map[string]bool{"general": true, "hobby": true, "sports": true, "professional": true, "local_business": true, "support": true, "education": true}
	if !validCategories[req.Category] {
		req.Category = "general"
	}

	ctx := c.Request.Context()
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction failed"})
		return
	}
	defer tx.Rollback(ctx)

	groupType := "social"
	if req.Privacy == "private" {
		groupType = "private_social"
	}

	var groupID uuid.UUID
	var createdAt time.Time
	err = tx.QueryRow(ctx, `
		INSERT INTO groups (name, description, type, privacy, is_encrypted, member_count, key_version, category)
		VALUES ($1, $2, $3, $4, FALSE, 1, 0, $5)
		RETURNING id, created_at
	`, req.Name, req.Description, groupType, req.Privacy, req.Category).Scan(&groupID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create group"})
		return
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'owner')
	`, groupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add owner"})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"group": gin.H{
		"id": groupID, "name": req.Name, "description": req.Description,
		"type": groupType, "privacy": req.Privacy, "category": req.Category, "is_encrypted": false,
		"member_count": 1, "key_version": 0, "created_at": createdAt,
	}})
}

// ── Public Cluster Endpoints ─────────────────────────────────────────────

// ListPublicClusters returns geo-fenced clusters near the user
func (h *CapsuleHandler) ListPublicClusters(c *gin.Context) {
	lat := c.Query("lat")
	lng := c.Query("long")
	if lat == "" || lng == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long required"})
		return
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT id, name, description, type, privacy, radius_meters,
		       COALESCE(avatar_url, '') AS avatar_url,
		       member_count, is_active, is_encrypted,
		       COALESCE(settings::text, '{}') AS settings,
		       key_version, COALESCE(category, 'general') AS category, created_at
		FROM groups
		WHERE type IN ('geo', 'public_geo', 'neighborhood') AND is_active = TRUE
		  AND ST_DWithin(location_center, ST_SetSRID(ST_MakePoint($1::float, $2::float), 4326)::geography, 50000)
		ORDER BY member_count DESC
		LIMIT 50
	`, lng, lat)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch clusters"})
		return
	}
	defer rows.Close()

	var clusters []gin.H
	for rows.Next() {
		var id uuid.UUID
		var name, desc, typ, privacy, avatarURL, settings, category string
		var radius, memberCount, keyVersion int
		var isActive, isEncrypted bool
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &desc, &typ, &privacy, &radius,
			&avatarURL, &memberCount, &isActive, &isEncrypted, &settings, &keyVersion, &category, &createdAt); err != nil {
			continue
		}
		clusters = append(clusters, gin.H{
			"id": id, "name": name, "description": desc, "type": typ,
			"privacy": privacy, "radius_meters": radius, "avatar_url": avatarURL,
			"member_count": memberCount, "is_encrypted": isEncrypted,
			"settings": settings, "key_version": keyVersion, "category": category, "created_at": createdAt,
		})
	}
	if clusters == nil {
		clusters = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"clusters": clusters})
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

// JoinGroup adds the authenticated user to a public, non-encrypted group
func (h *CapsuleHandler) JoinGroup(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group id"})
		return
	}

	ctx := c.Request.Context()

	// Verify group exists, is public, and not encrypted
	var privacy string
	var isEncrypted bool
	err = h.pool.QueryRow(ctx, `SELECT privacy, is_encrypted FROM groups WHERE id = $1 AND is_active = TRUE`, groupID).Scan(&privacy, &isEncrypted)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}
	if isEncrypted {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot join encrypted groups directly"})
		return
	}
	if privacy != "public" {
		c.JSON(http.StatusForbidden, gin.H{"error": "this group requires an invitation"})
		return
	}

	// Check if already a member
	var exists bool
	h.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)`, groupID, userID).Scan(&exists)
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "already a member"})
		return
	}

	// Add member and increment count
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction failed"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'member')`, groupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to join group"})
		return
	}
	_, err = tx.Exec(ctx, `UPDATE groups SET member_count = member_count + 1 WHERE id = $1`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update count"})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "joined group"})
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

// PostCapsuleEntry stores a new encrypted entry (chat/forum/doc)
// The server stores the blob as-is — NO parsing, NO sanitizing
func (h *CapsuleHandler) PostCapsuleEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	ctx := c.Request.Context()

	// Verify membership
	var memberRole string
	err = h.pool.QueryRow(ctx, `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&memberRole)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member"})
		return
	}

	var req struct {
		IV               string  `json:"iv"`
		EncryptedPayload string  `json:"encrypted_payload"`
		DataType         string  `json:"data_type"`
		ReplyToID        *string `json:"reply_to_id"`
		KeyVersion       int     `json:"key_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.IV == "" || req.EncryptedPayload == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "iv and encrypted_payload required"})
		return
	}

	var replyTo *uuid.UUID
	if req.ReplyToID != nil {
		parsed, parseErr := uuid.Parse(*req.ReplyToID)
		if parseErr == nil {
			replyTo = &parsed
		}
	}

	var entryID uuid.UUID
	var createdAt time.Time
	err = h.pool.QueryRow(ctx, `
		INSERT INTO capsule_entries (group_id, author_id, iv, encrypted_payload, data_type, reply_to_id, key_version)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, created_at
	`, groupID, userID, req.IV, req.EncryptedPayload, req.DataType, replyTo, req.KeyVersion).Scan(&entryID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store entry"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"entry": gin.H{
		"id": entryID, "group_id": groupID, "author_id": userID,
		"data_type": req.DataType, "key_version": req.KeyVersion,
		"created_at": createdAt,
	}})
}

// GetCapsuleEntries returns encrypted entries for a capsule (paginated)
func (h *CapsuleHandler) GetCapsuleEntries(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	ctx := c.Request.Context()

	// Verify membership
	var exists bool
	h.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)
	`, groupID, userID).Scan(&exists)
	if !exists {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member"})
		return
	}

	dataType := c.Query("type")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	query := `
		SELECT ce.id, ce.group_id, ce.author_id, ce.iv, ce.encrypted_payload,
		       ce.data_type, ce.reply_to_id, ce.key_version, ce.created_at,
		       p.handle AS author_handle,
		       COALESCE(p.display_name, '') AS author_display_name,
		       COALESCE(p.avatar_url, '') AS author_avatar_url
		FROM capsule_entries ce
		JOIN profiles p ON p.id = ce.author_id
		WHERE ce.group_id = $1 AND ce.is_deleted = FALSE
	`
	var argIdx int = 2
	var args []any = []any{groupID}
	if dataType != "" {
		query += fmt.Sprintf(` AND ce.data_type = $%d`, argIdx)
		args = append(args, dataType)
		argIdx++
	}

	query += fmt.Sprintf(` ORDER BY ce.created_at DESC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch entries"})
		return
	}
	defer rows.Close()

	var entries []gin.H
	for rows.Next() {
		var id, gid, aid uuid.UUID
		var iv, payload, dt, handle, displayName, avatarURL string
		var replyTo *uuid.UUID
		var kv int
		var cat time.Time
		if err := rows.Scan(&id, &gid, &aid, &iv, &payload, &dt, &replyTo, &kv, &cat,
			&handle, &displayName, &avatarURL); err != nil {
			continue
		}
		entries = append(entries, gin.H{
			"id": id, "group_id": gid, "author_id": aid,
			"iv": iv, "encrypted_payload": payload,
			"data_type": dt, "reply_to_id": replyTo, "key_version": kv,
			"created_at": cat, "author_handle": handle,
			"author_display_name": displayName, "author_avatar_url": avatarURL,
		})
	}
	if entries == nil {
		entries = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"entries": entries})
}

// InviteToCapsule adds a member with their encrypted copy of the group key
func (h *CapsuleHandler) InviteToCapsule(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	ctx := c.Request.Context()

	// Only owner/admin can invite
	var inviterRole string
	err = h.pool.QueryRow(ctx, `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&inviterRole)
	if err != nil || (inviterRole != "owner" && inviterRole != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only owner or admin can invite"})
		return
	}

	var req struct {
		InviteeUserID     string `json:"invitee_user_id"`
		EncryptedGroupKey string `json:"encrypted_group_key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	inviteeID, err := uuid.Parse(req.InviteeUserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitee_user_id"})
		return
	}

	var keyVersion int
	h.pool.QueryRow(ctx, `SELECT key_version FROM groups WHERE id = $1`, groupID).Scan(&keyVersion)

	_, err = h.pool.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role, encrypted_group_key, key_version)
		VALUES ($1, $2, 'member', $3, $4)
		ON CONFLICT (group_id, user_id) DO UPDATE SET encrypted_group_key = $3, key_version = $4
	`, groupID, inviteeID, req.EncryptedGroupKey, keyVersion)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to invite"})
		return
	}

	// Also store in capsule_keys
	_, _ = h.pool.Exec(ctx, `
		INSERT INTO capsule_keys (user_id, group_id, encrypted_key_blob, key_version)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, group_id) DO UPDATE SET encrypted_key_blob = $3, key_version = $4
	`, inviteeID, groupID, req.EncryptedGroupKey, keyVersion)

	// Bump member count
	h.pool.Exec(ctx, `
		UPDATE groups SET member_count = (SELECT COUNT(*) FROM group_members WHERE group_id = $1) WHERE id = $1
	`, groupID)

	c.JSON(http.StatusOK, gin.H{"status": "invited"})
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

// ReportCapsuleEntry stores a member's report of an encrypted entry.
// The client voluntarily decrypts the payload to provide plaintext evidence.
func (h *CapsuleHandler) ReportCapsuleEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}
	entryID, err := uuid.Parse(c.Param("entryId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry ID"})
		return
	}

	ctx := c.Request.Context()

	// Verify membership
	var isMember bool
	h.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)`,
		groupID, userID,
	).Scan(&isMember)
	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member"})
		return
	}

	var req struct {
		Reason          string  `json:"reason" binding:"required"`
		DecryptedSample *string `json:"decrypted_sample"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason required"})
		return
	}

	// Prevent duplicate reports from the same user for the same entry
	var alreadyReported bool
	h.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM capsule_reports WHERE reporter_id = $1 AND entry_id = $2)`,
		userID, entryID,
	).Scan(&alreadyReported)
	if alreadyReported {
		c.JSON(http.StatusConflict, gin.H{"error": "already reported"})
		return
	}

	_, err = h.pool.Exec(ctx, `
		INSERT INTO capsule_reports (reporter_id, capsule_id, entry_id, decrypted_sample, reason)
		VALUES ($1, $2, $3, $4, $5)
	`, userID, groupID, entryID, req.DecryptedSample, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store report"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Report submitted"})
}
