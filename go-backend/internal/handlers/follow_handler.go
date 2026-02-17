package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type FollowHandler struct {
	db interface {
		Exec(query string, args ...interface{}) (interface{}, error)
		Query(query string, args ...interface{}) (interface{}, error)
		QueryRow(query string, args ...interface{}) interface{}
	}
}

func NewFollowHandler(db interface {
	Exec(query string, args ...interface{}) (interface{}, error)
	Query(query string, args ...interface{}) (interface{}, error)
	QueryRow(query string, args ...interface{}) interface{}
}) *FollowHandler {
	return &FollowHandler{db: db}
}

// FollowUser creates a follow relationship
func (h *FollowHandler) FollowUser(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Target user ID required"})
		return
	}

	if userID == targetUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot follow yourself"})
		return
	}

	query := `
		INSERT INTO follows (follower_id, following_id)
		VALUES ($1, $2)
		ON CONFLICT (follower_id, following_id) DO NOTHING
		RETURNING id
	`

	var followID string
	err := h.db.QueryRow(query, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to follow user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Successfully followed user",
		"follow_id": followID,
	})
}

// UnfollowUser removes a follow relationship
func (h *FollowHandler) UnfollowUser(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Target user ID required"})
		return
	}

	query := `
		DELETE FROM follows
		WHERE follower_id = $1 AND following_id = $2
	`

	_, err := h.db.Exec(query, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unfollow user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Successfully unfollowed user"})
}

// IsFollowing checks if current user follows target user
func (h *FollowHandler) IsFollowing(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Target user ID required"})
		return
	}

	query := `
		SELECT EXISTS(
			SELECT 1 FROM follows
			WHERE follower_id = $1 AND following_id = $2
		)
	`

	var isFollowing bool
	err := h.db.QueryRow(query, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check follow status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"is_following": isFollowing})
}

// GetMutualFollowers returns users that both current user and target user follow
func (h *FollowHandler) GetMutualFollowers(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Target user ID required"})
		return
	}

	query := `SELECT * FROM get_mutual_followers($1, $2)`

	rows, err := h.db.Query(query, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get mutual followers"})
		return
	}

	var mutualFollowers []map[string]interface{}
	// Parse rows into mutualFollowers slice
	// Implementation depends on your DB driver

	c.JSON(http.StatusOK, gin.H{"mutual_followers": mutualFollowers})
}

// GetSuggestedUsers returns suggested users to follow
func (h *FollowHandler) GetSuggestedUsers(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	limit := 10
	if limitParam := c.Query("limit"); limitParam != "" {
		// Parse limit from query param
	}

	query := `SELECT * FROM get_suggested_users($1, $2)`

	rows, err := h.db.Query(query, userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get suggestions"})
		return
	}

	var suggestions []map[string]interface{}
	// Parse rows into suggestions slice

	c.JSON(http.StatusOK, gin.H{"suggestions": suggestions})
}

// GetFollowers returns list of users following the target user
func (h *FollowHandler) GetFollowers(c *gin.Context) {
	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	query := `
		SELECT p.user_id, p.username, p.display_name, p.avatar_url, f.created_at
		FROM follows f
		JOIN profiles p ON f.follower_id = p.user_id
		WHERE f.following_id = $1
		ORDER BY f.created_at DESC
		LIMIT 100
	`

	rows, err := h.db.Query(query, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get followers"})
		return
	}

	var followers []map[string]interface{}
	// Parse rows

	c.JSON(http.StatusOK, gin.H{"followers": followers})
}

// GetFollowing returns list of users that target user follows
func (h *FollowHandler) GetFollowing(c *gin.Context) {
	targetUserID := c.Param("userId")
	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	query := `
		SELECT p.user_id, p.username, p.display_name, p.avatar_url, f.created_at
		FROM follows f
		JOIN profiles p ON f.following_id = p.user_id
		WHERE f.follower_id = $1
		ORDER BY f.created_at DESC
		LIMIT 100
	`

	rows, err := h.db.Query(query, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get following"})
		return
	}

	var following []map[string]interface{}
	// Parse rows

	c.JSON(http.StatusOK, gin.H{"following": following})
}
