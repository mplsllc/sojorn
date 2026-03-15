// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SoundsHandler serves the in-house soundbank — trending user sounds and curated
// library tracks. Replaces the former Freesound proxy (audio_handler.go).
//
// Sounds are stored in the `sounds` table and served from R2:
//   - bucket='user'    → sojorn-media/quip-audio/
//   - bucket='library' → sojorn-media/library-audio/
type SoundsHandler struct {
	pool     *pgxpool.Pool
	r2Domain string // public CDN domain for serving audio (e.g. img.sojorn.net)
}

func NewSoundsHandler(pool *pgxpool.Pool, _, _, _, _, r2Domain string) *SoundsHandler {
	return &SoundsHandler{pool: pool, r2Domain: r2Domain}
}

type soundItem struct {
	ID           uuid.UUID  `json:"id"`
	Title        string     `json:"title"`
	Bucket       string     `json:"bucket"`
	DurationMS   *int       `json:"duration_ms"`
	UseCount     int        `json:"use_count"`
	R2Key        string     `json:"r2_key"`
	AudioURL     string     `json:"audio_url"`
	UploaderID   *uuid.UUID `json:"uploader_id,omitempty"`
	SourcePostID *uuid.UUID `json:"source_post_id,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
}

// List returns paginated sounds sorted by use_count DESC.
// Query params:
//
//	bucket = "user" | "library" | "" (both, default)
//	cursor = ISO timestamp of last item's created_at (for next-page fetching)
//	limit  = max rows, default 30, max 100
func (h *SoundsHandler) List(c *gin.Context) {
	ctx := c.Request.Context()

	bucket := c.Query("bucket")
	limit := 30
	if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 && l <= 100 {
		limit = l
	}
	cursor := c.Query("cursor")

	var args []any
	argIdx := 1

	query := `
		SELECT id, title, bucket, duration_ms, use_count, r2_key,
		       uploader_id, source_post_id, created_at
		FROM sounds
		WHERE is_active = true`

	if bucket == "user" || bucket == "library" {
		query += ` AND bucket = $` + strconv.Itoa(argIdx)
		args = append(args, bucket)
		argIdx++
	}
	if cursor != "" {
		query += ` AND created_at < $` + strconv.Itoa(argIdx)
		args = append(args, cursor)
		argIdx++
	}

	query += ` ORDER BY use_count DESC, created_at DESC LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit+1) // +1 to detect whether a next page exists

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch sounds"})
		return
	}
	defer rows.Close()

	var sounds []soundItem
	for rows.Next() {
		var s soundItem
		if err := rows.Scan(
			&s.ID, &s.Title, &s.Bucket, &s.DurationMS, &s.UseCount,
			&s.R2Key, &s.UploaderID, &s.SourcePostID, &s.CreatedAt,
		); err != nil {
			continue
		}
		s.AudioURL = h.audioURL(s.R2Key)
		sounds = append(sounds, s)
	}
	if sounds == nil {
		sounds = []soundItem{}
	}

	var nextCursor *string
	if len(sounds) > limit {
		sounds = sounds[:limit]
		t := sounds[limit-1].CreatedAt.UTC().Format(time.RFC3339Nano)
		nextCursor = &t
	}

	c.JSON(http.StatusOK, gin.H{"sounds": sounds, "next_cursor": nextCursor})
}

// Register creates a user sound record pointing to an already-uploaded R2 key.
// Called when a Quip with original audio is posted and no sound_id is present.
// Body: { title, r2_key, duration_ms?, source_post_id? }
func (h *SoundsHandler) Register(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	ctx := c.Request.Context()

	var req struct {
		Title        string  `json:"title" binding:"required"`
		R2Key        string  `json:"r2_key" binding:"required"`
		DurationMS   *int    `json:"duration_ms"`
		SourcePostID *string `json:"source_post_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title and r2_key are required"})
		return
	}

	var sourcePostID *uuid.UUID
	if req.SourcePostID != nil {
		if id, err := uuid.Parse(*req.SourcePostID); err == nil {
			sourcePostID = &id
		}
	}

	var id uuid.UUID
	err := h.pool.QueryRow(ctx, `
		INSERT INTO sounds (uploader_id, source_post_id, title, r2_key, bucket, duration_ms)
		VALUES ($1, $2, $3, $4, 'user', $5)
		RETURNING id
	`, userID, sourcePostID, req.Title, req.R2Key, req.DurationMS).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register sound"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id})
}

// RecordUse increments use_count on a sound. Called when a user selects a sound
// from the picker for their Quip (before posting).
func (h *SoundsHandler) RecordUse(c *gin.Context) {
	soundID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid sound ID"})
		return
	}
	_, err = h.pool.Exec(c.Request.Context(), `
		UPDATE sounds SET use_count = use_count + 1 WHERE id = $1 AND is_active = true
	`, soundID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record use"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// ─── Admin endpoints ───────────────────────────────────────────────────────

// AdminList returns all sounds including inactive ones, for admin management.
func (h *SoundsHandler) AdminList(c *gin.Context) {
	ctx := c.Request.Context()
	bucket := c.Query("bucket")
	limit := 100
	if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 && l <= 500 {
		limit = l
	}

	var args []any
	query := `
		SELECT id, title, bucket, duration_ms, use_count, r2_key,
		       uploader_id, source_post_id, created_at, is_active
		FROM sounds`

	if bucket == "user" || bucket == "library" {
		query += ` WHERE bucket = $1`
		args = append(args, bucket)
	}
	query += ` ORDER BY created_at DESC LIMIT $` + strconv.Itoa(len(args)+1)
	args = append(args, limit)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch sounds"})
		return
	}
	defer rows.Close()

	type adminSoundRow struct {
		soundItem
		IsActive bool `json:"is_active"`
	}
	var sounds []adminSoundRow
	for rows.Next() {
		var s adminSoundRow
		if err := rows.Scan(
			&s.ID, &s.Title, &s.Bucket, &s.DurationMS, &s.UseCount,
			&s.R2Key, &s.UploaderID, &s.SourcePostID, &s.CreatedAt, &s.IsActive,
		); err != nil {
			continue
		}
		s.AudioURL = h.audioURL(s.R2Key)
		sounds = append(sounds, s)
	}
	if sounds == nil {
		sounds = []adminSoundRow{}
	}
	c.JSON(http.StatusOK, gin.H{"sounds": sounds})
}

// AdminCreate registers a library track. The audio file should already be
// uploaded to R2 via the media upload endpoint before calling this.
// Body: { title, r2_key, duration_ms?, bucket? }
func (h *SoundsHandler) AdminCreate(c *gin.Context) {
	ctx := c.Request.Context()
	var req struct {
		Title      string `json:"title" binding:"required"`
		R2Key      string `json:"r2_key" binding:"required"`
		DurationMS *int   `json:"duration_ms"`
		Bucket     string `json:"bucket"` // defaults to 'library'
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title and r2_key are required"})
		return
	}
	if req.Bucket != "user" {
		req.Bucket = "library"
	}

	var id uuid.UUID
	err := h.pool.QueryRow(ctx, `
		INSERT INTO sounds (title, r2_key, bucket, duration_ms)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, req.Title, req.R2Key, req.Bucket, req.DurationMS).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create sound"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id, "audio_url": h.audioURL(req.R2Key)})
}

// AdminUpdate updates title and/or is_active status for a sound.
// Body: { title?, is_active? }
func (h *SoundsHandler) AdminUpdate(c *gin.Context) {
	soundID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid sound ID"})
		return
	}
	ctx := c.Request.Context()

	var req struct {
		Title    *string `json:"title"`
		IsActive *bool   `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	if req.Title != nil {
		if _, err := h.pool.Exec(ctx,
			`UPDATE sounds SET title = $1 WHERE id = $2`, *req.Title, soundID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update title"})
			return
		}
	}
	if req.IsActive != nil {
		if _, err := h.pool.Exec(ctx,
			`UPDATE sounds SET is_active = $1 WHERE id = $2`, *req.IsActive, soundID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update status"})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"status": "updated"})
}

// audioURL builds the public CDN URL for an R2 audio key.
func (h *SoundsHandler) audioURL(r2Key string) string {
	if h.r2Domain == "" || r2Key == "" {
		return ""
	}
	return "https://" + h.r2Domain + "/" + r2Key
}
