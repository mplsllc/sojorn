// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// ActivityPubHandler serves read-only ActivityPub endpoints (WebFinger, Actor, Outbox).
type ActivityPubHandler struct {
	db         *pgxpool.Pool
	apiBaseURL string
}

// NewActivityPubHandler creates a new ActivityPubHandler.
func NewActivityPubHandler(db *pgxpool.Pool, apiBaseURL string) *ActivityPubHandler {
	return &ActivityPubHandler{db: db, apiBaseURL: apiBaseURL}
}

// domain returns the host portion of the API base URL (e.g. "api.sojorn.app").
func (h *ActivityPubHandler) domain() string {
	u, err := url.Parse(h.apiBaseURL)
	if err != nil {
		return "localhost"
	}
	return u.Host
}

// ──────────────────────────────────────────────────────────────────────────────
// WebFinger — GET /.well-known/webfinger?resource=acct:handle@domain
// ──────────────────────────────────────────────────────────────────────────────

func (h *ActivityPubHandler) WebFinger(c *gin.Context) {
	resource := c.Query("resource")
	if resource == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing resource parameter"})
		return
	}

	// Expect "acct:handle@domain"
	if !strings.HasPrefix(resource, "acct:") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "resource must start with acct:"})
		return
	}

	acct := strings.TrimPrefix(resource, "acct:")
	parts := strings.SplitN(acct, "@", 2)
	if len(parts) != 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid acct format, expected handle@domain"})
		return
	}
	handle := parts[0]
	requestedDomain := parts[1]

	// Only answer for our own domain
	if requestedDomain != h.domain() {
		c.JSON(http.StatusNotFound, gin.H{"error": "unknown domain"})
		return
	}

	// Verify user exists
	var exists bool
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM profiles p JOIN users u ON u.id = p.id WHERE p.handle = $1 AND u.status = 'active')`,
		handle,
	).Scan(&exists)
	if err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	actorURL := fmt.Sprintf("%s/api/v1/ap/users/%s", h.apiBaseURL, handle)

	c.Header("Content-Type", "application/jrd+json")
	c.JSON(http.StatusOK, gin.H{
		"subject": resource,
		"links": []gin.H{
			{
				"rel":  "self",
				"type": "application/activity+json",
				"href": actorURL,
			},
		},
	})
}

// ──────────────────────────────────────────────────────────────────────────────
// GetActor — GET /api/v1/ap/users/:handle
// ──────────────────────────────────────────────────────────────────────────────

func (h *ActivityPubHandler) GetActor(c *gin.Context) {
	handle := c.Param("handle")

	var (
		id          string
		displayName *string
		bio         *string
		avatarURL   *string
		isPrivate   *bool
	)
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT p.id, p.display_name, p.bio, p.avatar_url, p.is_private
		FROM profiles p
		JOIN users u ON u.id = p.id
		WHERE p.handle = $1 AND u.status = 'active'
	`, handle).Scan(&id, &displayName, &bio, &avatarURL, &isPrivate)
	if err != nil {
		if err == pgx.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		} else {
			log.Error().Err(err).Str("handle", handle).Msg("[ActivityPub] failed to fetch actor")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		}
		return
	}

	// Only expose public (non-private) profiles
	if isPrivate != nil && *isPrivate {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	actorID := fmt.Sprintf("%s/api/v1/ap/users/%s", h.apiBaseURL, handle)
	profileURL := fmt.Sprintf("%s/@%s", h.apiBaseURL, handle)

	name := handle
	if displayName != nil && *displayName != "" {
		name = *displayName
	}
	summary := ""
	if bio != nil {
		summary = *bio
	}

	actor := gin.H{
		"@context": []string{
			"https://www.w3.org/ns/activitystreams",
			"https://w3id.org/security/v1",
		},
		"type":              "Person",
		"id":                actorID,
		"preferredUsername":  handle,
		"name":              name,
		"summary":           summary,
		"url":               profileURL,
		"inbox":             actorID + "/inbox",
		"outbox":            actorID + "/outbox",
		"followers":         actorID + "/followers",
		"following":         actorID + "/following",
		"publicKey": gin.H{
			"id":           actorID + "#main-key",
			"owner":        actorID,
			"publicKeyPem": "",
		},
	}

	if avatarURL != nil && *avatarURL != "" {
		actor["icon"] = gin.H{
			"type": "Image",
			"url":  *avatarURL,
		}
	}

	c.Header("Content-Type", "application/activity+json")
	c.JSON(http.StatusOK, actor)
}

// ──────────────────────────────────────────────────────────────────────────────
// GetOutbox — GET /api/v1/ap/users/:handle/outbox
// ──────────────────────────────────────────────────────────────────────────────

func (h *ActivityPubHandler) GetOutbox(c *gin.Context) {
	handle := c.Param("handle")

	// Verify user exists (active, public)
	var userID string
	var isPrivate *bool
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT p.id, p.is_private
		FROM profiles p
		JOIN users u ON u.id = p.id
		WHERE p.handle = $1 AND u.status = 'active'
	`, handle).Scan(&userID, &isPrivate)
	if err != nil {
		if err == pgx.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		} else {
			log.Error().Err(err).Str("handle", handle).Msg("[ActivityPub] outbox user lookup failed")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		}
		return
	}
	if isPrivate != nil && *isPrivate {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	outboxID := fmt.Sprintf("%s/api/v1/ap/users/%s/outbox", h.apiBaseURL, handle)
	actorID := fmt.Sprintf("%s/api/v1/ap/users/%s", h.apiBaseURL, handle)

	// If not a page request, return collection summary with total count
	if c.Query("page") != "true" {
		var totalItems int
		err := h.db.QueryRow(c.Request.Context(), `
			SELECT COUNT(*)
			FROM posts
			WHERE author_id = $1::uuid
			  AND deleted_at IS NULL
			  AND status = 'active'
			  AND COALESCE(visibility, 'public') = 'public'
		`, userID).Scan(&totalItems)
		if err != nil {
			log.Error().Err(err).Msg("[ActivityPub] outbox count failed")
			totalItems = 0
		}

		c.Header("Content-Type", "application/activity+json")
		c.JSON(http.StatusOK, gin.H{
			"@context":   "https://www.w3.org/ns/activitystreams",
			"type":       "OrderedCollection",
			"id":         outboxID,
			"totalItems": totalItems,
			"first":      outboxID + "?page=true",
		})
		return
	}

	// Paginated page request
	const pageSize = 20

	query := `
		SELECT p.id, p.body, p.created_at
		FROM posts p
		WHERE p.author_id = $1::uuid
		  AND p.deleted_at IS NULL
		  AND p.status = 'active'
		  AND COALESCE(p.visibility, 'public') = 'public'
	`
	args := []interface{}{userID}
	argIdx := 2

	if minID := c.Query("min_id"); minID != "" {
		query += fmt.Sprintf(" AND p.id > $%d::uuid", argIdx)
		args = append(args, minID)
		argIdx++
		query += " ORDER BY p.created_at ASC"
	} else if maxID := c.Query("max_id"); maxID != "" {
		query += fmt.Sprintf(" AND p.id < $%d::uuid", argIdx)
		args = append(args, maxID)
		argIdx++
		query += " ORDER BY p.created_at DESC"
	} else {
		query += " ORDER BY p.created_at DESC"
	}

	query += fmt.Sprintf(" LIMIT $%d", argIdx)
	args = append(args, pageSize+1) // fetch one extra to detect next page

	rows, err := h.db.Query(c.Request.Context(), query, args...)
	if err != nil {
		log.Error().Err(err).Msg("[ActivityPub] outbox query failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	defer rows.Close()

	type postRow struct {
		ID        string
		Body      string
		CreatedAt time.Time
	}
	var posts []postRow
	for rows.Next() {
		var pr postRow
		if err := rows.Scan(&pr.ID, &pr.Body, &pr.CreatedAt); err != nil {
			log.Error().Err(err).Msg("[ActivityPub] outbox row scan failed")
			continue
		}
		posts = append(posts, pr)
	}

	hasMore := len(posts) > pageSize
	if hasMore {
		posts = posts[:pageSize]
	}

	// Build ordered items (Create activities wrapping Note objects)
	orderedItems := make([]gin.H, 0, len(posts))
	for _, p := range posts {
		noteID := fmt.Sprintf("%s/api/v1/ap/posts/%s", h.apiBaseURL, p.ID)
		orderedItems = append(orderedItems, gin.H{
			"type":      "Create",
			"id":        noteID + "/activity",
			"actor":     actorID,
			"published": p.CreatedAt.UTC().Format(time.RFC3339),
			"to":        []string{"https://www.w3.org/ns/activitystreams#Public"},
			"object": gin.H{
				"type":         "Note",
				"id":           noteID,
				"content":      p.Body,
				"published":    p.CreatedAt.UTC().Format(time.RFC3339),
				"attributedTo": actorID,
				"to":           []string{"https://www.w3.org/ns/activitystreams#Public"},
				"url":          noteID,
			},
		})
	}

	result := gin.H{
		"@context":     "https://www.w3.org/ns/activitystreams",
		"type":         "OrderedCollectionPage",
		"id":           outboxID + "?page=true" + buildPaginationSuffix(c),
		"partOf":       outboxID,
		"orderedItems": orderedItems,
	}

	if hasMore && len(posts) > 0 {
		lastID := posts[len(posts)-1].ID
		result["next"] = outboxID + "?page=true&max_id=" + lastID
	}

	c.Header("Content-Type", "application/activity+json")
	c.JSON(http.StatusOK, result)
}

// buildPaginationSuffix reproduces the pagination query params for the current page ID.
func buildPaginationSuffix(c *gin.Context) string {
	var s string
	if v := c.Query("min_id"); v != "" {
		s += "&min_id=" + url.QueryEscape(v)
	}
	if v := c.Query("max_id"); v != "" {
		s += "&max_id=" + url.QueryEscape(v)
	}
	return s
}
