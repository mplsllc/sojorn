package handlers

import (
	"database/sql"
	"net/http"
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
