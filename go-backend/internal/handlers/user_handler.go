package handlers

import (
	"context"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
	"github.com/rs/zerolog/log"
)

type UserHandler struct {
	repo                *repository.UserRepository
	postRepo            *repository.PostRepository
	notificationService *services.NotificationService
	assetService        *services.AssetService
}

func NewUserHandler(repo *repository.UserRepository, postRepo *repository.PostRepository, notificationService *services.NotificationService, assetService *services.AssetService) *UserHandler {
	return &UserHandler{
		repo:                repo,
		postRepo:            postRepo,
		notificationService: notificationService,
		assetService:        assetService,
	}
}

func (h *UserHandler) GetProfile(c *gin.Context) {
	userID := c.Param("id")
	handle, handleExists := c.GetQuery("handle")

	var profile *models.Profile
	var err error

	if userID != "" {
		profile, err = h.repo.GetProfileByID(c.Request.Context(), userID)
	} else if handleExists {
		if handle == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Handle cannot be empty"})
			return
		}
		profile, err = h.repo.GetProfileByHandle(c.Request.Context(), handle)
	} else {
		// Fallback to current authenticated user
		if val, exists := c.Get("user_id"); exists {
			userID = val.(string)
			profile, err = h.repo.GetProfileByID(c.Request.Context(), userID)
		}
	}

	if err != nil || profile == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Profile not found"})
		return
	}

	// Use the profile ID for subsequent lookups
	actualUserID := profile.ID.String()

	// Get stats
	stats, _ := h.repo.GetProfileStats(c.Request.Context(), actualUserID)

	// Check follow status if authenticated
	isFollowing := false
	isFollowedBy := false
	followStatus := ""
	if currentUserID, exists := c.Get("user_id"); exists && currentUserID.(string) != actualUserID {
		var err error
		isFollowing, err = h.repo.IsFollowing(c.Request.Context(), currentUserID.(string), actualUserID)
		if err != nil {
			log.Error().Err(err).Msg("Failed to check isFollowing")
		}
		isFollowedBy, err = h.repo.IsFollowing(c.Request.Context(), actualUserID, currentUserID.(string))
		if err != nil {
			log.Error().Err(err).Msg("Failed to check isFollowedBy")
		}
		followStatus, _ = h.repo.GetFollowStatus(c.Request.Context(), currentUserID.(string), actualUserID)
	}

	// Sign URLs
	if profile.AvatarURL != nil {
		signed := h.assetService.SignImageURL(*profile.AvatarURL)
		profile.AvatarURL = &signed
	}
	if profile.CoverURL != nil {
		signed := h.assetService.SignImageURL(*profile.CoverURL)
		profile.CoverURL = &signed
	}

	c.JSON(http.StatusOK, gin.H{
		"profile":        profile,
		"stats":          stats,
		"is_following":   isFollowing,
		"is_followed_by": isFollowedBy,
		"is_friend":      isFollowing && isFollowedBy,
		"follow_status":  followStatus,
		"is_private":     profile.IsPrivate,
	})
}

func (h *UserHandler) Follow(c *gin.Context) {
	followerID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	followingID := c.Param("id")
	if followingID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	status, err := h.repo.FollowUser(c.Request.Context(), followerID.(string), followingID)
	if err != nil {
		if strings.Contains(err.Error(), "cannot follow self") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot follow self"})
			return
		}
		if strings.Contains(err.Error(), "23503") || strings.Contains(err.Error(), "target profile not found") { // FK Violation or custom error
			c.JSON(http.StatusNotFound, gin.H{"error": "User to follow not found"})
			return
		}
		log.Error().Err(err).Msg("Failed to follow user")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to follow user", "details": err.Error()})
		return
	}

	// Send Notification
	if h.notificationService != nil {
		go func(targetID string, actorID string, isPending bool) {
			_ = h.notificationService.NotifyFollow(context.Background(), targetID, actorID, isPending)
		}(followingID, followerID.(string), status == "pending")
	}

	c.JSON(http.StatusOK, gin.H{"message": "Follow update successful", "status": status})
}

func (h *UserHandler) Unfollow(c *gin.Context) {
	followerID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	followingID := c.Param("id")
	if followingID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	if err := h.repo.UnfollowUser(c.Request.Context(), followerID.(string), followingID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unfollow user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Unfollowed successfully"})
}
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req struct {
		Handle              *string  `json:"handle"`
		DisplayName         *string  `json:"display_name"`
		Bio                 *string  `json:"bio"`
		AvatarURL           *string  `json:"avatar_url"`
		CoverURL            *string  `json:"cover_url"`
		Location            *string  `json:"location"`
		Website             *string  `json:"website"`
		Interests           []string `json:"interests"`
		IdentityKey         *string  `json:"identity_key"`
		RegistrationID      *int     `json:"registration_id"`
		EncryptedPrivateKey *string  `json:"encrypted_private_key"`
		IsPrivate           *bool    `json:"is_private"`
		IsOfficial          *bool    `json:"is_official"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate handle if being changed
	if req.Handle != nil {
		handleCheck := services.ValidateUsernameWithDB(c.Request.Context(), h.repo.Pool(), *req.Handle)
		if handleCheck.Violation != services.UsernameOK {
			status := http.StatusBadRequest
			if handleCheck.Violation == services.UsernameReserved {
				status = http.StatusForbidden
			}
			c.JSON(status, gin.H{"error": handleCheck.Message})
			return
		}
	}

	// Validate display name if being changed
	if req.DisplayName != nil {
		nameCheck := services.ValidateDisplayName(*req.DisplayName)
		if nameCheck.Violation != services.UsernameOK {
			c.JSON(http.StatusBadRequest, gin.H{"error": nameCheck.Message})
			return
		}
	}

	profile := &models.Profile{
		ID:                  userID,
		Handle:              req.Handle,
		DisplayName:         req.DisplayName,
		Bio:                 req.Bio,
		AvatarURL:           req.AvatarURL,
		CoverURL:            req.CoverURL,
		Location:            req.Location,
		Website:             req.Website,
		Interests:           req.Interests,
		IdentityKey:         req.IdentityKey,
		RegistrationID:      req.RegistrationID,
		EncryptedPrivateKey: req.EncryptedPrivateKey,
		IsPrivate:           req.IsPrivate,
		IsOfficial:          req.IsOfficial,
	}

	err := h.repo.UpdateProfile(c.Request.Context(), profile)
	if err != nil {
		// Log error
		log.Error().Err(err).Msg("Failed to update profile")

		// Check for duplicate handle
		if strings.Contains(err.Error(), "23505") {
			c.JSON(http.StatusConflict, gin.H{"error": "Handle already taken"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile", "details": err.Error()})
		return
	}

	updated, _ := h.repo.GetProfileByID(c.Request.Context(), userID.String())
	c.JSON(http.StatusOK, gin.H{"profile": updated})
}

func (h *UserHandler) GetSavedPosts(c *gin.Context) {
	currentUserID := c.GetString("user_id") // Authenticated user
	targetID := c.Param("id")

	if targetID == "" || targetID == "me" {
		targetID = currentUserID
	}

	// TODO: Add privacy check here if viewing another user's saved posts

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	// Check viewer's NSFW preference
	showNSFW := false
	if settings, err := h.repo.GetUserSettings(c.Request.Context(), currentUserID); err == nil && settings.NSFWEnabled != nil {
		showNSFW = *settings.NSFWEnabled
	}

	posts, err := h.postRepo.GetSavedPosts(c.Request.Context(), targetID, limit, offset, showNSFW)
	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch saved posts")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch saved posts"})
		return
	}
	// Sign URLs
	for i := range posts {
		if posts[i].ImageURL != nil {
			signed := h.assetService.SignImageURL(*posts[i].ImageURL)
			posts[i].ImageURL = &signed
		}
		if posts[i].VideoURL != nil {
			signed := h.assetService.SignVideoURL(*posts[i].VideoURL)
			posts[i].VideoURL = &signed
		}
		if posts[i].ThumbnailURL != nil {
			signed := h.assetService.SignImageURL(*posts[i].ThumbnailURL)
			posts[i].ThumbnailURL = &signed
		}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *UserHandler) GetLikedPosts(c *gin.Context) {
	userID := c.GetString("user_id")
	limit := 20
	offset := 0

	// Check viewer's NSFW preference
	showNSFW := false
	if settings, err := h.repo.GetUserSettings(c.Request.Context(), userID); err == nil && settings.NSFWEnabled != nil {
		showNSFW = *settings.NSFWEnabled
	}

	posts, err := h.postRepo.GetLikedPosts(c.Request.Context(), userID, limit, offset, showNSFW)
	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch liked posts")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch liked posts"})
		return
	}
	// Sign URLs
	for i := range posts {
		if posts[i].ImageURL != nil {
			signed := h.assetService.SignImageURL(*posts[i].ImageURL)
			posts[i].ImageURL = &signed
		}
		if posts[i].VideoURL != nil {
			signed := h.assetService.SignVideoURL(*posts[i].VideoURL)
			posts[i].VideoURL = &signed
		}
		if posts[i].ThumbnailURL != nil {
			signed := h.assetService.SignImageURL(*posts[i].ThumbnailURL)
			posts[i].ThumbnailURL = &signed
		}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *UserHandler) AcceptFollowRequest(c *gin.Context) {
	userIdStr, _ := c.Get("user_id")
	requesterId := c.Param("id")

	if err := h.repo.AcceptFollowRequest(c.Request.Context(), userIdStr.(string), requesterId); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to accept follow request"})
		return
	}

	// Harmony & Notifications
	if h.notificationService != nil {
		go func(targetID, actorID string) {
			// 1. Update Harmony Scores (Mutual gain)
			_ = h.repo.UpdateHarmonyScore(context.Background(), targetID, 2)
			_ = h.repo.UpdateHarmonyScore(context.Background(), actorID, 2)

			// 2. Send Notification to requester
			_ = h.notificationService.NotifyFollowAccepted(context.Background(), actorID, targetID)
		}(userIdStr.(string), requesterId)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Follow request accepted"})
}

func (h *UserHandler) GetPendingFollowRequests(c *gin.Context) {
	userIdStr, _ := c.Get("user_id")

	requests, err := h.repo.GetPendingFollowRequests(c.Request.Context(), userIdStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch pending follow requests"})
		return
	}

	// Sign URLs for avatars in requests
	for i := range requests {
		if avatar, ok := requests[i]["avatar_url"].(string); ok && avatar != "" {
			requests[i]["avatar_url"] = h.assetService.SignImageURL(avatar)
		}
	}

	c.JSON(http.StatusOK, gin.H{"requests": requests})
}

func (h *UserHandler) RejectFollowRequest(c *gin.Context) {
	userIdStr, _ := c.Get("user_id")
	requesterId := c.Param("id")

	if err := h.repo.RejectFollowRequest(c.Request.Context(), userIdStr.(string), requesterId); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reject follow request"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Follow request rejected"})
}

func (h *UserHandler) BlockUser(c *gin.Context) {
	blockerID, _ := c.Get("user_id")
	blockedID := c.Param("id")
	actorIP := c.ClientIP()

	if err := h.repo.BlockUser(c.Request.Context(), blockerID.(string), blockedID, actorIP); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to block user"})
		return
	}

	// Also unfollow automatically
	_ = h.repo.UnfollowUser(c.Request.Context(), blockerID.(string), blockedID)
	_ = h.repo.UnfollowUser(c.Request.Context(), blockedID, blockerID.(string))

	c.JSON(http.StatusOK, gin.H{"message": "User blocked"})
}

func (h *UserHandler) ReportUser(c *gin.Context) {
	reporterID, _ := c.Get("user_id")

	var input struct {
		TargetUserID  string `json:"target_user_id" binding:"required"`
		PostID        string `json:"post_id"`
		CommentID     string `json:"comment_id"`
		ViolationType string `json:"violation_type" binding:"required"`
		Description   string `json:"description"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rID, _ := uuid.Parse(reporterID.(string))
	tID, _ := uuid.Parse(input.TargetUserID)

	report := &models.Report{
		ReporterID:    rID,
		TargetUserID:  tID,
		ViolationType: input.ViolationType,
		Description:   input.Description,
	}

	if input.PostID != "" {
		pID, _ := uuid.Parse(input.PostID)
		report.PostID = &pID
	}
	if input.CommentID != "" {
		cID, _ := uuid.Parse(input.CommentID)
		report.CommentID = &cID
	}

	if err := h.repo.CreateReport(c.Request.Context(), report); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create report"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Report submitted successfully"})
}

func (h *UserHandler) UnblockUser(c *gin.Context) {
	blockerID, _ := c.Get("user_id")
	blockedID := c.Param("id")

	if err := h.repo.UnblockUser(c.Request.Context(), blockerID.(string), blockedID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unblock user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User unblocked"})
}

func (h *UserHandler) GetBlockedUsers(c *gin.Context) {
	userID, _ := c.Get("user_id")

	blocked, err := h.repo.GetBlockedUsers(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch blocked users"})
		return
	}

	// Sign URLs
	for i := range blocked {
		if blocked[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*blocked[i].AvatarURL)
			blocked[i].AvatarURL = &signed
		}
	}

	c.JSON(http.StatusOK, gin.H{"users": blocked})
}

func (h *UserHandler) BlockUserByHandle(c *gin.Context) {
	actorID, _ := c.Get("user_id")
	actorIP := c.ClientIP()

	var input struct {
		Handle string `json:"handle" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Handle is required"})
		return
	}

	if err := h.repo.BlockUserByHandle(c.Request.Context(), actorID.(string), input.Handle, actorIP); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to block user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User blocked by handle"})
}

func (h *UserHandler) GetTrustState(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	state, err := h.repo.GetTrustState(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch trust state"})
		return
	}

	c.JSON(http.StatusOK, state)
}

// ========================================================================
// Social Graph: Followers & Following
// ========================================================================

// GetFollowers returns the list of users following the specified user
func (h *UserHandler) GetFollowers(c *gin.Context) {
	targetUserID := c.Param("id")
	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	followers, err := h.repo.GetFollowers(c.Request.Context(), targetUserID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch followers"})
		return
	}

	// Sign avatar URLs
	for i := range followers {
		if followers[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*followers[i].AvatarURL)
			followers[i].AvatarURL = &signed
		}
	}

	c.JSON(http.StatusOK, gin.H{"followers": followers, "count": len(followers)})
}

// GetFollowing returns the list of users the specified user is following
func (h *UserHandler) GetFollowing(c *gin.Context) {
	targetUserID := c.Param("id")
	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	following, err := h.repo.GetFollowing(c.Request.Context(), targetUserID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch following"})
		return
	}

	// Sign avatar URLs
	for i := range following {
		if following[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*following[i].AvatarURL)
			following[i].AvatarURL = &signed
		}
	}

	c.JSON(http.StatusOK, gin.H{"following": following, "count": len(following)})
}

// ========================================================================
// Circle (Close Friends) Management
// ========================================================================

// AddToCircle adds a user to the current user's circle
func (h *UserHandler) AddToCircle(c *gin.Context) {
	userID, _ := c.Get("user_id")
	memberID := c.Param("id")

	if err := h.repo.AddToCircle(c.Request.Context(), userID.(string), memberID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User added to circle"})
}

// RemoveFromCircle removes a user from the current user's circle
func (h *UserHandler) RemoveFromCircle(c *gin.Context) {
	userID, _ := c.Get("user_id")
	memberID := c.Param("id")

	if err := h.repo.RemoveFromCircle(c.Request.Context(), userID.(string), memberID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove from circle"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User removed from circle"})
}

// GetCircleMembers returns all members of the current user's circle
func (h *UserHandler) GetCircleMembers(c *gin.Context) {
	userID, _ := c.Get("user_id")

	members, err := h.repo.GetCircleMembers(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch circle members"})
		return
	}

	// Sign avatar URLs
	for i := range members {
		if members[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*members[i].AvatarURL)
			members[i].AvatarURL = &signed
		}
	}

	c.JSON(http.StatusOK, gin.H{"members": members, "count": len(members)})
}

// ========================================================================
// Data Export (Portability)
// ========================================================================

// ExportData streams user data as JSON for portability/GDPR compliance
func (h *UserHandler) ExportData(c *gin.Context) {
	userID, _ := c.Get("user_id")

	exportData, err := h.repo.ExportUserData(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate export"})
		return
	}

	// Sign all image/video URLs in posts
	for i := range exportData.Posts {
		if exportData.Posts[i].ImageURL != nil {
			signed := h.assetService.SignImageURL(*exportData.Posts[i].ImageURL)
			exportData.Posts[i].ImageURL = &signed
		}
		if exportData.Posts[i].VideoURL != nil {
			signed := h.assetService.SignVideoURL(*exportData.Posts[i].VideoURL)
			exportData.Posts[i].VideoURL = &signed
		}
	}

	// Set headers for file download
	c.Header("Content-Disposition", "attachment; filename=sojorn_data_export.json")
	c.Header("Content-Type", "application/json")
	c.JSON(http.StatusOK, exportData)
}
