// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"context"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

type BoardHandler struct {
	pool                *pgxpool.Pool
	contentFilter       *services.ContentFilter
	moderationService   *services.ModerationService
	contentModerator    *services.ContentModerator
	notificationService *services.NotificationService
}

func NewBoardHandler(pool *pgxpool.Pool, opts ...interface{}) *BoardHandler {
	h := &BoardHandler{pool: pool}
	for _, opt := range opts {
		switch v := opt.(type) {
		case *services.ContentFilter:
			h.contentFilter = v
		case *services.ModerationService:
			h.moderationService = v
		case *services.ContentModerator:
			h.contentModerator = v
		case *services.NotificationService:
			h.notificationService = v
		}
	}
	return h
}

// ── List nearby board entries ─────────────────────────────────────────────

func (h *BoardHandler) ListNearby(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	latStr := c.Query("lat")
	longStr := c.Query("long")
	radiusStr := c.DefaultQuery("radius", "5000")
	topic := c.Query("topic")
	sort := c.DefaultQuery("sort", "new")

	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat required"})
		return
	}
	long, err := strconv.ParseFloat(longStr, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "long required"})
		return
	}
	radius, _ := strconv.Atoi(radiusStr)
	if radius <= 0 || radius > 50000 {
		radius = 5000
	}

	query := `
		SELECT e.id, e.body, COALESCE(e.image_url, ''), e.topic,
		       e.lat, e.long, e.upvotes, e.reply_count, e.is_pinned, e.created_at,
		       pr.handle, pr.display_name, COALESCE(pr.avatar_url, ''),
		       EXISTS(SELECT 1 FROM board_votes bv WHERE bv.user_id = $4 AND bv.entry_id = e.id) AS has_voted
		FROM board_entries e
		JOIN profiles pr ON e.author_id = pr.id
		WHERE e.is_active = TRUE
		  AND ST_DWithin(e.location, ST_SetSRID(ST_Point($2, $1), 4326)::geography, $3)
	`
	args := []any{lat, long, radius, userID}
	argIdx := 5

	if topic != "" {
		query += ` AND e.topic = $` + strconv.Itoa(argIdx)
		args = append(args, topic)
		argIdx++
	}

	orderClause := "e.is_pinned DESC, e.created_at DESC"
	switch sort {
	case "top":
		orderClause = "e.is_pinned DESC, e.upvotes DESC, e.reply_count DESC, e.created_at DESC"
	case "hot":
		orderClause = "e.is_pinned DESC, (e.upvotes * 2 + e.reply_count) DESC, e.created_at DESC"
	}

	query += ` ORDER BY ` + orderClause + ` LIMIT 100`

	rows, err := h.pool.Query(c.Request.Context(), query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch board entries"})
		return
	}
	defer rows.Close()

	var entries []gin.H
	for rows.Next() {
		var id uuid.UUID
		var body, imageURL, tp, handle, displayName, avatarURL string
		var eLat, eLong float64
		var upvotes, replyCount int
		var isPinned, hasVoted bool
		var createdAt time.Time
		if err := rows.Scan(&id, &body, &imageURL, &tp,
			&eLat, &eLong, &upvotes, &replyCount, &isPinned, &createdAt,
			&handle, &displayName, &avatarURL, &hasVoted); err != nil {
			continue
		}
		entries = append(entries, gin.H{
			"id": id, "body": body, "image_url": imageURL, "topic": tp,
			"lat": eLat, "long": eLong, "upvotes": upvotes, "reply_count": replyCount,
			"is_pinned": isPinned, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
			"has_voted": hasVoted,
		})
	}
	if entries == nil {
		entries = []gin.H{}
	}

	// Check if the current user is a neighborhood admin for any nearby group
	isAdmin := h.isNeighborhoodAdmin(c, userID, lat, long)

	c.JSON(http.StatusOK, gin.H{"entries": entries, "is_neighborhood_admin": isAdmin})
}

// ── Create board entry ────────────────────────────────────────────────────

func (h *BoardHandler) CreateEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Body     string  `json:"body" binding:"required,max=1000"`
		ImageURL *string `json:"image_url"`
		Topic    string  `json:"topic"`
		Lat      float64 `json:"lat" binding:"required"`
		Long     float64 `json:"long" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Topic == "" {
		req.Topic = "community"
	}

	// Layer 0: Hard blocklist check (instant rejection)
	if h.contentFilter != nil {
		result := h.contentFilter.CheckContent(req.Body)
		if result.Blocked {
			go h.contentFilter.RecordStrike(c.Request.Context(), userID, result.Category, req.Body)
			c.JSON(http.StatusForbidden, gin.H{
				"error":    "Content violates community guidelines",
				"category": result.Category,
			})
			return
		}
	}

	// Fuzz coordinates to ~1.1 km precision — same as beacons.
	fLat := math.Round(req.Lat*100) / 100
	fLong := math.Round(req.Long*100) / 100

	var id uuid.UUID
	var createdAt time.Time
	err = h.pool.QueryRow(c.Request.Context(), `
		INSERT INTO board_entries (author_id, body, image_url, topic, lat, long)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, created_at
	`, userID, req.Body, req.ImageURL, req.Topic, fLat, fLong).Scan(&id, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create entry"})
		return
	}

	// Layer 1: AI moderation (async — doesn't block the response)
	go h.aiModerateEntry(id, req.Body, userID)

	// Fetch author info for response
	var handle, displayName, avatarURL string
	_ = h.pool.QueryRow(c.Request.Context(),
		`SELECT handle, display_name, COALESCE(avatar_url, '') FROM profiles WHERE id = $1`, userID,
	).Scan(&handle, &displayName, &avatarURL)

	c.JSON(http.StatusCreated, gin.H{"entry": gin.H{
		"id": id, "body": req.Body, "image_url": req.ImageURL, "topic": req.Topic,
		"lat": fLat, "long": fLong, "upvotes": 0, "reply_count": 0,
		"is_pinned": false, "created_at": createdAt,
		"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		"has_voted": false,
	}})
}

// ── Get single entry with replies ─────────────────────────────────────────

func (h *BoardHandler) GetEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	entryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry id"})
		return
	}

	// Fetch entry
	var body, imageURL, topic, handle, displayName, avatarURL string
	var eLat, eLong float64
	var upvotes, replyCount int
	var isPinned, hasVoted bool
	var createdAt time.Time
	err = h.pool.QueryRow(c.Request.Context(), `
		SELECT e.body, COALESCE(e.image_url, ''), e.topic,
		       e.lat, e.long, e.upvotes, e.reply_count, e.is_pinned, e.created_at,
		       pr.handle, pr.display_name, COALESCE(pr.avatar_url, ''),
		       EXISTS(SELECT 1 FROM board_votes bv WHERE bv.user_id = $2 AND bv.entry_id = e.id) AS has_voted
		FROM board_entries e
		JOIN profiles pr ON e.author_id = pr.id
		WHERE e.id = $1 AND e.is_active = TRUE
	`, entryID, userID).Scan(&body, &imageURL, &topic,
		&eLat, &eLong, &upvotes, &replyCount, &isPinned, &createdAt,
		&handle, &displayName, &avatarURL, &hasVoted)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "entry not found"})
		return
	}

	// Fetch replies
	replyRows, err := h.pool.Query(c.Request.Context(), `
		SELECT r.id, r.body, r.upvotes, r.created_at,
		       pr.handle, pr.display_name, COALESCE(pr.avatar_url, ''),
		       EXISTS(SELECT 1 FROM board_votes bv WHERE bv.user_id = $2 AND bv.reply_id = r.id) AS has_voted
		FROM board_replies r
		JOIN profiles pr ON r.author_id = pr.id
		WHERE r.entry_id = $1 AND r.is_active = TRUE
		ORDER BY r.created_at ASC
	`, entryID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch replies"})
		return
	}
	defer replyRows.Close()

	var replies []gin.H
	for replyRows.Next() {
		var rID uuid.UUID
		var rBody, rHandle, rDisplayName, rAvatarURL string
		var rUpvotes int
		var rCreatedAt time.Time
		var rHasVoted bool
		if err := replyRows.Scan(&rID, &rBody, &rUpvotes, &rCreatedAt,
			&rHandle, &rDisplayName, &rAvatarURL, &rHasVoted); err != nil {
			continue
		}
		replies = append(replies, gin.H{
			"id": rID, "body": rBody, "upvotes": rUpvotes, "created_at": rCreatedAt,
			"author_handle": rHandle, "author_display_name": rDisplayName, "author_avatar_url": rAvatarURL,
			"has_voted": rHasVoted,
		})
	}
	if replies == nil {
		replies = []gin.H{}
	}

	// Check admin status for this entry
	isAdmin := h.isNeighborhoodAdmin(c, userID, eLat, eLong)

	c.JSON(http.StatusOK, gin.H{
		"entry": gin.H{
			"id": entryID, "body": body, "image_url": imageURL, "topic": topic,
			"lat": eLat, "long": eLong, "upvotes": upvotes, "reply_count": replyCount,
			"is_pinned": isPinned, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
			"has_voted": hasVoted,
		},
		"replies":               replies,
		"is_neighborhood_admin": isAdmin,
	})
}

// ── Reply to entry ────────────────────────────────────────────────────────

func (h *BoardHandler) CreateReply(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	entryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry id"})
		return
	}

	var req struct {
		Body string `json:"body" binding:"required,max=500"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Layer 0: Hard blocklist check
	if h.contentFilter != nil {
		result := h.contentFilter.CheckContent(req.Body)
		if result.Blocked {
			go h.contentFilter.RecordStrike(c.Request.Context(), userID, result.Category, req.Body)
			c.JSON(http.StatusForbidden, gin.H{
				"error":    "Content violates community guidelines",
				"category": result.Category,
			})
			return
		}
	}

	var replyID uuid.UUID
	var createdAt time.Time
	err = h.pool.QueryRow(c.Request.Context(), `
		INSERT INTO board_replies (entry_id, author_id, body)
		VALUES ($1, $2, $3)
		RETURNING id, created_at
	`, entryID, userID, req.Body).Scan(&replyID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create reply"})
		return
	}

	// Bump reply count
	_, _ = h.pool.Exec(c.Request.Context(),
		`UPDATE board_entries SET reply_count = reply_count + 1, updated_at = NOW() WHERE id = $1`, entryID)

	// Layer 1: AI moderation (async)
	go h.aiModerateReply(replyID, req.Body, userID)

	var handle, displayName, avatarURL string
	_ = h.pool.QueryRow(c.Request.Context(),
		`SELECT handle, display_name, COALESCE(avatar_url, '') FROM profiles WHERE id = $1`, userID,
	).Scan(&handle, &displayName, &avatarURL)

	c.JSON(http.StatusCreated, gin.H{"reply": gin.H{
		"id": replyID, "body": req.Body, "upvotes": 0, "created_at": createdAt,
		"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		"has_voted": false,
	}})
}

// ── Upvote entry or reply (toggle) ────────────────────────────────────────

func (h *BoardHandler) ToggleVote(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		EntryID *string `json:"entry_id"`
		ReplyID *string `json:"reply_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()

	if req.EntryID != nil && *req.EntryID != "" {
		entryID, err := uuid.Parse(*req.EntryID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry_id"})
			return
		}
		// Try delete (un-vote); if nothing deleted, insert (vote)
		tag, err := h.pool.Exec(ctx,
			`DELETE FROM board_votes WHERE user_id = $1 AND entry_id = $2`, userID, entryID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vote failed"})
			return
		}
		if tag.RowsAffected() > 0 {
			_, _ = h.pool.Exec(ctx,
				`UPDATE board_entries SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = $1`, entryID)
			c.JSON(http.StatusOK, gin.H{"voted": false})
			return
		}
		_, err = h.pool.Exec(ctx,
			`INSERT INTO board_votes (user_id, entry_id) VALUES ($1, $2)`, userID, entryID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vote failed"})
			return
		}
		_, _ = h.pool.Exec(ctx,
			`UPDATE board_entries SET upvotes = upvotes + 1 WHERE id = $1`, entryID)
		c.JSON(http.StatusOK, gin.H{"voted": true})
		return
	}

	if req.ReplyID != nil && *req.ReplyID != "" {
		replyID, err := uuid.Parse(*req.ReplyID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reply_id"})
			return
		}
		tag, err := h.pool.Exec(ctx,
			`DELETE FROM board_votes WHERE user_id = $1 AND reply_id = $2`, userID, replyID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vote failed"})
			return
		}
		if tag.RowsAffected() > 0 {
			_, _ = h.pool.Exec(ctx,
				`UPDATE board_replies SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = $1`, replyID)
			c.JSON(http.StatusOK, gin.H{"voted": false})
			return
		}
		_, err = h.pool.Exec(ctx,
			`INSERT INTO board_votes (user_id, reply_id) VALUES ($1, $2)`, userID, replyID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vote failed"})
			return
		}
		_, _ = h.pool.Exec(ctx,
			`UPDATE board_replies SET upvotes = upvotes + 1 WHERE id = $1`, replyID)
		c.JSON(http.StatusOK, gin.H{"voted": true})
		return
	}

	c.JSON(http.StatusBadRequest, gin.H{"error": "entry_id or reply_id required"})
}

// ── Admin: Remove board entry ─────────────────────────────────────────────
// Neighborhood admins can remove entries in their neighborhood.
// POST /board/:id/remove

func (h *BoardHandler) RemoveEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	entryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry id"})
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required,min=5,max=500"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Check if the user is a neighborhood admin for the entry's location
	var entryLat, entryLong float64
	err = h.pool.QueryRow(ctx,
		`SELECT lat, long FROM board_entries WHERE id = $1 AND is_active = TRUE`, entryID,
	).Scan(&entryLat, &entryLong)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "entry not found"})
		return
	}

	// Verify caller is neighborhood admin or app admin
	if !h.isNeighborhoodAdmin(c, userID, entryLat, entryLong) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only neighborhood admins can remove content"})
		return
	}

	// Soft-remove the entry
	_, err = h.pool.Exec(ctx, `
		UPDATE board_entries
		SET is_active = FALSE, removed_by = $1, removed_reason = $2, removed_at = NOW(), updated_at = NOW()
		WHERE id = $3
	`, userID, req.Reason, entryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove entry"})
		return
	}

	// Audit trail
	_, _ = h.pool.Exec(ctx, `
		INSERT INTO board_moderation_actions (entry_id, moderator_id, action, reason)
		VALUES ($1, $2, 'remove', $3)
	`, entryID, userID, req.Reason)

	c.JSON(http.StatusOK, gin.H{"message": "entry removed", "entry_id": entryID})
}

// ── Flag board content ────────────────────────────────────────────────────
// Any user can flag board content for review.
// POST /board/:id/flag

func (h *BoardHandler) FlagEntry(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	entryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid entry id"})
		return
	}

	var req struct {
		Reason  string  `json:"reason" binding:"required,min=3,max=500"`
		ReplyID *string `json:"reply_id"` // optional: flag a specific reply
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()

	if req.ReplyID != nil && *req.ReplyID != "" {
		replyUUID, err := uuid.Parse(*req.ReplyID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reply_id"})
			return
		}
		_, _ = h.pool.Exec(ctx, `
			INSERT INTO board_moderation_actions (reply_id, moderator_id, action, reason)
			VALUES ($1, $2, 'flag', $3)
		`, replyUUID, userID, req.Reason)
	} else {
		_, _ = h.pool.Exec(ctx, `
			INSERT INTO board_moderation_actions (entry_id, moderator_id, action, reason)
			VALUES ($1, $2, 'flag', $3)
		`, entryID, userID, req.Reason)
	}

	c.JSON(http.StatusOK, gin.H{"message": "content flagged for review"})
}

// ── Helpers ───────────────────────────────────────────────────────────────

// isNeighborhoodAdmin checks if a user is an admin/owner of any neighborhood
// group that covers the given coordinates.
func (h *BoardHandler) isNeighborhoodAdmin(c *gin.Context, userID uuid.UUID, lat, long float64) bool {
	var exists bool
	_ = h.pool.QueryRow(c.Request.Context(), `
		SELECT EXISTS(
			SELECT 1
			FROM neighborhood_seeds ns
			JOIN group_members gm ON gm.group_id = ns.group_id
			WHERE gm.user_id = $1
			  AND gm.role IN ('owner', 'admin')
			  AND ST_DWithin(
					ST_SetSRID(ST_Point($3, $2), 4326)::geography,
					ST_SetSRID(ST_Point(ns.lng, ns.lat), 4326)::geography,
					ns.radius_meters
			  )
		)
	`, userID, lat, long).Scan(&exists)
	return exists
}

// aiModerateEntry runs AI moderation on a board entry asynchronously using the
// shared content moderation cascade (local AI → SightEngine → fail-open).
// If flagged, it sets ai_flagged = true and hides the entry.
func (h *BoardHandler) aiModerateEntry(entryID uuid.UUID, body string, authorID uuid.UUID) {
	if h.contentModerator == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	result := h.contentModerator.ModerateText(ctx, "text", body)
	decision := result.Action
	reason := result.Reason
	engine := result.Engine
	scores := result.Scores

	// Always log AI decision for audit
	if h.moderationService != nil {
		rawScore, _ := json.Marshal(scores)
		h.moderationService.LogAIDecision(ctx, "board_entry", entryID, authorID, body, scores, rawScore, decision, reason, engine, nil)
	}

	if decision == "clean" || decision == "nsfw" {
		// NSFW board entries stay visible but could be blurred (future)
		return
	}

	log.Printf("[BoardAI] entry %s flagged by %s: %s", entryID, engine, reason)

	_, _ = h.pool.Exec(ctx, `
		UPDATE board_entries
		SET ai_flagged = TRUE, ai_flag_reason = $1, is_active = FALSE,
		    removed_reason = 'AI auto-moderation: ' || $1, removed_at = NOW(), updated_at = NOW()
		WHERE id = $2
	`, reason, entryID)

	_, _ = h.pool.Exec(ctx, `
		INSERT INTO board_moderation_actions (entry_id, moderator_id, action, reason, ai_engine, ai_reason)
		VALUES ($1, $2, 'remove', $3, $4, $3)
	`, entryID, authorID, "AI flagged: "+reason, engine)

	// Notify the author that their content was removed so they can appeal
	if h.notificationService != nil {
		_ = h.notificationService.NotifyContentRemoved(ctx, authorID.String(), entryID.String())
	}
}

// aiModerateReply runs AI moderation on a board reply asynchronously using the
// shared content moderation cascade.
func (h *BoardHandler) aiModerateReply(replyID uuid.UUID, body string, authorID uuid.UUID) {
	if h.contentModerator == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	result := h.contentModerator.ModerateText(ctx, "text", body)
	decision := result.Action
	reason := result.Reason
	engine := result.Engine
	scores := result.Scores

	if h.moderationService != nil {
		rawScore, _ := json.Marshal(scores)
		h.moderationService.LogAIDecision(ctx, "board_reply", replyID, authorID, body, scores, rawScore, decision, reason, engine, nil)
	}

	if decision == "clean" || decision == "nsfw" {
		return
	}

	log.Printf("[BoardAI] reply %s flagged by %s: %s", replyID, engine, reason)

	_, _ = h.pool.Exec(ctx, `
		UPDATE board_replies
		SET ai_flagged = TRUE, ai_flag_reason = $1, is_active = FALSE,
		    removed_reason = 'AI auto-moderation: ' || $1, removed_at = NOW()
		WHERE id = $2
	`, reason, replyID)

	_, _ = h.pool.Exec(ctx, `
		INSERT INTO board_moderation_actions (reply_id, moderator_id, action, reason, ai_engine, ai_reason)
		VALUES ($1, $2, 'remove', $3, $4, $3)
	`, replyID, authorID, "AI flagged: "+reason, engine)

	// Notify the author that their reply was removed so they can appeal
	if h.notificationService != nil {
		_ = h.notificationService.NotifyContentRemoved(ctx, authorID.String(), replyID.String())
	}
}
