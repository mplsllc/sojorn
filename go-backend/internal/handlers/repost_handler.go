// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
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

type RepostHandler struct {
	db *pgxpool.Pool
}

func NewRepostHandler(db *pgxpool.Pool) *RepostHandler {
	return &RepostHandler{db: db}
}

// CreateRepost — POST /posts/repost
func (h *RepostHandler) CreateRepost(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var req struct {
		OriginalPostID string                 `json:"original_post_id" binding:"required"`
		Type           string                 `json:"type" binding:"required"`
		Comment        string                 `json:"comment"`
		Metadata       map[string]interface{} `json:"metadata"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	validTypes := map[string]bool{"standard": true, "quote": true, "boost": true, "amplify": true}
	if !validTypes[req.Type] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid repost type"})
		return
	}

	var authorHandle string
	var avatarURL *string
	err := h.db.QueryRow(c.Request.Context(),
		"SELECT handle, avatar_url FROM profiles WHERE id = $1", userIDStr,
	).Scan(&authorHandle, &avatarURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user info"})
		return
	}

	id := uuid.New().String()
	now := time.Now()
	_, err = h.db.Exec(c.Request.Context(), `
		INSERT INTO reposts (id, original_post_id, author_id, type, comment, metadata, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (original_post_id, author_id, type) DO NOTHING
	`, id, req.OriginalPostID, userIDStr, req.Type, req.Comment, req.Metadata, now)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create repost"})
		return
	}

	countCol := repostCountColumn(req.Type)
	h.db.Exec(c.Request.Context(),
		"UPDATE posts SET "+countCol+" = "+countCol+" + 1 WHERE id = $1",
		req.OriginalPostID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"repost": gin.H{
			"id":                  id,
			"original_post_id":    req.OriginalPostID,
			"author_id":           userIDStr,
			"author_handle":       authorHandle,
			"author_avatar":       avatarURL,
			"type":                req.Type,
			"comment":             req.Comment,
			"created_at":          now.Format(time.RFC3339),
			"boost_count":         0,
			"amplification_score": 0,
			"is_amplified":        false,
		},
	})
}

// BoostPost — POST /posts/boost
func (h *RepostHandler) BoostPost(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var req struct {
		PostID      string `json:"post_id" binding:"required"`
		BoostType   string `json:"boost_type" binding:"required"`
		BoostAmount int    `json:"boost_amount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.BoostAmount <= 0 {
		req.BoostAmount = 1
	}

	maxDaily := 5
	if req.BoostType == "amplify" {
		maxDaily = 3
	}
	var dailyCount int
	h.db.QueryRow(c.Request.Context(), `
		SELECT COUNT(*) FROM reposts
		WHERE author_id = $1 AND type = $2 AND created_at > NOW() - INTERVAL '24 hours'
	`, userIDStr, req.BoostType).Scan(&dailyCount)
	if dailyCount >= maxDaily {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "daily boost limit reached", "success": false})
		return
	}

	id := uuid.New().String()
	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO reposts (id, original_post_id, author_id, type, created_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (original_post_id, author_id, type) DO NOTHING
	`, id, req.PostID, userIDStr, req.BoostType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to boost post"})
		return
	}

	countCol := repostCountColumn(req.BoostType)
	h.db.Exec(c.Request.Context(),
		"UPDATE posts SET "+countCol+" = "+countCol+" + 1 WHERE id = $1",
		req.PostID)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetRepostsForPost — GET /posts/:id/reposts
func (h *RepostHandler) GetRepostsForPost(c *gin.Context) {
	postID := c.Param("id")
	limit := clampInt(queryInt(c, "limit", 20), 1, 100)

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT r.id, r.original_post_id, r.author_id,
		       p.handle, p.avatar_url,
		       r.type, r.comment, r.created_at
		FROM reposts r
		JOIN profiles p ON p.id = r.author_id
		WHERE r.original_post_id = $1
		ORDER BY r.created_at DESC
		LIMIT $2
	`, postID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get reposts"})
		return
	}
	defer rows.Close()

	reposts := buildRepostList(rows)
	c.JSON(http.StatusOK, gin.H{"success": true, "reposts": reposts})
}

// GetUserReposts — GET /users/:id/reposts
func (h *RepostHandler) GetUserReposts(c *gin.Context) {
	userID := c.Param("id")
	limit := clampInt(queryInt(c, "limit", 20), 1, 100)

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT r.id, r.original_post_id, r.author_id,
		       p.handle, p.avatar_url,
		       r.type, r.comment, r.created_at
		FROM reposts r
		JOIN profiles p ON p.id = r.author_id
		WHERE r.author_id = $1
		ORDER BY r.created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user reposts"})
		return
	}
	defer rows.Close()

	reposts := buildRepostList(rows)
	c.JSON(http.StatusOK, gin.H{"success": true, "reposts": reposts})
}

// DeleteRepost — DELETE /reposts/:id
func (h *RepostHandler) DeleteRepost(c *gin.Context) {
	userID, _ := c.Get("user_id")
	repostID := c.Param("id")

	var origPostID, repostType string
	err := h.db.QueryRow(c.Request.Context(),
		"SELECT original_post_id, type FROM reposts WHERE id = $1 AND author_id = $2",
		repostID, userID.(string),
	).Scan(&origPostID, &repostType)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "repost not found"})
		return
	}

	_, err = h.db.Exec(c.Request.Context(),
		"DELETE FROM reposts WHERE id = $1 AND author_id = $2",
		repostID, userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete repost"})
		return
	}

	countCol := repostCountColumn(repostType)
	h.db.Exec(c.Request.Context(),
		"UPDATE posts SET "+countCol+" = GREATEST("+countCol+" - 1, 0) WHERE id = $1",
		origPostID)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetAmplificationAnalytics — GET /posts/:id/amplification
func (h *RepostHandler) GetAmplificationAnalytics(c *gin.Context) {
	postID := c.Param("id")

	var totalAmplification int
	h.db.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM reposts WHERE original_post_id = $1", postID,
	).Scan(&totalAmplification)

	var viewCount int
	h.db.QueryRow(c.Request.Context(),
		"SELECT COALESCE(view_count, 1) FROM posts WHERE id = $1", postID,
	).Scan(&viewCount)
	if viewCount == 0 {
		viewCount = 1
	}
	amplificationRate := float64(totalAmplification) / float64(viewCount)

	rows, _ := h.db.Query(c.Request.Context(),
		"SELECT type, COUNT(*) FROM reposts WHERE original_post_id = $1 GROUP BY type", postID)
	repostCounts := map[string]int{}
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var t string
			var cnt int
			rows.Scan(&t, &cnt)
			repostCounts[t] = cnt
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"analytics": gin.H{
			"post_id":             postID,
			"metrics":             []gin.H{},
			"reposts":             []gin.H{},
			"total_amplification": totalAmplification,
			"amplification_rate":  amplificationRate,
			"repost_counts":       repostCounts,
		},
	})
}

// GetTrendingPosts — GET /posts/trending
func (h *RepostHandler) GetTrendingPosts(c *gin.Context) {
	limit := clampInt(queryInt(c, "limit", 10), 1, 50)
	category := c.Query("category")

	query := `
		SELECT p.id
		FROM posts p
		WHERE p.status = 'active'
		  AND p.deleted_at IS NULL
	`
	args := []interface{}{}
	argIdx := 1

	if category != "" {
		query += " AND p.category = $" + strconv.Itoa(argIdx)
		args = append(args, category)
		argIdx++
	}

	query += `
		ORDER BY (
			COALESCE(p.like_count, 0)    * 1  +
			COALESCE(p.comment_count, 0) * 3  +
			COALESCE(p.repost_count, 0)  * 4  +
			COALESCE(p.boost_count, 0)   * 8  +
			COALESCE(p.amplify_count, 0) * 10
		) DESC, p.created_at DESC
		LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := h.db.Query(c.Request.Context(), query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get trending posts"})
		return
	}
	defer rows.Close()

	var postIDs []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		postIDs = append(postIDs, id)
	}
	if postIDs == nil {
		postIDs = []string{}
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "posts": postIDs})
}

// GetAmplificationRules — GET /amplification/rules
func (h *RepostHandler) GetAmplificationRules(c *gin.Context) {
	rules := []gin.H{
		{
			"id": "rule-standard", "name": "Standard Repost",
			"description": "Share a post with your followers",
			"type": "standard", "weight_multiplier": 1.0,
			"min_boost_score": 0, "max_daily_boosts": 20,
			"is_active": true, "created_at": "2024-01-01T00:00:00Z",
		},
		{
			"id": "rule-quote", "name": "Quote Repost",
			"description": "Share a post with your commentary",
			"type": "quote", "weight_multiplier": 1.5,
			"min_boost_score": 0, "max_daily_boosts": 10,
			"is_active": true, "created_at": "2024-01-01T00:00:00Z",
		},
		{
			"id": "rule-boost", "name": "Boost",
			"description": "Amplify a post's reach in the feed",
			"type": "boost", "weight_multiplier": 8.0,
			"min_boost_score": 0, "max_daily_boosts": 5,
			"is_active": true, "created_at": "2024-01-01T00:00:00Z",
		},
		{
			"id": "rule-amplify", "name": "Amplify",
			"description": "Maximum amplification for high-quality content",
			"type": "amplify", "weight_multiplier": 10.0,
			"min_boost_score": 100, "max_daily_boosts": 3,
			"is_active": true, "created_at": "2024-01-01T00:00:00Z",
		},
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "rules": rules})
}

// CalculateAmplificationScore — POST /posts/:id/calculate-score
func (h *RepostHandler) CalculateAmplificationScore(c *gin.Context) {
	postID := c.Param("id")

	var likes, comments, reposts, boosts, amplifies int
	h.db.QueryRow(c.Request.Context(), `
		SELECT COALESCE(like_count,0), COALESCE(comment_count,0),
		       COALESCE(repost_count,0), COALESCE(boost_count,0), COALESCE(amplify_count,0)
		FROM posts WHERE id = $1
	`, postID).Scan(&likes, &comments, &reposts, &boosts, &amplifies)

	score := likes*1 + comments*3 + reposts*4 + boosts*8 + amplifies*10
	c.JSON(http.StatusOK, gin.H{"success": true, "score": score})
}

// CanBoostPost — GET /users/:id/can-boost/:postId
func (h *RepostHandler) CanBoostPost(c *gin.Context) {
	userID := c.Param("id")
	postID := c.Param("postId")
	boostType := c.Query("type")

	var alreadyBoosted int
	h.db.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM reposts WHERE author_id=$1 AND original_post_id=$2 AND type=$3",
		userID, postID, boostType,
	).Scan(&alreadyBoosted)
	if alreadyBoosted > 0 {
		c.JSON(http.StatusOK, gin.H{"can_boost": false, "reason": "already_boosted"})
		return
	}

	maxDaily := 5
	if boostType == "amplify" {
		maxDaily = 3
	}
	var dailyCount int
	h.db.QueryRow(c.Request.Context(), `
		SELECT COUNT(*) FROM reposts
		WHERE author_id=$1 AND type=$2 AND created_at > NOW() - INTERVAL '24 hours'
	`, userID, boostType).Scan(&dailyCount)

	c.JSON(http.StatusOK, gin.H{"can_boost": dailyCount < maxDaily})
}

// GetDailyBoostCount — GET /users/:id/daily-boosts
func (h *RepostHandler) GetDailyBoostCount(c *gin.Context) {
	userID := c.Param("id")

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT type, COUNT(*) FROM reposts
		WHERE author_id=$1 AND created_at > NOW() - INTERVAL '24 hours'
		GROUP BY type
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get boost counts"})
		return
	}
	defer rows.Close()

	boostCounts := map[string]int{}
	for rows.Next() {
		var t string
		var cnt int
		rows.Scan(&t, &cnt)
		boostCounts[t] = cnt
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "boost_counts": boostCounts})
}

// ReportRepost — POST /reposts/:id/report
func (h *RepostHandler) ReportRepost(c *gin.Context) {
	userID, _ := c.Get("user_id")
	repostID := c.Param("id")

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO repost_reports (id, repost_id, reporter_id, reason, created_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (repost_id, reporter_id) DO NOTHING
	`, uuid.New().String(), repostID, userID.(string), req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to report repost"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ─── helpers ─────────────────────────────────────────────────────────────────

func repostCountColumn(repostType string) string {
	switch repostType {
	case "boost":
		return "boost_count"
	case "amplify":
		return "amplify_count"
	default:
		return "repost_count"
	}
}

func queryInt(c *gin.Context, key string, def int) int {
	if s := c.Query(key); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			return n
		}
	}
	return def
}

func clampInt(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func buildRepostList(rows interface {
	Next() bool
	Scan(...interface{}) error
	Close()
}) []gin.H {
	list := []gin.H{}
	for rows.Next() {
		var id, origPostID, authorID, handle, repostType string
		var avatarURL, comment *string
		var createdAt time.Time
		rows.Scan(&id, &origPostID, &authorID, &handle, &avatarURL, &repostType, &comment, &createdAt)
		list = append(list, gin.H{
			"id":                  id,
			"original_post_id":    origPostID,
			"author_id":           authorID,
			"author_handle":       handle,
			"author_avatar":       avatarURL,
			"type":                repostType,
			"comment":             comment,
			"created_at":          createdAt.Format(time.RFC3339),
			"boost_count":         0,
			"amplification_score": 0,
			"is_amplified":        false,
		})
	}
	return list
}
