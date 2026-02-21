// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

type GroupHandler struct {
	pool     *pgxpool.Pool
	notifSvc *services.NotificationService
}

func NewGroupHandler(pool *pgxpool.Pool, notifSvc *services.NotificationService) *GroupHandler {
	return &GroupHandler{pool: pool, notifSvc: notifSvc}
}

// ═══════════════════════════════════════════════════════════════════════
// MEMBERSHIP HELPERS
// ═══════════════════════════════════════════════════════════════════════

func (h *GroupHandler) requireMembership(c *gin.Context) (userID, groupID uuid.UUID, role string, ok bool) {
	uid, _ := c.Get("user_id")
	userID, err := uuid.Parse(uid.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return userID, groupID, "", false
	}
	groupID, err = uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return userID, groupID, "", false
	}
	err = h.pool.QueryRow(c.Request.Context(),
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, userID).Scan(&role)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a member of this group"})
		return userID, groupID, "", false
	}
	return userID, groupID, role, true
}

func isAdminOrOwner(role string) bool {
	return role == "owner" || role == "admin"
}

// ═══════════════════════════════════════════════════════════════════════
// GROUP POSTS (Feed)
// ═══════════════════════════════════════════════════════════════════════

// ListGroupPosts returns paginated posts for a group
func (h *GroupHandler) ListGroupPosts(c *gin.Context) {
	_, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit > 50 {
		limit = 50
	}

	uid, _ := c.Get("user_id")
	userID, _ := uuid.Parse(uid.(string))

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT gp.id, gp.group_id, gp.author_id, gp.body, COALESCE(gp.image_url, '') AS image_url,
		       gp.like_count, gp.comment_count, gp.is_pinned, gp.created_at,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url,
		       EXISTS(SELECT 1 FROM group_post_likes WHERE group_post_id = gp.id AND user_id = $3) AS liked_by_me
		FROM group_posts gp
		JOIN profiles p ON p.id = gp.author_id
		WHERE gp.group_id = $1 AND gp.is_deleted = FALSE
		ORDER BY gp.is_pinned DESC, gp.created_at DESC
		LIMIT $2 OFFSET $4
	`, groupID, limit, userID, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch posts"})
		return
	}
	defer rows.Close()

	var posts []gin.H
	for rows.Next() {
		var id, gid, aid uuid.UUID
		var body, imageURL, handle, displayName, avatarURL string
		var likeCount, commentCount int
		var isPinned, likedByMe bool
		var createdAt time.Time
		if err := rows.Scan(&id, &gid, &aid, &body, &imageURL, &likeCount, &commentCount, &isPinned, &createdAt,
			&handle, &displayName, &avatarURL, &likedByMe); err != nil {
			continue
		}
		posts = append(posts, gin.H{
			"id": id, "group_id": gid, "author_id": aid,
			"body": body, "image_url": imageURL,
			"like_count": likeCount, "comment_count": commentCount,
			"is_pinned": isPinned, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
			"liked_by_me": likedByMe,
		})
	}
	if posts == nil {
		posts = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// CreateGroupPost creates a new post in the group
func (h *GroupHandler) CreateGroupPost(c *gin.Context) {
	userID, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	var req struct {
		Body     string `json:"body"`
		ImageURL string `json:"image_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Body == "" && req.ImageURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body or image_url required"})
		return
	}

	var postID uuid.UUID
	var createdAt time.Time
	err := h.pool.QueryRow(c.Request.Context(), `
		INSERT INTO group_posts (group_id, author_id, body, image_url)
		VALUES ($1, $2, $3, NULLIF($4, ''))
		RETURNING id, created_at
	`, groupID, userID, req.Body, req.ImageURL).Scan(&postID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create post"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"post": gin.H{
		"id": postID, "group_id": groupID, "author_id": userID,
		"body": req.Body, "image_url": req.ImageURL,
		"like_count": 0, "comment_count": 0, "created_at": createdAt,
	}})

	// Notify all group members in background
	if h.notifSvc != nil {
		go func() {
			bgCtx := context.Background()
			var groupName string
			h.pool.QueryRow(bgCtx, `SELECT name FROM groups WHERE id = $1`, groupID).Scan(&groupName)
			rows, err := h.pool.Query(bgCtx, `SELECT user_id FROM group_members WHERE group_id = $1`, groupID)
			if err != nil {
				return
			}
			defer rows.Close()
			var memberIDs []string
			for rows.Next() {
				var uid uuid.UUID
				if err := rows.Scan(&uid); err == nil {
					memberIDs = append(memberIDs, uid.String())
				}
			}
			h.notifSvc.NotifyGroupPost(bgCtx, userID.String(), postID.String(), groupID.String(), groupName, memberIDs)
		}()
	}
}

// ToggleGroupPostLike toggles a like on a group post
func (h *GroupHandler) ToggleGroupPostLike(c *gin.Context) {
	userID, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	postID, err := uuid.Parse(c.Param("postId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post ID"})
		return
	}

	ctx := c.Request.Context()
	var exists bool
	h.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM group_post_likes WHERE group_post_id = $1 AND user_id = $2)`,
		postID, userID).Scan(&exists)

	if exists {
		h.pool.Exec(ctx, `DELETE FROM group_post_likes WHERE group_post_id = $1 AND user_id = $2`, postID, userID)
		h.pool.Exec(ctx, `UPDATE group_posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = $1`, postID)
		c.JSON(http.StatusOK, gin.H{"liked": false})
	} else {
		h.pool.Exec(ctx, `INSERT INTO group_post_likes (group_post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, postID, userID)
		h.pool.Exec(ctx, `UPDATE group_posts SET like_count = like_count + 1 WHERE id = $1`, postID)
		c.JSON(http.StatusOK, gin.H{"liked": true})

		// Notify post author
		if h.notifSvc != nil {
			go func() {
				bgCtx := context.Background()
				var authorID uuid.UUID
				var groupName string
				h.pool.QueryRow(bgCtx, `
					SELECT gp.author_id, COALESCE(g.name, '') FROM group_posts gp
					JOIN groups g ON g.id = gp.group_id
					WHERE gp.id = $1`, postID).Scan(&authorID, &groupName)
				h.notifSvc.NotifyGroupLike(bgCtx, authorID.String(), userID.String(), postID.String(), groupID.String(), groupName)
			}()
		}
	}
}

// ListGroupPostComments returns comments for a group post
func (h *GroupHandler) ListGroupPostComments(c *gin.Context) {
	_, _, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	postID, err := uuid.Parse(c.Param("postId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post ID"})
		return
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT gc.id, gc.post_id, gc.author_id, gc.body, gc.created_at,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_post_comments gc
		JOIN profiles p ON p.id = gc.author_id
		WHERE gc.post_id = $1 AND gc.is_deleted = FALSE
		ORDER BY gc.created_at ASC
		LIMIT 100
	`, postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch comments"})
		return
	}
	defer rows.Close()

	var comments []gin.H
	for rows.Next() {
		var id, pid, aid uuid.UUID
		var body, handle, displayName, avatarURL string
		var createdAt time.Time
		if err := rows.Scan(&id, &pid, &aid, &body, &createdAt, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		comments = append(comments, gin.H{
			"id": id, "post_id": pid, "author_id": aid, "body": body, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		})
	}
	if comments == nil {
		comments = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

// CreateGroupPostComment adds a comment to a group post
func (h *GroupHandler) CreateGroupPostComment(c *gin.Context) {
	userID, _, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	postID, err := uuid.Parse(c.Param("postId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post ID"})
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body required"})
		return
	}

	ctx := c.Request.Context()
	var commentID uuid.UUID
	var createdAt time.Time
	err = h.pool.QueryRow(ctx, `
		INSERT INTO group_post_comments (post_id, author_id, body)
		VALUES ($1, $2, $3) RETURNING id, created_at
	`, postID, userID, req.Body).Scan(&commentID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create comment"})
		return
	}

	// Bump comment count
	h.pool.Exec(ctx, `UPDATE group_posts SET comment_count = comment_count + 1 WHERE id = $1`, postID)

	c.JSON(http.StatusCreated, gin.H{"comment": gin.H{
		"id": commentID, "post_id": postID, "author_id": userID,
		"body": req.Body, "created_at": createdAt,
	}})

	// Notify post author
	if h.notifSvc != nil {
		go func() {
			bgCtx := context.Background()
			var authorID, groupID uuid.UUID
			var groupName string
			h.pool.QueryRow(bgCtx, `
				SELECT gp.author_id, gp.group_id, COALESCE(g.name, '') FROM group_posts gp
				JOIN groups g ON g.id = gp.group_id
				WHERE gp.id = $1`, postID).Scan(&authorID, &groupID, &groupName)
			h.notifSvc.NotifyGroupComment(bgCtx, authorID.String(), userID.String(), postID.String(), groupID.String(), groupName)
		}()
	}
}

// ═══════════════════════════════════════════════════════════════════════
// GROUP MESSAGES (Chat)
// ═══════════════════════════════════════════════════════════════════════

// ListGroupMessages returns paginated chat messages
func (h *GroupHandler) ListGroupMessages(c *gin.Context) {
	_, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit > 100 {
		limit = 100
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT gm.id, gm.group_id, gm.author_id, gm.body, gm.created_at,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_messages gm
		JOIN profiles p ON p.id = gm.author_id
		WHERE gm.group_id = $1 AND gm.is_deleted = FALSE
		ORDER BY gm.created_at DESC
		LIMIT $2 OFFSET $3
	`, groupID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch messages"})
		return
	}
	defer rows.Close()

	var messages []gin.H
	for rows.Next() {
		var id, gid, aid uuid.UUID
		var body, handle, displayName, avatarURL string
		var createdAt time.Time
		if err := rows.Scan(&id, &gid, &aid, &body, &createdAt, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		messages = append(messages, gin.H{
			"id": id, "group_id": gid, "author_id": aid, "body": body, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		})
	}
	if messages == nil {
		messages = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"messages": messages})
}

// SendGroupMessage sends a chat message
func (h *GroupHandler) SendGroupMessage(c *gin.Context) {
	userID, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body required"})
		return
	}

	var msgID uuid.UUID
	var createdAt time.Time
	err := h.pool.QueryRow(c.Request.Context(), `
		INSERT INTO group_messages (group_id, author_id, body)
		VALUES ($1, $2, $3) RETURNING id, created_at
	`, groupID, userID, req.Body).Scan(&msgID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": gin.H{
		"id": msgID, "group_id": groupID, "author_id": userID,
		"body": req.Body, "created_at": createdAt,
	}})
}

// ═══════════════════════════════════════════════════════════════════════
// GROUP FORUM (Threads + Replies)
// ═══════════════════════════════════════════════════════════════════════

// ListGroupThreads returns paginated forum threads
func (h *GroupHandler) ListGroupThreads(c *gin.Context) {
	_, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "30"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit > 50 {
		limit = 50
	}

	category := c.Query("category")

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT t.id, t.group_id, t.author_id, t.title, t.body,
		       t.reply_count, t.is_pinned, t.is_locked, t.last_activity_at, t.created_at,
		       COALESCE(t.category, '') AS category,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_forum_threads t
		JOIN profiles p ON p.id = t.author_id
		WHERE t.group_id = $1 AND t.is_deleted = FALSE
		  AND ($4::text = '' OR t.category = $4)
		ORDER BY t.is_pinned DESC, t.last_activity_at DESC
		LIMIT $2 OFFSET $3
	`, groupID, limit, offset, category)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch threads"})
		return
	}
	defer rows.Close()

	var threads []gin.H
	for rows.Next() {
		var id, gid, aid uuid.UUID
		var title, body, cat, handle, displayName, avatarURL string
		var replyCount int
		var isPinned, isLocked bool
		var lastActivity, createdAt time.Time
		if err := rows.Scan(&id, &gid, &aid, &title, &body, &replyCount, &isPinned, &isLocked, &lastActivity, &createdAt,
			&cat, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		threads = append(threads, gin.H{
			"id": id, "group_id": gid, "author_id": aid,
			"title": title, "body": body, "category": cat,
			"reply_count": replyCount,
			"is_pinned":   isPinned, "is_locked": isLocked,
			"last_activity_at": lastActivity, "created_at": createdAt,
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		})
	}
	if threads == nil {
		threads = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"threads": threads})
}

// CreateGroupThread creates a new forum thread
func (h *GroupHandler) CreateGroupThread(c *gin.Context) {
	userID, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	var req struct {
		Title    string `json:"title"`
		Body     string `json:"body"`
		Category string `json:"category"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title required"})
		return
	}

	var threadID uuid.UUID
	var createdAt time.Time
	err := h.pool.QueryRow(c.Request.Context(), `
		INSERT INTO group_forum_threads (group_id, author_id, title, body, category)
		VALUES ($1, $2, $3, $4, NULLIF($5, '')) RETURNING id, created_at
	`, groupID, userID, req.Title, req.Body, req.Category).Scan(&threadID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create thread"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"thread": gin.H{
		"id": threadID, "group_id": groupID, "author_id": userID,
		"title": req.Title, "body": req.Body, "category": req.Category,
		"reply_count": 0, "created_at": createdAt,
	}})

	// Notify all group members about the new thread
	if h.notifSvc != nil {
		go func() {
			bgCtx := context.Background()
			var groupName string
			h.pool.QueryRow(bgCtx, `SELECT name FROM groups WHERE id = $1`, groupID).Scan(&groupName)
			rows, err := h.pool.Query(bgCtx, `SELECT user_id FROM group_members WHERE group_id = $1`, groupID)
			if err != nil {
				return
			}
			defer rows.Close()
			var memberIDs []string
			for rows.Next() {
				var uid uuid.UUID
				if err := rows.Scan(&uid); err == nil {
					memberIDs = append(memberIDs, uid.String())
				}
			}
			h.notifSvc.NotifyGroupThread(bgCtx, userID.String(), threadID.String(), groupID.String(), groupName, memberIDs)
		}()
	}
}

// GetGroupThread returns a single thread with its replies
func (h *GroupHandler) GetGroupThread(c *gin.Context) {
	_, _, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	threadID, err := uuid.Parse(c.Param("threadId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid thread ID"})
		return
	}

	ctx := c.Request.Context()

	// Get thread
	var id, gid, aid uuid.UUID
	var title, body, cat, handle, displayName, avatarURL string
	var replyCount int
	var isPinned, isLocked bool
	var lastActivity, createdAt time.Time
	err = h.pool.QueryRow(ctx, `
		SELECT t.id, t.group_id, t.author_id, t.title, t.body,
		       t.reply_count, t.is_pinned, t.is_locked, t.last_activity_at, t.created_at,
		       COALESCE(t.category, '') AS category,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_forum_threads t
		JOIN profiles p ON p.id = t.author_id
		WHERE t.id = $1 AND t.is_deleted = FALSE
	`, threadID).Scan(&id, &gid, &aid, &title, &body, &replyCount, &isPinned, &isLocked, &lastActivity, &createdAt,
		&cat, &handle, &displayName, &avatarURL)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "thread not found"})
		return
	}

	thread := gin.H{
		"id": id, "group_id": gid, "author_id": aid,
		"title": title, "body": body, "category": cat,
		"reply_count": replyCount,
		"is_pinned":   isPinned, "is_locked": isLocked,
		"last_activity_at": lastActivity, "created_at": createdAt,
		"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
	}

	// Get replies
	rows, err := h.pool.Query(ctx, `
		SELECT r.id, r.thread_id, r.author_id, r.body, r.created_at,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_forum_replies r
		JOIN profiles p ON p.id = r.author_id
		WHERE r.thread_id = $1 AND r.is_deleted = FALSE
		ORDER BY r.created_at ASC
		LIMIT 200
	`, threadID)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"thread": thread, "replies": []gin.H{}})
		return
	}
	defer rows.Close()

	var replies []gin.H
	for rows.Next() {
		var rid, tid, raid uuid.UUID
		var rbody, rhandle, rdisplayName, ravatarURL string
		var rcreatedAt time.Time
		if err := rows.Scan(&rid, &tid, &raid, &rbody, &rcreatedAt, &rhandle, &rdisplayName, &ravatarURL); err != nil {
			continue
		}
		replies = append(replies, gin.H{
			"id": rid, "thread_id": tid, "author_id": raid, "body": rbody, "created_at": rcreatedAt,
			"author_handle": rhandle, "author_display_name": rdisplayName, "author_avatar_url": ravatarURL,
		})
	}
	if replies == nil {
		replies = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"thread": thread, "replies": replies})
}

// CreateGroupThreadReply adds a reply to a forum thread
func (h *GroupHandler) CreateGroupThreadReply(c *gin.Context) {
	userID, _, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	threadID, err := uuid.Parse(c.Param("threadId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid thread ID"})
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body required"})
		return
	}

	ctx := c.Request.Context()

	// Check thread exists and not locked
	var isLocked bool
	err = h.pool.QueryRow(ctx, `SELECT is_locked FROM group_forum_threads WHERE id = $1 AND is_deleted = FALSE`, threadID).Scan(&isLocked)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "thread not found"})
		return
	}
	if isLocked {
		c.JSON(http.StatusForbidden, gin.H{"error": "thread is locked"})
		return
	}

	var replyID uuid.UUID
	var createdAt time.Time
	err = h.pool.QueryRow(ctx, `
		INSERT INTO group_forum_replies (thread_id, author_id, body)
		VALUES ($1, $2, $3) RETURNING id, created_at
	`, threadID, userID, req.Body).Scan(&replyID, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create reply"})
		return
	}

	// Bump reply count and last_activity
	h.pool.Exec(ctx, `
		UPDATE group_forum_threads SET reply_count = reply_count + 1, last_activity_at = NOW()
		WHERE id = $1
	`, threadID)

	c.JSON(http.StatusCreated, gin.H{"reply": gin.H{
		"id": replyID, "thread_id": threadID, "author_id": userID,
		"body": req.Body, "created_at": createdAt,
	}})

	// Notify thread author
	if h.notifSvc != nil {
		go func() {
			bgCtx := context.Background()
			var threadAuthorID, groupID uuid.UUID
			var groupName string
			h.pool.QueryRow(bgCtx, `
				SELECT t.author_id, t.group_id, COALESCE(g.name, '') FROM group_forum_threads t
				JOIN groups g ON g.id = t.group_id
				WHERE t.id = $1`, threadID).Scan(&threadAuthorID, &groupID, &groupName)
			h.notifSvc.NotifyGroupReply(bgCtx, threadAuthorID.String(), userID.String(), threadID.String(), groupID.String(), groupName)
		}()
	}
}

// ═══════════════════════════════════════════════════════════════════════
// MEMBERS
// ═══════════════════════════════════════════════════════════════════════

// ListGroupMembers returns all members of a group
func (h *GroupHandler) ListGroupMembers(c *gin.Context) {
	_, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT gm.user_id, gm.role, gm.joined_at,
		       p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM group_members gm
		JOIN profiles p ON p.id = gm.user_id
		WHERE gm.group_id = $1
		ORDER BY
			CASE gm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 WHEN 'moderator' THEN 2 ELSE 3 END,
			gm.joined_at ASC
	`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch members"})
		return
	}
	defer rows.Close()

	var members []gin.H
	for rows.Next() {
		var uid uuid.UUID
		var role, handle, displayName, avatarURL string
		var joinedAt time.Time
		if err := rows.Scan(&uid, &role, &joinedAt, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		members = append(members, gin.H{
			"user_id": uid, "role": role, "joined_at": joinedAt,
			"handle": handle, "display_name": displayName, "avatar_url": avatarURL,
		})
	}
	if members == nil {
		members = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"members": members})
}

// RemoveGroupMember removes a member (owner/admin only)
func (h *GroupHandler) RemoveGroupMember(c *gin.Context) {
	_, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if !isAdminOrOwner(role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only owner or admin can remove members"})
		return
	}

	targetID, err := uuid.Parse(c.Param("memberId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member ID"})
		return
	}

	ctx := c.Request.Context()

	// Can't remove owner
	var targetRole string
	err = h.pool.QueryRow(ctx, `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`, groupID, targetID).Scan(&targetRole)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if targetRole == "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot remove the group owner"})
		return
	}

	_, err = h.pool.Exec(ctx, `DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`, groupID, targetID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove member"})
		return
	}

	// Update member count
	h.pool.Exec(ctx, `UPDATE groups SET member_count = (SELECT COUNT(*) FROM group_members WHERE group_id = $1) WHERE id = $1`, groupID)

	c.JSON(http.StatusOK, gin.H{"status": "removed"})
}

// UpdateMemberRole changes a member's role (owner only)
func (h *GroupHandler) UpdateMemberRole(c *gin.Context) {
	_, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the owner can change roles"})
		return
	}

	targetID, err := uuid.Parse(c.Param("memberId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member ID"})
		return
	}

	var req struct {
		Role string `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if req.Role != "admin" && req.Role != "moderator" && req.Role != "member" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be admin, moderator, or member"})
		return
	}

	_, err = h.pool.Exec(c.Request.Context(),
		`UPDATE group_members SET role = $3 WHERE group_id = $1 AND user_id = $2 AND role != 'owner'`,
		groupID, targetID, req.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update role"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "updated", "new_role": req.Role})
}

// LeaveGroup removes the current user from the group
func (h *GroupHandler) LeaveGroup(c *gin.Context) {
	userID, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if role == "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "owner cannot leave; transfer ownership first or delete the group"})
		return
	}

	ctx := c.Request.Context()
	_, err := h.pool.Exec(ctx, `DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`, groupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to leave group"})
		return
	}

	h.pool.Exec(ctx, `UPDATE groups SET member_count = (SELECT COUNT(*) FROM group_members WHERE group_id = $1) WHERE id = $1`, groupID)

	c.JSON(http.StatusOK, gin.H{"status": "left"})
}

// ═══════════════════════════════════════════════════════════════════════
// GROUP SETTINGS
// ═══════════════════════════════════════════════════════════════════════

// UpdateGroup updates group name, description, or settings
func (h *GroupHandler) UpdateGroup(c *gin.Context) {
	_, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if !isAdminOrOwner(role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only owner or admin can update group settings"})
		return
	}

	var req struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		Settings    *string `json:"settings"` // JSON string
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	ctx := c.Request.Context()
	if req.Name != nil && *req.Name != "" {
		h.pool.Exec(ctx, `UPDATE groups SET name = $2, updated_at = NOW() WHERE id = $1`, groupID, *req.Name)
	}
	if req.Description != nil {
		h.pool.Exec(ctx, `UPDATE groups SET description = $2, updated_at = NOW() WHERE id = $1`, groupID, *req.Description)
	}
	if req.Settings != nil {
		h.pool.Exec(ctx, `UPDATE groups SET settings = $2::jsonb, updated_at = NOW() WHERE id = $1`, groupID, *req.Settings)
	}

	c.JSON(http.StatusOK, gin.H{"status": "updated"})
}

// DeleteGroup permanently deletes a group (owner only)
func (h *GroupHandler) DeleteGroup(c *gin.Context) {
	_, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the owner can delete a group"})
		return
	}

	ctx := c.Request.Context()
	_, err := h.pool.Exec(ctx, `UPDATE groups SET is_active = FALSE, updated_at = NOW() WHERE id = $1`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// InviteToGroup adds a member to a non-encrypted group
func (h *GroupHandler) InviteToGroup(c *gin.Context) {
	inviterID, groupID, role, ok := h.requireMembership(c)
	if !ok {
		return
	}
	if !isAdminOrOwner(role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "only owner or admin can invite"})
		return
	}

	var req struct {
		UserID string `json:"user_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	inviteeID, err := uuid.Parse(req.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user_id"})
		return
	}

	ctx := c.Request.Context()

	// Check user exists
	var exists bool
	h.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM profiles WHERE id = $1)`, inviteeID).Scan(&exists)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	_, err = h.pool.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (group_id, user_id) DO NOTHING
	`, groupID, inviteeID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to invite"})
		return
	}

	h.pool.Exec(ctx, `UPDATE groups SET member_count = (SELECT COUNT(*) FROM group_members WHERE group_id = $1) WHERE id = $1`, groupID)

	c.JSON(http.StatusOK, gin.H{"status": "invited"})

	// Notify invited user
	if h.notifSvc != nil {
		go func() {
			bgCtx := context.Background()
			var groupName string
			h.pool.QueryRow(bgCtx, `SELECT name FROM groups WHERE id = $1`, groupID).Scan(&groupName)
			h.notifSvc.NotifyGroupInvite(bgCtx, inviteeID.String(), inviterID.String(), groupID.String(), groupName)
		}()
	}
}

// SearchUsersForInvite searches for users by handle to invite
func (h *GroupHandler) SearchUsersForInvite(c *gin.Context) {
	_, groupID, _, ok := h.requireMembership(c)
	if !ok {
		return
	}

	query := c.Query("q")
	if len(query) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query must be at least 2 characters"})
		return
	}

	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT p.id, p.handle, COALESCE(p.display_name, '') AS display_name, COALESCE(p.avatar_url, '') AS avatar_url
		FROM profiles p
		WHERE (p.handle ILIKE $1 OR p.display_name ILIKE $1)
		  AND p.id NOT IN (SELECT user_id FROM group_members WHERE group_id = $2)
		LIMIT 20
	`, fmt.Sprintf("%%%s%%", query), groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}
	defer rows.Close()

	var users []gin.H
	for rows.Next() {
		var uid uuid.UUID
		var handle, displayName, avatarURL string
		if err := rows.Scan(&uid, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		users = append(users, gin.H{
			"id": uid, "handle": handle, "display_name": displayName, "avatar_url": avatarURL,
		})
	}
	if users == nil {
		users = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"users": users})
}
