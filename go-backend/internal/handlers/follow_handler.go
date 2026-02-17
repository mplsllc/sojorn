package handlers

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type FollowHandler struct {
	db *pgxpool.Pool
}

func NewFollowHandler(db *pgxpool.Pool) *FollowHandler {
	return &FollowHandler{db: db}
}

// FollowUser — POST /users/:userId/follow
func (h *FollowHandler) FollowUser(c *gin.Context) {
	userID := c.GetString("user_id")
	targetUserID := c.Param("userId")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if userID == targetUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot follow yourself"})
		return
	}

	_, err := h.db.Exec(context.Background(), `
		INSERT INTO follows (follower_id, following_id)
		VALUES ($1, $2)
		ON CONFLICT (follower_id, following_id) DO NOTHING
	`, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to follow user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "followed"})
}

// UnfollowUser — POST /users/:userId/unfollow
func (h *FollowHandler) UnfollowUser(c *gin.Context) {
	userID := c.GetString("user_id")
	targetUserID := c.Param("userId")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	_, err := h.db.Exec(context.Background(), `
		DELETE FROM follows WHERE follower_id = $1 AND following_id = $2
	`, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to unfollow user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "unfollowed"})
}

// IsFollowing — GET /users/:userId/is-following
func (h *FollowHandler) IsFollowing(c *gin.Context) {
	userID := c.GetString("user_id")
	targetUserID := c.Param("userId")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var isFollowing bool
	err := h.db.QueryRow(context.Background(), `
		SELECT EXISTS(
			SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2
		)
	`, userID, targetUserID).Scan(&isFollowing)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check follow status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"is_following": isFollowing})
}

// GetMutualFollowers — GET /users/:userId/mutual-followers
func (h *FollowHandler) GetMutualFollowers(c *gin.Context) {
	userID := c.GetString("user_id")
	targetUserID := c.Param("userId")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	rows, err := h.db.Query(context.Background(), `
		SELECT p.id, p.handle, p.display_name, p.avatar_url
		FROM profiles p
		WHERE p.id IN (
			SELECT following_id FROM follows WHERE follower_id = $1
		)
		AND p.id IN (
			SELECT following_id FROM follows WHERE follower_id = $2
		)
		LIMIT 50
	`, userID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get mutual followers"})
		return
	}
	defer rows.Close()

	type mutualUser struct {
		ID          string  `json:"id"`
		Handle      string  `json:"handle"`
		DisplayName string  `json:"display_name"`
		AvatarURL   *string `json:"avatar_url"`
	}
	users := []mutualUser{}
	for rows.Next() {
		var u mutualUser
		if err := rows.Scan(&u.ID, &u.Handle, &u.DisplayName, &u.AvatarURL); err == nil {
			users = append(users, u)
		}
	}

	c.JSON(http.StatusOK, gin.H{"mutual_followers": users})
}

// GetSuggestedUsers — GET /users/suggested
func (h *FollowHandler) GetSuggestedUsers(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Suggest users followed by people the current user follows, excluding already-followed
	rows, err := h.db.Query(context.Background(), `
		SELECT DISTINCT p.id, p.handle, p.display_name, p.avatar_url,
		       COUNT(f2.follower_id) AS mutual_count
		FROM follows f1
		JOIN follows f2 ON f2.follower_id = f1.following_id
		JOIN profiles p ON p.id = f2.following_id
		WHERE f1.follower_id = $1
		  AND f2.following_id != $1
		  AND f2.following_id NOT IN (
		      SELECT following_id FROM follows WHERE follower_id = $1
		  )
		GROUP BY p.id, p.handle, p.display_name, p.avatar_url
		ORDER BY mutual_count DESC
		LIMIT 10
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get suggestions"})
		return
	}
	defer rows.Close()

	type suggestedUser struct {
		ID           string  `json:"id"`
		Handle       string  `json:"handle"`
		DisplayName  string  `json:"display_name"`
		AvatarURL    *string `json:"avatar_url"`
		MutualCount  int     `json:"mutual_count"`
	}
	suggestions := []suggestedUser{}
	for rows.Next() {
		var u suggestedUser
		if err := rows.Scan(&u.ID, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.MutualCount); err == nil {
			suggestions = append(suggestions, u)
		}
	}

	c.JSON(http.StatusOK, gin.H{"suggestions": suggestions})
}

// GetFollowers — GET /users/:userId/followers
func (h *FollowHandler) GetFollowers(c *gin.Context) {
	targetUserID := c.Param("userId")

	rows, err := h.db.Query(context.Background(), `
		SELECT p.id, p.handle, p.display_name, p.avatar_url, f.created_at
		FROM follows f
		JOIN profiles p ON f.follower_id = p.id
		WHERE f.following_id = $1
		ORDER BY f.created_at DESC
		LIMIT 100
	`, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get followers"})
		return
	}
	defer rows.Close()

	type follower struct {
		ID          string  `json:"id"`
		Handle      string  `json:"handle"`
		DisplayName string  `json:"display_name"`
		AvatarURL   *string `json:"avatar_url"`
		FollowedAt  string  `json:"followed_at"`
	}
	followers := []follower{}
	for rows.Next() {
		var f follower
		var followedAt interface{}
		if err := rows.Scan(&f.ID, &f.Handle, &f.DisplayName, &f.AvatarURL, &followedAt); err == nil {
			followers = append(followers, f)
		}
	}

	c.JSON(http.StatusOK, gin.H{"followers": followers})
}

// GetFollowing — GET /users/:userId/following
func (h *FollowHandler) GetFollowing(c *gin.Context) {
	targetUserID := c.Param("userId")

	rows, err := h.db.Query(context.Background(), `
		SELECT p.id, p.handle, p.display_name, p.avatar_url, f.created_at
		FROM follows f
		JOIN profiles p ON f.following_id = p.id
		WHERE f.follower_id = $1
		ORDER BY f.created_at DESC
		LIMIT 100
	`, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get following"})
		return
	}
	defer rows.Close()

	type followingUser struct {
		ID          string  `json:"id"`
		Handle      string  `json:"handle"`
		DisplayName string  `json:"display_name"`
		AvatarURL   *string `json:"avatar_url"`
		FollowedAt  string  `json:"followed_at"`
	}
	following := []followingUser{}
	for rows.Next() {
		var f followingUser
		var followedAt interface{}
		if err := rows.Scan(&f.ID, &f.Handle, &f.DisplayName, &f.AvatarURL, &followedAt); err == nil {
			following = append(following, f)
		}
	}

	c.JSON(http.StatusOK, gin.H{"following": following})
}
