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
)

// ListNeighborhoods returns neighborhood seeds with group and activity metadata.
func (h *AdminHandler) ListNeighborhoods(c *gin.Context) {
	ctx := c.Request.Context()

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	search := strings.TrimSpace(c.Query("search"))
	zip := strings.TrimSpace(c.Query("zip"))
	state := strings.TrimSpace(c.Query("state"))
	sortBy := strings.TrimSpace(c.DefaultQuery("sort", "name"))
	order := strings.ToLower(strings.TrimSpace(c.DefaultQuery("order", "asc")))

	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if order != "desc" {
		order = "asc"
	}

	sortColumn := "ns.name"
	switch sortBy {
	case "zip":
		sortColumn = "ns.zip_code"
	case "state":
		sortColumn = "ns.state"
	case "members":
		sortColumn = "g.member_count"
	case "created":
		sortColumn = "ns.created_at"
	}

	base := `
		FROM neighborhood_seeds ns
		LEFT JOIN groups g ON g.id = ns.group_id
		WHERE 1=1
	`
	args := []any{}
	argIdx := 1

	if search != "" {
		base += fmt.Sprintf(" AND (ns.name ILIKE $%d OR ns.city ILIKE $%d OR ns.state ILIKE $%d OR ns.zip_code ILIKE $%d OR g.name ILIKE $%d)", argIdx, argIdx, argIdx, argIdx, argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if zip != "" {
		base += fmt.Sprintf(" AND ns.zip_code ILIKE $%d", argIdx)
		args = append(args, "%"+zip+"%")
		argIdx++
	}
	if state != "" {
		base += fmt.Sprintf(" AND ns.state ILIKE $%d", argIdx)
		args = append(args, "%"+state+"%")
		argIdx++
	}

	var total int
	if err := h.pool.QueryRow(ctx, "SELECT COUNT(*) "+base, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count neighborhoods"})
		return
	}

	query := `
		SELECT
			ns.id,
			ns.name,
			ns.city,
			ns.state,
			COALESCE(ns.zip_code, ''),
			ns.country,
			ns.lat,
			ns.lng,
			ns.radius_meters,
			ns.created_at,
			ns.group_id,
			COALESCE(g.name, ''),
			COALESCE(g.member_count, 0),
			COALESCE((
				SELECT COUNT(*) FROM group_members gm
				WHERE gm.group_id = ns.group_id AND gm.role IN ('owner','admin')
			), 0) AS admin_count,
			COALESCE((
				SELECT COUNT(*) FROM board_entries be
				WHERE be.is_active = TRUE
				  AND ST_DWithin(be.location, ST_SetSRID(ST_MakePoint(ns.lng, ns.lat), 4326)::geography, ns.radius_meters)
			), 0) AS board_post_count,
			COALESCE((
				SELECT COUNT(*) FROM group_posts gp
				WHERE gp.group_id = ns.group_id AND gp.is_deleted = FALSE
			), 0) AS group_post_count
	` + base + fmt.Sprintf(" ORDER BY %s %s, ns.created_at DESC LIMIT $%d OFFSET $%d", sortColumn, order, argIdx, argIdx+1)

	args = append(args, limit, offset)
	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list neighborhoods"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id uuid.UUID
		var name, city, state, zipCode, country string
		var lat, lng float64
		var radiusMeters, memberCount, adminCount, boardCount, groupPostCount int
		var createdAt time.Time
		var groupID *uuid.UUID
		var groupName string

		if err := rows.Scan(
			&id, &name, &city, &state, &zipCode, &country,
			&lat, &lng, &radiusMeters, &createdAt,
			&groupID, &groupName, &memberCount, &adminCount, &boardCount, &groupPostCount,
		); err != nil {
			continue
		}

		items = append(items, gin.H{
			"id":               id,
			"name":             name,
			"city":             city,
			"state":            state,
			"zip_code":         zipCode,
			"country":          country,
			"lat":              lat,
			"lng":              lng,
			"radius_meters":    radiusMeters,
			"created_at":       createdAt,
			"group_id":         groupID,
			"group_name":       groupName,
			"member_count":     memberCount,
			"admin_count":      adminCount,
			"board_post_count": boardCount,
			"group_post_count": groupPostCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"neighborhoods": items,
		"total":         total,
		"limit":         limit,
		"offset":        offset,
	})
}

// SetNeighborhoodAdmin assigns or removes neighborhood admins by role on group_members.
func (h *AdminHandler) SetNeighborhoodAdmin(c *gin.Context) {
	ctx := c.Request.Context()
	seedID := c.Param("id")

	var req struct {
		UserID string `json:"user_id" binding:"required"`
		Action string `json:"action" binding:"required,oneof=assign remove"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var groupID uuid.UUID
	if err := h.pool.QueryRow(ctx, `SELECT group_id FROM neighborhood_seeds WHERE id = $1::uuid`, seedID).Scan(&groupID); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "neighborhood or group not found"})
		return
	}

	if req.Action == "assign" {
		_, err := h.pool.Exec(ctx, `
			INSERT INTO group_members (group_id, user_id, role)
			VALUES ($1, $2::uuid, 'admin')
			ON CONFLICT (group_id, user_id) DO UPDATE SET role = 'admin'
		`, groupID, req.UserID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to assign admin"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "admin assigned"})
		return
	}

	_, err := h.pool.Exec(ctx, `
		UPDATE group_members
		SET role = 'member'
		WHERE group_id = $1 AND user_id = $2::uuid AND role = 'admin'
	`, groupID, req.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove admin"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "admin removed"})
}

// ListNeighborhoodAdmins returns current owner/admin members for a neighborhood group.
func (h *AdminHandler) ListNeighborhoodAdmins(c *gin.Context) {
	ctx := c.Request.Context()
	seedID := c.Param("id")

	var groupID uuid.UUID
	if err := h.pool.QueryRow(ctx, `SELECT group_id FROM neighborhood_seeds WHERE id = $1::uuid`, seedID).Scan(&groupID); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "neighborhood or group not found"})
		return
	}

	rows, err := h.pool.Query(ctx, `
		SELECT gm.user_id, gm.role, gm.joined_at,
		       COALESCE(p.handle, ''), COALESCE(p.display_name, ''), COALESCE(p.avatar_url, '')
		FROM group_members gm
		JOIN profiles p ON p.id = gm.user_id
		WHERE gm.group_id = $1 AND gm.role IN ('owner', 'admin')
		ORDER BY CASE gm.role WHEN 'owner' THEN 0 ELSE 1 END, gm.joined_at ASC
	`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list neighborhood admins"})
		return
	}
	defer rows.Close()

	admins := make([]gin.H, 0)
	for rows.Next() {
		var userID uuid.UUID
		var role, handle, displayName, avatarURL string
		var joinedAt time.Time
		if err := rows.Scan(&userID, &role, &joinedAt, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		admins = append(admins, gin.H{
			"user_id":      userID,
			"role":         role,
			"joined_at":    joinedAt,
			"handle":       handle,
			"display_name": displayName,
			"avatar_url":   avatarURL,
		})
	}

	c.JSON(http.StatusOK, gin.H{"admins": admins})
}

// ListNeighborhoodBoardEntries lists board content inside a neighborhood radius for moderation.
func (h *AdminHandler) ListNeighborhoodBoardEntries(c *gin.Context) {
	ctx := c.Request.Context()
	seedID := c.Param("id")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	search := strings.TrimSpace(c.Query("search"))
	active := strings.TrimSpace(c.Query("active"))

	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}

	var lat, lng float64
	var radius int
	if err := h.pool.QueryRow(ctx, `SELECT lat, lng, radius_meters FROM neighborhood_seeds WHERE id = $1::uuid`, seedID).Scan(&lat, &lng, &radius); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "neighborhood not found"})
		return
	}

	base := `
		FROM board_entries be
		JOIN profiles p ON p.id = be.author_id
		WHERE ST_DWithin(be.location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
	`
	args := []any{lng, lat, radius}
	argIdx := 4

	if search != "" {
		base += fmt.Sprintf(" AND be.body ILIKE $%d", argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if active == "true" || active == "false" {
		base += fmt.Sprintf(" AND be.is_active = $%d", argIdx)
		args = append(args, active == "true")
		argIdx++
	}

	var total int
	if err := h.pool.QueryRow(ctx, "SELECT COUNT(*) "+base, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count board entries"})
		return
	}

	query := `
		SELECT be.id, be.body, be.topic, be.is_active, be.is_pinned, be.upvotes, be.reply_count, be.created_at,
		       p.id, COALESCE(p.handle, ''), COALESCE(p.display_name, '')
	` + base + fmt.Sprintf(" ORDER BY be.is_pinned DESC, be.created_at DESC LIMIT $%d OFFSET $%d", argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list board entries"})
		return
	}
	defer rows.Close()

	entries := make([]gin.H, 0)
	for rows.Next() {
		var id, authorID uuid.UUID
		var body, topic, handle, displayName string
		var isActive, isPinned bool
		var upvotes, replyCount int
		var createdAt time.Time
		if err := rows.Scan(&id, &body, &topic, &isActive, &isPinned, &upvotes, &replyCount, &createdAt, &authorID, &handle, &displayName); err != nil {
			continue
		}
		entries = append(entries, gin.H{
			"id":          id,
			"body":        body,
			"topic":       topic,
			"is_active":   isActive,
			"is_pinned":   isPinned,
			"upvotes":     upvotes,
			"reply_count": replyCount,
			"created_at":  createdAt,
			"author": gin.H{
				"id":           authorID,
				"handle":       handle,
				"display_name": displayName,
			},
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"entries": entries,
		"total":   total,
		"limit":   limit,
		"offset":  offset,
	})
}

func (h *AdminHandler) UpdateNeighborhoodBoardEntry(c *gin.Context) {
	ctx := c.Request.Context()
	entryID := c.Param("entryId")

	var req struct {
		IsActive *bool `json:"is_active"`
		IsPinned *bool `json:"is_pinned"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.IsActive == nil && req.IsPinned == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "is_active or is_pinned is required"})
		return
	}

	sets := make([]string, 0, 2)
	args := make([]any, 0, 3)
	argIdx := 1
	if req.IsActive != nil {
		sets = append(sets, fmt.Sprintf("is_active = $%d", argIdx))
		args = append(args, *req.IsActive)
		argIdx++
	}
	if req.IsPinned != nil {
		sets = append(sets, fmt.Sprintf("is_pinned = $%d", argIdx))
		args = append(args, *req.IsPinned)
		argIdx++
	}
	sets = append(sets, "updated_at = NOW()")
	args = append(args, entryID)

	query := fmt.Sprintf("UPDATE board_entries SET %s WHERE id = $%d::uuid", strings.Join(sets, ", "), argIdx)
	_, err := h.pool.Exec(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update board entry"})
		return
	}

	resp := gin.H{"message": "board entry updated"}
	if req.IsActive != nil {
		resp["is_active"] = *req.IsActive
	}
	if req.IsPinned != nil {
		resp["is_pinned"] = *req.IsPinned
	}

	c.JSON(http.StatusOK, resp)
}
