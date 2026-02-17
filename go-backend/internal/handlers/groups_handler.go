package handlers

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type GroupsHandler struct {
	db *pgxpool.Pool
}

func NewGroupsHandler(db *pgxpool.Pool) *GroupsHandler {
	return &GroupsHandler{db: db}
}

type Group struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Category    string    `json:"category"`
	AvatarURL   *string   `json:"avatar_url"`
	BannerURL   *string   `json:"banner_url"`
	IsPrivate   bool      `json:"is_private"`
	CreatedBy   string    `json:"created_by"`
	MemberCount int       `json:"member_count"`
	PostCount   int       `json:"post_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	UserRole    *string   `json:"user_role,omitempty"`
	IsMember    bool      `json:"is_member"`
	HasPending  bool      `json:"has_pending_request,omitempty"`
}

type GroupMember struct {
	ID       string    `json:"id"`
	GroupID  string    `json:"group_id"`
	UserID   string    `json:"user_id"`
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
	Username string    `json:"username,omitempty"`
	Avatar   *string   `json:"avatar_url,omitempty"`
}

type JoinRequest struct {
	ID         string     `json:"id"`
	GroupID    string     `json:"group_id"`
	UserID     string     `json:"user_id"`
	Status     string     `json:"status"`
	Message    *string    `json:"message"`
	CreatedAt  time.Time  `json:"created_at"`
	ReviewedAt *time.Time `json:"reviewed_at"`
	ReviewedBy *string    `json:"reviewed_by"`
	Username   string     `json:"username,omitempty"`
	Avatar     *string    `json:"avatar_url,omitempty"`
}

// ListGroups returns all groups with optional category filter
func (h *GroupsHandler) ListGroups(c *gin.Context) {
	userID := c.GetString("user_id")
	category := c.Query("category")
	page := c.DefaultQuery("page", "0")
	limit := c.DefaultQuery("limit", "20")

	query := `
		SELECT g.id, g.name, g.description, g.category, g.avatar_url, g.banner_url,
		       g.is_private, g.created_by, g.member_count, g.post_count, g.created_at, g.updated_at,
		       gm.role, 
		       EXISTS(SELECT 1 FROM group_members WHERE group_id = g.id AND user_id = $1) as is_member,
		       EXISTS(SELECT 1 FROM group_join_requests WHERE group_id = g.id AND user_id = $1 AND status = 'pending') as has_pending
		FROM groups g
		LEFT JOIN group_members gm ON g.id = gm.group_id AND gm.user_id = $1
		WHERE ($2 = '' OR g.category = $2)
		ORDER BY g.member_count DESC, g.created_at DESC
		LIMIT $3 OFFSET $4
	`

	rows, err := h.db.Query(c.Request.Context(), query, userID, category, limit, page)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch groups"})
		return
	}
	defer rows.Close()

	groups := []Group{}
	for rows.Next() {
		var g Group
		err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.Category, &g.AvatarURL, &g.BannerURL,
			&g.IsPrivate, &g.CreatedBy, &g.MemberCount, &g.PostCount, &g.CreatedAt, &g.UpdatedAt,
			&g.UserRole, &g.IsMember, &g.HasPending)
		if err != nil {
			continue
		}
		groups = append(groups, g)
	}

	c.JSON(http.StatusOK, gin.H{"groups": groups})
}

// GetMyGroups returns groups the user is a member of
func (h *GroupsHandler) GetMyGroups(c *gin.Context) {
	userID := c.GetString("user_id")

	query := `
		SELECT g.id, g.name, g.description, g.category, g.avatar_url, g.banner_url,
		       g.is_private, g.created_by, g.member_count, g.post_count, g.created_at, g.updated_at,
		       gm.role
		FROM groups g
		JOIN group_members gm ON g.id = gm.group_id
		WHERE gm.user_id = $1
		ORDER BY gm.joined_at DESC
	`

	rows, err := h.db.Query(c.Request.Context(), query, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch groups"})
		return
	}
	defer rows.Close()

	groups := []Group{}
	for rows.Next() {
		var g Group
		g.IsMember = true
		err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.Category, &g.AvatarURL, &g.BannerURL,
			&g.IsPrivate, &g.CreatedBy, &g.MemberCount, &g.PostCount, &g.CreatedAt, &g.UpdatedAt,
			&g.UserRole)
		if err != nil {
			continue
		}
		groups = append(groups, g)
	}

	c.JSON(http.StatusOK, gin.H{"groups": groups})
}

// GetSuggestedGroups returns suggested groups for the user
func (h *GroupsHandler) GetSuggestedGroups(c *gin.Context) {
	userID := c.GetString("user_id")
	limit := c.DefaultQuery("limit", "10")

	query := `SELECT * FROM get_suggested_groups($1, $2)`

	rows, err := h.db.Query(c.Request.Context(), query, userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch suggestions"})
		return
	}
	defer rows.Close()

	type SuggestedGroup struct {
		Group
		Reason string `json:"reason"`
	}

	groups := []SuggestedGroup{}
	for rows.Next() {
		var sg SuggestedGroup
		err := rows.Scan(&sg.ID, &sg.Name, &sg.Description, &sg.Category, &sg.AvatarURL,
			&sg.IsPrivate, &sg.MemberCount, &sg.PostCount, &sg.Reason)
		if err != nil {
			continue
		}
		sg.IsMember = false
		groups = append(groups, sg)
	}

	c.JSON(http.StatusOK, gin.H{"suggestions": groups})
}

// GetGroup returns a single group by ID
func (h *GroupsHandler) GetGroup(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")

	query := `
		SELECT g.id, g.name, g.description, g.category, g.avatar_url, g.banner_url,
		       g.is_private, g.created_by, g.member_count, g.post_count, g.created_at, g.updated_at,
		       gm.role,
		       EXISTS(SELECT 1 FROM group_members WHERE group_id = g.id AND user_id = $2) as is_member,
		       EXISTS(SELECT 1 FROM group_join_requests WHERE group_id = g.id AND user_id = $2 AND status = 'pending') as has_pending
		FROM groups g
		LEFT JOIN group_members gm ON g.id = gm.group_id AND gm.user_id = $2
		WHERE g.id = $1
	`

	var g Group
	err := h.db.QueryRow(c.Request.Context(), query, groupID, userID).Scan(
		&g.ID, &g.Name, &g.Description, &g.Category, &g.AvatarURL, &g.BannerURL,
		&g.IsPrivate, &g.CreatedBy, &g.MemberCount, &g.PostCount, &g.CreatedAt, &g.UpdatedAt,
		&g.UserRole, &g.IsMember, &g.HasPending)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"group": g})
}

// CreateGroup creates a new group
func (h *GroupsHandler) CreateGroup(c *gin.Context) {
	userID := c.GetString("user_id")

	var req struct {
		Name        string  `json:"name" binding:"required,max=50"`
		Description string  `json:"description" binding:"max=300"`
		Category    string  `json:"category" binding:"required"`
		IsPrivate   bool    `json:"is_private"`
		AvatarURL   *string `json:"avatar_url"`
		BannerURL   *string `json:"banner_url"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Normalize name for uniqueness check
	req.Name = strings.TrimSpace(req.Name)

	tx, err := h.db.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create group"})
		return
	}
	defer tx.Rollback(c.Request.Context())

	// Create group
	var groupID string
	err = tx.QueryRow(c.Request.Context(), `
		INSERT INTO groups (name, description, category, is_private, created_by, avatar_url, banner_url)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id
	`, req.Name, req.Description, req.Category, req.IsPrivate, userID, req.AvatarURL, req.BannerURL).Scan(&groupID)

	if err != nil {
		if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "A group with this name already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create group"})
		return
	}

	// Add creator as owner
	_, err = tx.Exec(c.Request.Context(), `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'owner')
	`, groupID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add owner"})
		return
	}

	if err = tx.Commit(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create group"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"group_id": groupID, "message": "Group created successfully"})
}

// JoinGroup allows a user to join a public group or request to join a private group
func (h *GroupsHandler) JoinGroup(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")

	var req struct {
		Message *string `json:"message"`
	}
	c.ShouldBindJSON(&req)

	// Check if group exists and is private
	var isPrivate bool
	err := h.db.QueryRow(c.Request.Context(), `SELECT is_private FROM groups WHERE id = $1`, groupID).Scan(&isPrivate)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to join group"})
		return
	}

	// Check if already a member
	var exists bool
	err = h.db.QueryRow(c.Request.Context(), `
		SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)
	`, groupID, userID).Scan(&exists)
	if err == nil && exists {
		c.JSON(http.StatusConflict, gin.H{"error": "Already a member"})
		return
	}

	if isPrivate {
		// Create join request
		_, err = h.db.Exec(c.Request.Context(), `
			INSERT INTO group_join_requests (group_id, user_id, message)
			VALUES ($1, $2, $3)
			ON CONFLICT (group_id, user_id, status) DO NOTHING
		`, groupID, userID, req.Message)

		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create join request"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"message": "Join request sent", "status": "pending"})
	} else {
		// Join immediately
		_, err = h.db.Exec(c.Request.Context(), `
			INSERT INTO group_members (group_id, user_id, role)
			VALUES ($1, $2, 'member')
		`, groupID, userID)

		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to join group"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"message": "Joined successfully", "status": "joined"})
	}
}

// LeaveGroup allows a user to leave a group
func (h *GroupsHandler) LeaveGroup(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")

	// Check if user is owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Not a member of this group"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to leave group"})
		return
	}

	if role == "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Owner must transfer ownership or delete group before leaving"})
		return
	}

	// Remove member
	_, err = h.db.Exec(c.Request.Context(), `
		DELETE FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to leave group"})
		return
	}

	// Flag key rotation so admin client silently rotates on next open
	h.db.Exec(c.Request.Context(),
		`UPDATE groups SET key_rotation_needed = true WHERE id = $1`, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "Left group successfully"})
}

// GetGroupMembers returns members of a group
func (h *GroupsHandler) GetGroupMembers(c *gin.Context) {
	groupID := c.Param("id")
	page := c.DefaultQuery("page", "0")
	limit := c.DefaultQuery("limit", "50")

	query := `
		SELECT gm.id, gm.group_id, gm.user_id, gm.role, gm.joined_at,
		       p.username, p.avatar_url
		FROM group_members gm
		JOIN profiles p ON gm.user_id = p.user_id
		WHERE gm.group_id = $1
		ORDER BY 
		  CASE gm.role 
		    WHEN 'owner' THEN 1
		    WHEN 'admin' THEN 2
		    WHEN 'moderator' THEN 3
		    ELSE 4
		  END,
		  gm.joined_at ASC
		LIMIT $2 OFFSET $3
	`

	rows, err := h.db.Query(c.Request.Context(), query, groupID, limit, page)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch members"})
		return
	}
	defer rows.Close()

	members := []GroupMember{}
	for rows.Next() {
		var m GroupMember
		err := rows.Scan(&m.ID, &m.GroupID, &m.UserID, &m.Role, &m.JoinedAt, &m.Username, &m.Avatar)
		if err != nil {
			continue
		}
		members = append(members, m)
	}

	c.JSON(http.StatusOK, gin.H{"members": members})
}

// GetPendingRequests returns pending join requests for a group (admin only)
func (h *GroupsHandler) GetPendingRequests(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")

	// Check if user is admin/owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role)

	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	query := `
		SELECT jr.id, jr.group_id, jr.user_id, jr.status, jr.message, jr.created_at,
		       jr.reviewed_at, jr.reviewed_by, p.username, p.avatar_url
		FROM group_join_requests jr
		JOIN profiles p ON jr.user_id = p.user_id
		WHERE jr.group_id = $1 AND jr.status = 'pending'
		ORDER BY jr.created_at ASC
	`

	rows, err := h.db.Query(c.Request.Context(), query, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch requests"})
		return
	}
	defer rows.Close()

	requests := []JoinRequest{}
	for rows.Next() {
		var jr JoinRequest
		err := rows.Scan(&jr.ID, &jr.GroupID, &jr.UserID, &jr.Status, &jr.Message, &jr.CreatedAt,
			&jr.ReviewedAt, &jr.ReviewedBy, &jr.Username, &jr.Avatar)
		if err != nil {
			continue
		}
		requests = append(requests, jr)
	}

	c.JSON(http.StatusOK, gin.H{"requests": requests})
}

// ApproveJoinRequest approves a join request (admin only)
func (h *GroupsHandler) ApproveJoinRequest(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")
	requestID := c.Param("requestId")

	// Check if user is admin/owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role)

	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	tx, err := h.db.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to approve request"})
		return
	}
	defer tx.Rollback(c.Request.Context())

	// Get requester user ID
	var requesterID string
	err = tx.QueryRow(c.Request.Context(), `
		SELECT user_id FROM group_join_requests WHERE id = $1 AND group_id = $2 AND status = 'pending'
	`, requestID, groupID).Scan(&requesterID)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Request not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to approve request"})
		return
	}

	// Update request status
	_, err = tx.Exec(c.Request.Context(), `
		UPDATE group_join_requests 
		SET status = 'approved', reviewed_at = NOW(), reviewed_by = $1
		WHERE id = $2
	`, userID, requestID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to approve request"})
		return
	}

	// Add user as member
	_, err = tx.Exec(c.Request.Context(), `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'member')
	`, groupID, requesterID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add member"})
		return
	}

	if err = tx.Commit(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to approve request"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Request approved"})
}

// RejectJoinRequest rejects a join request (admin only)
func (h *GroupsHandler) RejectJoinRequest(c *gin.Context) {
	userID := c.GetString("user_id")
	groupID := c.Param("id")
	requestID := c.Param("requestId")

	// Check if user is admin/owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2
	`, groupID, userID).Scan(&role)

	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	_, err = h.db.Exec(c.Request.Context(), `
		UPDATE group_join_requests
		SET status = 'rejected', reviewed_at = NOW(), reviewed_by = $1
		WHERE id = $2 AND group_id = $3 AND status = 'pending'
	`, userID, requestID, groupID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reject request"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Request rejected"})
}

// ──────────────────────────────────────────────────────────────────────────────
// Group feed
// ──────────────────────────────────────────────────────────────────────────────

// GetGroupFeed GET /groups/:id/feed?limit=20&offset=0
func (h *GroupsHandler) GetGroupFeed(c *gin.Context) {
	groupID := c.Param("id")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT p.id, p.user_id, p.content, p.image_url, p.video_url,
		       p.thumbnail_url, p.created_at, p.status
		FROM posts p
		JOIN group_posts gp ON gp.post_id = p.id
		WHERE gp.group_id = $1 AND p.status = 'active'
		ORDER BY p.created_at DESC
		LIMIT $2 OFFSET $3
	`, groupID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch group feed"})
		return
	}
	defer rows.Close()

	type feedPost struct {
		ID           string    `json:"id"`
		UserID       string    `json:"user_id"`
		Content      string    `json:"content"`
		ImageURL     *string   `json:"image_url"`
		VideoURL     *string   `json:"video_url"`
		ThumbnailURL *string   `json:"thumbnail_url"`
		CreatedAt    time.Time `json:"created_at"`
		Status       string    `json:"status"`
	}

	var posts []feedPost
	for rows.Next() {
		var p feedPost
		if err := rows.Scan(&p.ID, &p.UserID, &p.Content, &p.ImageURL, &p.VideoURL,
			&p.ThumbnailURL, &p.CreatedAt, &p.Status); err != nil {
			continue
		}
		posts = append(posts, p)
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts, "limit": limit, "offset": offset})
}

// ──────────────────────────────────────────────────────────────────────────────
// E2EE group key management
// ──────────────────────────────────────────────────────────────────────────────

// GetGroupKeyStatus GET /groups/:id/key-status
// Returns the current key version, whether rotation is needed, and the caller's
// encrypted group key (if they have one).
func (h *GroupsHandler) GetGroupKeyStatus(c *gin.Context) {
	groupID := c.Param("id")
	userID, _ := c.Get("user_id")

	var keyVersion int
	var keyRotationNeeded bool
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT key_version, key_rotation_needed FROM groups WHERE id = $1`, groupID,
	).Scan(&keyVersion, &keyRotationNeeded)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}

	// Fetch this user's encrypted key for the current version
	var encryptedKey *string
	h.db.QueryRow(c.Request.Context(),
		`SELECT encrypted_key FROM group_member_keys
		 WHERE group_id = $1 AND user_id = $2 AND key_version = $3`,
		groupID, userID, keyVersion,
	).Scan(&encryptedKey)

	c.JSON(http.StatusOK, gin.H{
		"key_version":        keyVersion,
		"key_rotation_needed": keyRotationNeeded,
		"my_encrypted_key":   encryptedKey,
	})
}

// DistributeGroupKeys POST /groups/:id/keys
// Called by an admin/owner client after local key rotation to push new
// encrypted copies to each member.
// Body: {"keys": [{"user_id": "...", "encrypted_key": "...", "key_version": N}]}
func (h *GroupsHandler) DistributeGroupKeys(c *gin.Context) {
	groupID := c.Param("id")
	callerID, _ := c.Get("user_id")

	// Only owner/admin may distribute keys
	var role string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, callerID,
	).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group owners or admins may rotate keys"})
		return
	}

	var req struct {
		Keys []struct {
			UserID       string `json:"user_id" binding:"required"`
			EncryptedKey string `json:"encrypted_key" binding:"required"`
			KeyVersion   int    `json:"key_version" binding:"required"`
		} `json:"keys" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Determine the new key version (max of submitted versions)
	newVersion := 0
	for _, k := range req.Keys {
		if k.KeyVersion > newVersion {
			newVersion = k.KeyVersion
		}
	}

	for _, k := range req.Keys {
		h.db.Exec(c.Request.Context(), `
			INSERT INTO group_member_keys (group_id, user_id, key_version, encrypted_key, updated_at)
			VALUES ($1, $2, $3, $4, now())
			ON CONFLICT (group_id, user_id, key_version)
			DO UPDATE SET encrypted_key = EXCLUDED.encrypted_key, updated_at = now()
		`, groupID, k.UserID, k.KeyVersion, k.EncryptedKey)
	}

	// Clear the rotation flag and bump key_version on the group
	h.db.Exec(c.Request.Context(),
		`UPDATE groups SET key_rotation_needed = false, key_version = $1 WHERE id = $2`,
		newVersion, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "keys distributed", "key_version": newVersion})
}

// GetGroupMemberPublicKeys GET /groups/:id/members/public-keys
// Returns RSA public keys for all members so a rotating client can encrypt for each.
func (h *GroupsHandler) GetGroupMemberPublicKeys(c *gin.Context) {
	groupID := c.Param("id")
	callerID, _ := c.Get("user_id")

	// Caller must be a member
	var memberCount int
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT COUNT(*) FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, callerID,
	).Scan(&memberCount)
	if err != nil || memberCount == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a group member"})
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT gm.user_id, u.public_key
		FROM group_members gm
		JOIN users u ON u.id = gm.user_id
		WHERE gm.group_id = $1 AND u.public_key IS NOT NULL AND u.public_key != ''
	`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch member keys"})
		return
	}
	defer rows.Close()

	type memberKey struct {
		UserID    string `json:"user_id"`
		PublicKey string `json:"public_key"`
	}
	var keys []memberKey
	for rows.Next() {
		var mk memberKey
		if rows.Scan(&mk.UserID, &mk.PublicKey) == nil {
			keys = append(keys, mk)
		}
	}
	c.JSON(http.StatusOK, gin.H{"keys": keys})
}

// ──────────────────────────────────────────────────────────────────────────────
// Member invite / remove / settings
// ──────────────────────────────────────────────────────────────────────────────

// InviteMember POST /groups/:id/invite-member
// Body: {"user_id": "...", "encrypted_key": "..."}
func (h *GroupsHandler) InviteMember(c *gin.Context) {
	groupID := c.Param("id")
	callerID, _ := c.Get("user_id")

	var role string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, callerID,
	).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group owners or admins may invite members"})
		return
	}

	var req struct {
		UserID       string `json:"user_id" binding:"required"`
		EncryptedKey string `json:"encrypted_key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Fetch current key version
	var keyVersion int
	h.db.QueryRow(c.Request.Context(),
		`SELECT key_version FROM groups WHERE id = $1`, groupID,
	).Scan(&keyVersion)

	// Add member
	_, err = h.db.Exec(c.Request.Context(), `
		INSERT INTO group_members (group_id, user_id, role, joined_at)
		VALUES ($1, $2, 'member', now())
		ON CONFLICT (group_id, user_id) DO NOTHING
	`, groupID, req.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add member"})
		return
	}

	// Store their encrypted key if provided
	if req.EncryptedKey != "" {
		h.db.Exec(c.Request.Context(), `
			INSERT INTO group_member_keys (group_id, user_id, key_version, encrypted_key, updated_at)
			VALUES ($1, $2, $3, $4, now())
			ON CONFLICT (group_id, user_id, key_version)
			DO UPDATE SET encrypted_key = EXCLUDED.encrypted_key, updated_at = now()
		`, groupID, req.UserID, keyVersion, req.EncryptedKey)
	}

	c.JSON(http.StatusOK, gin.H{"message": "member invited"})
}

// RemoveMember DELETE /groups/:id/members/:userId
func (h *GroupsHandler) RemoveMember(c *gin.Context) {
	groupID := c.Param("id")
	targetUserID := c.Param("userId")
	callerID, _ := c.Get("user_id")

	var role string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, callerID,
	).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group owners or admins may remove members"})
		return
	}

	_, err = h.db.Exec(c.Request.Context(),
		`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove member"})
		return
	}

	// Trigger automatic key rotation on next admin open
	h.db.Exec(c.Request.Context(),
		`UPDATE groups SET key_rotation_needed = true WHERE id = $1`, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "member removed"})
}

// UpdateGroupSettings PATCH /groups/:id/settings
// Body: {"chat_enabled": true, "forum_enabled": false, "vault_enabled": true}
func (h *GroupsHandler) UpdateGroupSettings(c *gin.Context) {
	groupID := c.Param("id")
	callerID, _ := c.Get("user_id")

	var role string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, callerID,
	).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group owners or admins may change settings"})
		return
	}

	var req struct {
		ChatEnabled  *bool `json:"chat_enabled"`
		ForumEnabled *bool `json:"forum_enabled"`
		VaultEnabled *bool `json:"vault_enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Build dynamic UPDATE (only fields provided)
	setClauses := []string{}
	args := []interface{}{}
	argIdx := 1

	if req.ChatEnabled != nil {
		setClauses = append(setClauses, fmt.Sprintf("chat_enabled = $%d", argIdx))
		args = append(args, *req.ChatEnabled)
		argIdx++
	}
	if req.ForumEnabled != nil {
		setClauses = append(setClauses, fmt.Sprintf("forum_enabled = $%d", argIdx))
		args = append(args, *req.ForumEnabled)
		argIdx++
	}
	if req.VaultEnabled != nil {
		setClauses = append(setClauses, fmt.Sprintf("vault_enabled = $%d", argIdx))
		args = append(args, *req.VaultEnabled)
		argIdx++
	}

	if len(setClauses) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no settings provided"})
		return
	}

	query := fmt.Sprintf(
		"UPDATE groups SET %s WHERE id = $%d",
		strings.Join(setClauses, ", "),
		argIdx,
	)
	args = append(args, groupID)

	if _, err := h.db.Exec(c.Request.Context(), query, args...); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update settings: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "settings updated"})
}

