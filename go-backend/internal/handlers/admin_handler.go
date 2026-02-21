package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"golang.org/x/crypto/bcrypt"
)

type AdminHandler struct {
	pool                    *pgxpool.Pool
	moderationService       *services.ModerationService
	appealService           *services.AppealService
	emailService            *services.EmailService
	sightEngineService      *services.SightEngineService
	officialAccountsService *services.OfficialAccountsService
	linkPreviewService      *services.LinkPreviewService
	localAIService          *services.LocalAIService
	jwtSecret               string
	s3Client                *s3.Client
	mediaBucket             string
	videoBucket             string
	imgDomain               string
	vidDomain               string
}

func NewAdminHandler(pool *pgxpool.Pool, moderationService *services.ModerationService, appealService *services.AppealService, emailService *services.EmailService, sightEngineService *services.SightEngineService, officialAccountsService *services.OfficialAccountsService, linkPreviewService *services.LinkPreviewService, localAIService *services.LocalAIService, jwtSecret string, s3Client *s3.Client, mediaBucket string, videoBucket string, imgDomain string, vidDomain string) *AdminHandler {
	return &AdminHandler{
		pool:                    pool,
		moderationService:       moderationService,
		appealService:           appealService,
		emailService:            emailService,
		sightEngineService:      sightEngineService,
		officialAccountsService: officialAccountsService,
		linkPreviewService:      linkPreviewService,
		localAIService:          localAIService,
		jwtSecret:               jwtSecret,
		s3Client:                s3Client,
		mediaBucket:             mediaBucket,
		videoBucket:             videoBucket,
		imgDomain:               imgDomain,
		vidDomain:               vidDomain,
	}
}

// ──────────────────────────────────────────────
// Admin Login (invisible ALTCHA verification)
// ──────────────────────────────────────────────

type AdminLoginRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required"`
	AltchaToken string `json:"altcha_token"`
}

func (h *AdminHandler) AdminLogin(c *gin.Context) {
	ctx := c.Request.Context()

	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	// Verify ALTCHA token
	altchaService := services.NewAltchaService(h.jwtSecret)
	remoteIP := c.ClientIP()
	altchaResp, err := altchaService.VerifyToken(req.AltchaToken, remoteIP)
	if err != nil {
		log.Error().Err(err).Msg("Admin login: ALTCHA verification failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Security verification failed"})
		return
	}

	if !altchaResp.Verified {
		errorMsg := altchaService.GetErrorMessage(altchaResp.Error)
		log.Warn().Str("email", req.Email).Str("error", errorMsg).Msg("Admin login: ALTCHA validation failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": errorMsg})
		return
	}

	// Look up user
	var userID uuid.UUID
	var passwordHash, status string
	err = h.pool.QueryRow(ctx,
		`SELECT id, encrypted_password, COALESCE(status, 'active') FROM users WHERE email = $1 AND deleted_at IS NULL`,
		req.Email).Scan(&userID, &passwordHash, &status)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	if status != "active" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Account is not active"})
		return
	}

	// Check admin role
	var role string
	err = h.pool.QueryRow(ctx,
		`SELECT COALESCE(role, 'user') FROM profiles WHERE id = $1`, userID).Scan(&role)
	if err != nil || role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Admin access required"})
		return
	}

	// Generate JWT
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  userID.String(),
		"exp":  time.Now().Add(24 * time.Hour).Unix(),
		"role": "authenticated",
	})
	tokenString, err := token.SignedString([]byte(h.jwtSecret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	// Get profile info
	var handle, displayName string
	var avatarURL *string
	h.pool.QueryRow(ctx,
		`SELECT handle, display_name, avatar_url FROM profiles WHERE id = $1`, userID).Scan(&handle, &displayName, &avatarURL)

	c.JSON(http.StatusOK, gin.H{
		"access_token": tokenString,
		"user": gin.H{
			"id":           userID,
			"email":        req.Email,
			"handle":       handle,
			"display_name": displayName,
			"avatar_url":   avatarURL,
			"role":         role,
		},
	})
}

// ──────────────────────────────────────────────
// Dashboard / Stats
// ──────────────────────────────────────────────

func (h *AdminHandler) GetDashboardStats(c *gin.Context) {
	ctx := c.Request.Context()

	stats := gin.H{}

	// Total users
	var totalUsers, activeUsers, suspendedUsers, bannedUsers int
	err := h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM public.profiles`).Scan(&totalUsers)
	if err != nil {
		log.Error().Err(err).Msg("Failed to count users")
	}
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE status = 'active'`).Scan(&activeUsers)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE status = 'suspended'`).Scan(&suspendedUsers)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE status = 'banned'`).Scan(&bannedUsers)

	// Total posts
	var totalPosts, activePosts, flaggedPosts, removedPosts int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts`).Scan(&totalPosts)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE status = 'active'`).Scan(&activePosts)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE status = 'flagged'`).Scan(&flaggedPosts)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE status = 'removed'`).Scan(&removedPosts)

	// Moderation
	var pendingFlags, reviewedFlags int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM moderation_flags WHERE status = 'pending'`).Scan(&pendingFlags)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM moderation_flags WHERE status != 'pending'`).Scan(&reviewedFlags)

	// Appeals
	var pendingAppeals, approvedAppeals, rejectedAppeals int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_appeals WHERE status = 'pending'`).Scan(&pendingAppeals)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_appeals WHERE status = 'approved'`).Scan(&approvedAppeals)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_appeals WHERE status = 'rejected'`).Scan(&rejectedAppeals)

	// New users today
	var newUsersToday int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE`).Scan(&newUsersToday)

	// New posts today
	var newPostsToday int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE created_at >= CURRENT_DATE`).Scan(&newPostsToday)

	// Reports
	var pendingReports int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM reports WHERE status = 'pending'`).Scan(&pendingReports)

	stats["users"] = gin.H{
		"total":     totalUsers,
		"active":    activeUsers,
		"suspended": suspendedUsers,
		"banned":    bannedUsers,
		"new_today": newUsersToday,
	}
	stats["posts"] = gin.H{
		"total":     totalPosts,
		"active":    activePosts,
		"flagged":   flaggedPosts,
		"removed":   removedPosts,
		"new_today": newPostsToday,
	}
	stats["moderation"] = gin.H{
		"pending_flags":  pendingFlags,
		"reviewed_flags": reviewedFlags,
	}
	stats["appeals"] = gin.H{
		"pending":  pendingAppeals,
		"approved": approvedAppeals,
		"rejected": rejectedAppeals,
	}
	stats["reports"] = gin.H{
		"pending": pendingReports,
	}

	c.JSON(http.StatusOK, stats)
}

// GetGrowthStats returns user/post growth over time for charts
func (h *AdminHandler) GetGrowthStats(c *gin.Context) {
	ctx := c.Request.Context()
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))
	if days > 365 {
		days = 365
	}

	// User growth
	userRows, err := h.pool.Query(ctx, `
		SELECT DATE(created_at) as day, COUNT(*) as count
		FROM users
		WHERE created_at >= NOW() - $1::int * INTERVAL '1 day'
		GROUP BY DATE(created_at)
		ORDER BY day
	`, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch growth stats"})
		return
	}
	defer userRows.Close()

	var userGrowth []gin.H
	for userRows.Next() {
		var day time.Time
		var count int
		if err := userRows.Scan(&day, &count); err == nil {
			userGrowth = append(userGrowth, gin.H{"date": day.Format("2006-01-02"), "count": count})
		}
	}

	// Post growth
	postRows, err := h.pool.Query(ctx, `
		SELECT DATE(created_at) as day, COUNT(*) as count
		FROM posts
		WHERE created_at >= NOW() - $1::int * INTERVAL '1 day'
		GROUP BY DATE(created_at)
		ORDER BY day
	`, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch post growth"})
		return
	}
	defer postRows.Close()

	var postGrowth []gin.H
	for postRows.Next() {
		var day time.Time
		var count int
		if err := postRows.Scan(&day, &count); err == nil {
			postGrowth = append(postGrowth, gin.H{"date": day.Format("2006-01-02"), "count": count})
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"user_growth": userGrowth,
		"post_growth": postGrowth,
		"days":        days,
	})
}

// ──────────────────────────────────────────────
// User Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListUsers(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	search := c.Query("search")
	statusFilter := c.Query("status")
	roleFilter := c.Query("role")

	if limit > 200 {
		limit = 200
	}

	query := `
		SELECT u.id, u.email, u.status, u.created_at,
		       p.handle, p.display_name, p.avatar_url, p.role, p.is_official, p.is_private, p.strikes
		FROM users u
		LEFT JOIN profiles p ON u.id = p.id
		WHERE u.deleted_at IS NULL
	`
	args := []interface{}{}
	argIdx := 1

	if search != "" {
		query += fmt.Sprintf(` AND (p.handle ILIKE $%d OR p.display_name ILIKE $%d OR u.email ILIKE $%d)`, argIdx, argIdx, argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if statusFilter != "" {
		query += fmt.Sprintf(` AND u.status = $%d`, argIdx)
		args = append(args, statusFilter)
		argIdx++
	}
	if roleFilter != "" {
		query += fmt.Sprintf(` AND p.role = $%d`, argIdx)
		args = append(args, roleFilter)
		argIdx++
	}

	// Count total
	countQuery := "SELECT COUNT(*) FROM (" + query + ") sub"
	var total int
	h.pool.QueryRow(ctx, countQuery, args...).Scan(&total)

	query += fmt.Sprintf(` ORDER BY u.created_at DESC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list users")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list users"})
		return
	}
	defer rows.Close()

	var users []gin.H
	for rows.Next() {
		var id uuid.UUID
		var email, status string
		var createdAt time.Time
		var handle, displayName, avatarURL, role *string
		var isOfficial, isPrivate *bool
		var strikes *int

		if err := rows.Scan(&id, &email, &status, &createdAt, &handle, &displayName, &avatarURL, &role, &isOfficial, &isPrivate, &strikes); err != nil {
			log.Error().Err(err).Msg("Failed to scan user row")
			continue
		}

		users = append(users, gin.H{
			"id":           id,
			"email":        email,
			"status":       status,
			"created_at":   createdAt,
			"handle":       handle,
			"display_name": displayName,
			"avatar_url":   avatarURL,
			"role":         role,
			"is_official":  isOfficial,
			"is_private":   isPrivate,
			"strikes":      strikes,
		})
	}

	if users == nil {
		users = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"users":  users,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	ctx := c.Request.Context()
	userID := c.Param("id")

	// User + profile details
	var id uuid.UUID
	var email, status string
	var createdAt time.Time
	var lastLogin *time.Time
	var handle, displayName, bio, avatarURL, coverURL, role, location, website, originCountry *string
	var isOfficial, isPrivate, isVerified *bool
	var strikes int
	var beaconEnabled, hasCompletedOnboarding bool

	err := h.pool.QueryRow(ctx, `
		SELECT u.id, u.email, u.status, u.created_at, u.last_login,
		       p.handle, p.display_name, p.bio, p.avatar_url, p.cover_url,
		       p.role, p.is_official, p.is_private, p.is_verified, p.strikes,
		       p.beacon_enabled, p.location, p.website, p.origin_country, p.has_completed_onboarding
		FROM users u
		LEFT JOIN profiles p ON u.id = p.id
		WHERE u.id = $1::uuid
	`, userID).Scan(
		&id, &email, &status, &createdAt, &lastLogin,
		&handle, &displayName, &bio, &avatarURL, &coverURL,
		&role, &isOfficial, &isPrivate, &isVerified, &strikes,
		&beaconEnabled, &location, &website, &originCountry, &hasCompletedOnboarding,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Counts
	var followerCount, followingCount, postCount int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM follows WHERE following_id = $1::uuid AND status = 'accepted'`, userID).Scan(&followerCount)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM follows WHERE follower_id = $1::uuid AND status = 'accepted'`, userID).Scan(&followingCount)
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE author_id = $1::uuid AND deleted_at IS NULL`, userID).Scan(&postCount)

	// Violation count
	var violationCount int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_violations WHERE user_id = $1::uuid`, userID).Scan(&violationCount)

	// Report count (received)
	var reportCount int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM reports WHERE target_user_id = $1::uuid`, userID).Scan(&reportCount)

	c.JSON(http.StatusOK, gin.H{
		"id": id, "email": email, "status": status, "created_at": createdAt, "last_login": lastLogin,
		"handle": handle, "display_name": displayName, "bio": bio, "avatar_url": avatarURL, "cover_url": coverURL,
		"role": role, "is_official": isOfficial, "is_private": isPrivate, "is_verified": isVerified,
		"strikes": strikes, "beacon_enabled": beaconEnabled, "location": location, "website": website,
		"origin_country": originCountry, "has_completed_onboarding": hasCompletedOnboarding,
		"follower_count": followerCount, "following_count": followingCount, "post_count": postCount,
		"violation_count": violationCount, "report_count": reportCount,
	})
}

func (h *AdminHandler) UpdateUserStatus(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	targetUserID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required,oneof=active suspended banned deactivated"`
		Reason string `json:"reason" binding:"required,min=3"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get old status
	var oldStatus string
	h.pool.QueryRow(ctx, `SELECT status FROM users WHERE id = $1::uuid`, targetUserID).Scan(&oldStatus)

	// Update user status
	if req.Status == "banned" {
		_, err := h.pool.Exec(ctx, `UPDATE users SET status = 'banned' WHERE id = $1::uuid`, targetUserID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user status"})
			return
		}
		// Revoke ALL refresh tokens immediately
		h.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1::uuid`, targetUserID)
		// Jail all their content (hidden from feeds until restored)
		h.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1::uuid AND status = 'active' AND deleted_at IS NULL`, targetUserID)
		h.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1::uuid AND status = 'active' AND deleted_at IS NULL`, targetUserID)
	} else if req.Status == "suspended" {
		suspendUntil := time.Now().Add(7 * 24 * time.Hour) // Default 7 day suspension from admin
		_, err := h.pool.Exec(ctx, `UPDATE users SET status = 'suspended', suspended_until = $2 WHERE id = $1::uuid`, targetUserID, suspendUntil)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user status"})
			return
		}
		// Jail all their content during suspension
		h.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1::uuid AND status = 'active' AND deleted_at IS NULL`, targetUserID)
		h.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1::uuid AND status = 'active' AND deleted_at IS NULL`, targetUserID)
	} else {
		_, err := h.pool.Exec(ctx, `UPDATE users SET status = $1, suspended_until = NULL WHERE id = $2::uuid`, req.Status, targetUserID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user status"})
			return
		}
		// If reactivating, restore any jailed content
		if req.Status == "active" {
			h.pool.Exec(ctx, `UPDATE posts SET status = 'active' WHERE author_id = $1::uuid AND status = 'jailed'`, targetUserID)
			h.pool.Exec(ctx, `UPDATE comments SET status = 'active' WHERE author_id = $1::uuid AND status = 'jailed'`, targetUserID)
		}
	}

	// Log status change
	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `
		INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by)
		VALUES ($1::uuid, $2, $3, $4, $5)
	`, targetUserID, oldStatus, req.Status, req.Reason, adminUUID)

	// Send notification email
	if h.emailService != nil {
		var userEmail, displayName string
		h.pool.QueryRow(ctx, `SELECT u.email, COALESCE(p.display_name, '') FROM users u LEFT JOIN profiles p ON p.id = u.id WHERE u.id = $1::uuid`, targetUserID).Scan(&userEmail, &displayName)
		if userEmail != "" {
			go func() {
				switch req.Status {
				case "banned":
					if err := h.emailService.SendBanNotificationEmail(userEmail, displayName, req.Reason); err != nil {
						log.Error().Err(err).Str("user", targetUserID).Msg("Failed to send ban notification email")
					}
				case "suspended":
					if err := h.emailService.SendSuspensionNotificationEmail(userEmail, displayName, req.Reason, "7 days"); err != nil {
						log.Error().Err(err).Str("user", targetUserID).Msg("Failed to send suspension notification email")
					}
				case "active":
					if oldStatus == "banned" || oldStatus == "suspended" {
						reason := req.Reason
						if reason == "" {
							reason = "Your account has been reviewed and restored."
						}
						if err := h.emailService.SendAccountRestoredEmail(userEmail, displayName, reason); err != nil {
							log.Error().Err(err).Str("user", targetUserID).Msg("Failed to send account restored email")
						}
					}
				}
			}()
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "User status updated", "status": req.Status})
}

func (h *AdminHandler) UpdateUserRole(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")

	var req struct {
		Role string `json:"role" binding:"required,oneof=user moderator admin"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx, `UPDATE profiles SET role = $1 WHERE id = $2::uuid`, req.Role, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user role"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User role updated", "role": req.Role})
}

func (h *AdminHandler) UpdateUserVerification(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")

	var req struct {
		IsOfficial bool `json:"is_official"`
		IsVerified bool `json:"is_verified"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx, `UPDATE profiles SET is_official = $1, is_verified = $2 WHERE id = $3::uuid`,
		req.IsOfficial, req.IsVerified, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update verification"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Verification updated"})
}

func (h *AdminHandler) ResetUserStrikes(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")

	_, err := h.pool.Exec(ctx, `UPDATE profiles SET strikes = 0 WHERE id = $1::uuid`, targetUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reset strikes"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Strikes reset"})
}

// AdminUpdateProfile allows full profile editing for official accounts.
func (h *AdminHandler) AdminUpdateProfile(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")

	var req struct {
		Handle      *string `json:"handle"`
		DisplayName *string `json:"display_name"`
		Bio         *string `json:"bio"`
		AvatarURL   *string `json:"avatar_url"`
		CoverURL    *string `json:"cover_url"`
		Location    *string `json:"location"`
		Website     *string `json:"website"`
		Country     *string `json:"origin_country"`
		BirthMonth  *int    `json:"birth_month"`
		BirthYear   *int    `json:"birth_year"`
		IsPrivate   *bool   `json:"is_private"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Build dynamic UPDATE
	sets := []string{}
	args := []interface{}{}
	idx := 1

	addField := func(col string, val interface{}) {
		sets = append(sets, fmt.Sprintf("%s = $%d", col, idx))
		args = append(args, val)
		idx++
	}

	if req.Handle != nil {
		addField("handle", *req.Handle)
	}
	if req.DisplayName != nil {
		addField("display_name", *req.DisplayName)
	}
	if req.Bio != nil {
		addField("bio", *req.Bio)
	}
	if req.AvatarURL != nil {
		addField("avatar_url", *req.AvatarURL)
	}
	if req.CoverURL != nil {
		addField("cover_url", *req.CoverURL)
	}
	if req.Location != nil {
		addField("location", *req.Location)
	}
	if req.Website != nil {
		addField("website", *req.Website)
	}
	if req.Country != nil {
		addField("origin_country", *req.Country)
	}
	if req.BirthMonth != nil {
		addField("birth_month", *req.BirthMonth)
	}
	if req.BirthYear != nil {
		addField("birth_year", *req.BirthYear)
	}
	if req.IsPrivate != nil {
		addField("is_private", *req.IsPrivate)
	}

	if len(sets) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No fields to update"})
		return
	}

	sets = append(sets, fmt.Sprintf("updated_at = $%d", idx))
	args = append(args, time.Now())
	idx++

	query := fmt.Sprintf("UPDATE profiles SET %s WHERE id = $%d::uuid", strings.Join(sets, ", "), idx)
	args = append(args, targetUserID)

	_, err := h.pool.Exec(ctx, query, args...)
	if err != nil {
		log.Error().Err(err).Str("user_id", targetUserID).Msg("Failed to update profile")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Profile updated"})
}

// resolveUserID accepts either a UUID or a handle and returns the user's UUID.
func (h *AdminHandler) resolveUserID(ctx context.Context, input string) (string, error) {
	// If it parses as a UUID, return as-is
	if _, err := uuid.Parse(input); err == nil {
		return input, nil
	}
	// Otherwise, treat as a handle and look it up
	handle := strings.TrimPrefix(input, "@")
	var id uuid.UUID
	err := h.pool.QueryRow(ctx, `SELECT id FROM profiles WHERE handle = $1`, handle).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("user not found: %s", input)
	}
	return id.String(), nil
}

// AdminManageFollow adds or removes follow relationships for official accounts.
func (h *AdminHandler) AdminManageFollow(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")

	var req struct {
		Action   string `json:"action"`   // "add" or "remove"
		UserID   string `json:"user_id"`  // UUID or handle of the other user
		Relation string `json:"relation"` // "follower" (user follows target) or "following" (target follows user)
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Action != "add" && req.Action != "remove" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "action must be 'add' or 'remove'"})
		return
	}
	if req.Relation != "follower" && req.Relation != "following" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "relation must be 'follower' or 'following'"})
		return
	}

	// Resolve handle or UUID to a UUID
	resolvedID, err := h.resolveUserID(ctx, req.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Determine follower_id and following_id
	var followerID, followingID string
	if req.Relation == "follower" {
		followerID = resolvedID
		followingID = targetUserID
	} else {
		followerID = targetUserID
		followingID = resolvedID
	}

	if req.Action == "add" {
		_, err := h.pool.Exec(ctx, `
			INSERT INTO follows (follower_id, following_id, status) VALUES ($1::uuid, $2::uuid, 'accepted')
			ON CONFLICT (follower_id, following_id) DO UPDATE SET status = 'accepted'
		`, followerID, followingID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add follow: " + err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "Follow added"})
	} else {
		_, err := h.pool.Exec(ctx, `DELETE FROM follows WHERE follower_id = $1::uuid AND following_id = $2::uuid`, followerID, followingID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove follow: " + err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "Follow removed"})
	}
}

// AdminListFollows lists followers or following for a user.
func (h *AdminHandler) AdminListFollows(c *gin.Context) {
	ctx := c.Request.Context()
	targetUserID := c.Param("id")
	relation := c.DefaultQuery("relation", "followers") // "followers" or "following"
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))

	var query string
	if relation == "following" {
		query = `
			SELECT p.id, p.handle, p.display_name, p.avatar_url, p.is_official, f.created_at
			FROM follows f JOIN profiles p ON p.id = f.following_id
			WHERE f.follower_id = $1::uuid AND f.status = 'accepted'
			ORDER BY f.created_at DESC LIMIT $2
		`
	} else {
		query = `
			SELECT p.id, p.handle, p.display_name, p.avatar_url, p.is_official, f.created_at
			FROM follows f JOIN profiles p ON p.id = f.follower_id
			WHERE f.following_id = $1::uuid AND f.status = 'accepted'
			ORDER BY f.created_at DESC LIMIT $2
		`
	}

	rows, err := h.pool.Query(ctx, query, targetUserID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list follows"})
		return
	}
	defer rows.Close()

	var users []gin.H
	for rows.Next() {
		var id uuid.UUID
		var handle, displayName *string
		var avatarURL *string
		var isOfficial *bool
		var createdAt time.Time
		if err := rows.Scan(&id, &handle, &displayName, &avatarURL, &isOfficial, &createdAt); err != nil {
			continue
		}
		users = append(users, gin.H{
			"id": id, "handle": handle, "display_name": displayName,
			"avatar_url": avatarURL, "is_official": isOfficial, "followed_at": createdAt,
		})
	}
	if users == nil {
		users = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"users": users, "relation": relation})
}

// ──────────────────────────────────────────────
// Post Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListPosts(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	search := c.Query("search")
	statusFilter := c.Query("status")
	authorFilter := c.Query("author_id")

	if limit > 200 {
		limit = 200
	}

	query := `
		SELECT p.id, p.author_id, p.body, p.status, p.image_url, p.video_url,
		       COALESCE((SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id), 0) AS like_count,
		       COALESCE((SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL), 0) AS comment_count,
		       p.is_beacon, p.visibility, p.created_at,
		       pr.handle, pr.display_name, pr.avatar_url
		FROM posts p
		LEFT JOIN profiles pr ON p.author_id = pr.id
		WHERE p.deleted_at IS NULL
	`
	args := []interface{}{}
	argIdx := 1

	if search != "" {
		query += fmt.Sprintf(` AND p.body ILIKE $%d`, argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if statusFilter != "" {
		query += fmt.Sprintf(` AND p.status = $%d`, argIdx)
		args = append(args, statusFilter)
		argIdx++
	}
	if authorFilter != "" {
		query += fmt.Sprintf(` AND p.author_id = $%d::uuid`, argIdx)
		args = append(args, authorFilter)
		argIdx++
	}

	countQuery := "SELECT COUNT(*) FROM (" + query + ") sub"
	var total int
	h.pool.QueryRow(ctx, countQuery, args...).Scan(&total)

	query += fmt.Sprintf(` ORDER BY p.created_at DESC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list posts")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list posts"})
		return
	}
	defer rows.Close()

	var posts []gin.H
	for rows.Next() {
		var id, authorID uuid.UUID
		var body, status, visibility string
		var imageURL, videoURL *string
		var likeCount, commentCount int
		var isBeacon bool
		var createdAt time.Time
		var authorHandle, authorDisplayName, authorAvatarURL *string

		if err := rows.Scan(&id, &authorID, &body, &status, &imageURL, &videoURL,
			&likeCount, &commentCount, &isBeacon, &visibility, &createdAt,
			&authorHandle, &authorDisplayName, &authorAvatarURL); err != nil {
			log.Error().Err(err).Msg("Failed to scan post row")
			continue
		}

		posts = append(posts, gin.H{
			"id": id, "author_id": authorID, "body": body, "status": status,
			"image_url": imageURL, "video_url": videoURL,
			"like_count": likeCount, "comment_count": commentCount,
			"is_beacon": isBeacon, "visibility": visibility, "created_at": createdAt,
			"author": gin.H{
				"handle": authorHandle, "display_name": authorDisplayName, "avatar_url": authorAvatarURL,
			},
		})
	}

	if posts == nil {
		posts = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"posts":  posts,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *AdminHandler) GetPost(c *gin.Context) {
	ctx := c.Request.Context()
	postID := c.Param("id")

	var id, authorID uuid.UUID
	var body, status, bodyFormat, visibility string
	var imageURL, videoURL, thumbnailURL, toneLabel, beaconType, backgroundID *string
	var cisScore *float64
	var durationMS, likeCount, commentCount int
	var isBeacon, allowChain bool
	var createdAt time.Time
	var editedAt *time.Time
	var authorHandle, authorDisplayName, authorAvatarURL *string

	err := h.pool.QueryRow(ctx, `
		SELECT p.id, p.author_id, p.body, p.status, p.body_format, p.image_url, p.video_url,
		       p.thumbnail_url, p.tone_label, p.cis_score, COALESCE(p.duration_ms, 0),
		       p.background_id, p.is_beacon, p.beacon_type, p.allow_chain, p.visibility,
		       COALESCE((SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id), 0),
		       COALESCE((SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL), 0),
		       p.created_at, p.edited_at,
		       pr.handle, pr.display_name, pr.avatar_url
		FROM posts p
		LEFT JOIN profiles pr ON p.author_id = pr.id
		WHERE p.id = $1::uuid
	`, postID).Scan(
		&id, &authorID, &body, &status, &bodyFormat, &imageURL, &videoURL,
		&thumbnailURL, &toneLabel, &cisScore, &durationMS,
		&backgroundID, &isBeacon, &beaconType, &allowChain, &visibility,
		&likeCount, &commentCount, &createdAt, &editedAt,
		&authorHandle, &authorDisplayName, &authorAvatarURL,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	// Get moderation flags
	flagRows, _ := h.pool.Query(ctx, `
		SELECT id, flag_reason, scores, status, reviewed_by, reviewed_at, created_at
		FROM moderation_flags WHERE post_id = $1::uuid ORDER BY created_at DESC
	`, postID)
	defer flagRows.Close()

	var flags []gin.H
	for flagRows.Next() {
		var fID uuid.UUID
		var fReason, fStatus string
		var fScores []byte
		var fReviewedBy *uuid.UUID
		var fReviewedAt *time.Time
		var fCreatedAt time.Time

		if err := flagRows.Scan(&fID, &fReason, &fScores, &fStatus, &fReviewedBy, &fReviewedAt, &fCreatedAt); err == nil {
			var scores map[string]float64
			json.Unmarshal(fScores, &scores)
			flags = append(flags, gin.H{
				"id": fID, "flag_reason": fReason, "scores": scores, "status": fStatus,
				"reviewed_by": fReviewedBy, "reviewed_at": fReviewedAt, "created_at": fCreatedAt,
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"id": id, "author_id": authorID, "body": body, "status": status, "body_format": bodyFormat,
		"image_url": imageURL, "video_url": videoURL, "thumbnail_url": thumbnailURL,
		"tone_label": toneLabel, "cis_score": cisScore, "duration_ms": durationMS,
		"background_id": backgroundID, "is_beacon": isBeacon, "beacon_type": beaconType,
		"allow_chain": allowChain, "visibility": visibility,
		"like_count": likeCount, "comment_count": commentCount,
		"created_at": createdAt, "edited_at": editedAt,
		"author": gin.H{
			"handle": authorHandle, "display_name": authorDisplayName, "avatar_url": authorAvatarURL,
		},
		"moderation_flags": flags,
	})
}

func (h *AdminHandler) UpdatePostStatus(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	postID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required,oneof=active flagged removed"`
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx, `UPDATE posts SET status = $1 WHERE id = $2::uuid`, req.Status, postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update post status"})
		return
	}

	// Log the action
	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, target_id, details)
		VALUES ($1, $2, 'post', $3::uuid, $4)
	`, adminUUID, "post_status_change", postID, fmt.Sprintf(`{"status":"%s","reason":"%s"}`, req.Status, req.Reason))

	// If post was removed, record a strike and notify the author
	if req.Status == "removed" || req.Status == "flagged" {
		var authorID uuid.UUID
		var authorEmail, displayName string
		err := h.pool.QueryRow(ctx, `
			SELECT p.author_id, u.email, COALESCE(pr.display_name, '')
			FROM posts p
			JOIN users u ON u.id = p.author_id
			LEFT JOIN profiles pr ON pr.id = p.author_id
			WHERE p.id = $1::uuid
		`, postID).Scan(&authorID, &authorEmail, &displayName)

		if err == nil && req.Status == "removed" {
			// Record a strike
			reason := req.Reason
			if reason == "" {
				reason = "Post removed by moderation team"
			}
			h.pool.Exec(ctx, `
				INSERT INTO content_strikes (user_id, category, content_snippet, created_at)
				VALUES ($1, 'moderation', $2, NOW())
			`, authorID, reason)

			// Count strikes
			var strikeCount int
			h.pool.QueryRow(ctx, `
				SELECT COUNT(*) FROM content_strikes
				WHERE user_id = $1 AND created_at > NOW() - INTERVAL '30 days'
			`, authorID).Scan(&strikeCount)

			// Send email notification
			if h.emailService != nil && authorEmail != "" {
				go func() {
					if err := h.emailService.SendContentRemovalEmail(authorEmail, displayName, "post", reason, strikeCount); err != nil {
						log.Error().Err(err).Str("user", authorID.String()).Msg("Failed to send post removal email")
					}
				}()
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post status updated", "status": req.Status})
}

func (h *AdminHandler) DeletePost(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	postID := c.Param("id")

	// Get author info before deleting
	var authorID uuid.UUID
	var authorEmail, displayName string
	h.pool.QueryRow(ctx, `
		SELECT p.author_id, u.email, COALESCE(pr.display_name, '')
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN profiles pr ON pr.id = p.author_id
		WHERE p.id = $1::uuid
	`, postID).Scan(&authorID, &authorEmail, &displayName)

	_, err := h.pool.Exec(ctx, `UPDATE posts SET deleted_at = NOW(), status = 'removed' WHERE id = $1::uuid`, postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete post"})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, target_id, details)
		VALUES ($1, 'admin_delete_post', 'post', $2::uuid, '{}')
	`, adminUUID, postID)

	// Record a strike on the author
	if authorID != uuid.Nil {
		reason := "Post deleted by moderation team"
		h.pool.Exec(ctx, `
			INSERT INTO content_strikes (user_id, category, content_snippet, created_at)
			VALUES ($1, 'moderation', $2, NOW())
		`, authorID, reason)

		var strikeCount int
		h.pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM content_strikes
			WHERE user_id = $1 AND created_at > NOW() - INTERVAL '30 days'
		`, authorID).Scan(&strikeCount)

		if h.emailService != nil && authorEmail != "" {
			go func() {
				if err := h.emailService.SendContentRemovalEmail(authorEmail, displayName, "post", reason, strikeCount); err != nil {
					log.Error().Err(err).Str("user", authorID.String()).Msg("Failed to send post removal email")
				}
			}()
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post deleted"})
}

// ──────────────────────────────────────────────
// Bulk Actions
// ──────────────────────────────────────────────

func (h *AdminHandler) BulkUpdatePosts(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		IDs    []string `json:"ids" binding:"required"`
		Action string   `json:"action" binding:"required"`
		Reason string   `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var affected int64
	for _, id := range req.IDs {
		var err error
		switch req.Action {
		case "remove":
			tag, e := h.pool.Exec(ctx, `UPDATE posts SET status = 'removed' WHERE id = $1::uuid AND deleted_at IS NULL`, id)
			err = e
			affected += tag.RowsAffected()
		case "activate":
			tag, e := h.pool.Exec(ctx, `UPDATE posts SET status = 'active' WHERE id = $1::uuid AND deleted_at IS NULL`, id)
			err = e
			affected += tag.RowsAffected()
		case "delete":
			tag, e := h.pool.Exec(ctx, `UPDATE posts SET deleted_at = NOW(), status = 'removed' WHERE id = $1::uuid`, id)
			err = e
			affected += tag.RowsAffected()
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid action"})
			return
		}
		if err != nil {
			log.Error().Err(err).Str("post_id", id).Msg("Bulk post action failed")
		}
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, details) VALUES ($1, $2, 'post', $3)`,
		adminUUID, "bulk_"+req.Action+"_posts", fmt.Sprintf(`{"count":%d,"reason":"%s"}`, affected, req.Reason))

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("%d posts updated", affected), "affected": affected})
}

func (h *AdminHandler) BulkUpdateUsers(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		IDs    []string `json:"ids" binding:"required"`
		Action string   `json:"action" binding:"required"`
		Reason string   `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var affected int64
	for _, id := range req.IDs {
		var err error
		switch req.Action {
		case "ban":
			tag, e := h.pool.Exec(ctx, `UPDATE users SET status = 'banned' WHERE id = $1::uuid`, id)
			err = e
			affected += tag.RowsAffected()
		case "suspend":
			tag, e := h.pool.Exec(ctx, `UPDATE users SET status = 'suspended' WHERE id = $1::uuid`, id)
			err = e
			affected += tag.RowsAffected()
		case "activate":
			tag, e := h.pool.Exec(ctx, `UPDATE users SET status = 'active' WHERE id = $1::uuid`, id)
			err = e
			affected += tag.RowsAffected()
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid action"})
			return
		}
		if err != nil {
			log.Error().Err(err).Str("user_id", id).Msg("Bulk user action failed")
		}
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, details) VALUES ($1, $2, 'user', $3)`,
		adminUUID, "bulk_"+req.Action+"_users", fmt.Sprintf(`{"count":%d,"reason":"%s"}`, affected, req.Reason))

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("%d users updated", affected), "affected": affected})
}

func (h *AdminHandler) BulkReviewModeration(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		IDs    []string `json:"ids" binding:"required"`
		Action string   `json:"action" binding:"required"`
		Reason string   `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	var affected int64
	for _, id := range req.IDs {
		var newStatus string
		switch req.Action {
		case "approve":
			newStatus = "approved"
		case "dismiss":
			newStatus = "dismissed"
		case "remove_content":
			newStatus = "actioned"
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid action"})
			return
		}
		tag, err := h.pool.Exec(ctx,
			`UPDATE moderation_flags SET status = $1, reviewed_by = $2, reviewed_at = NOW() WHERE id = $3::uuid AND status = 'pending'`,
			newStatus, adminUUID, id)
		if err != nil {
			log.Error().Err(err).Str("flag_id", id).Msg("Bulk moderation action failed")
		}
		affected += tag.RowsAffected()

		if req.Action == "remove_content" {
			h.pool.Exec(ctx, `UPDATE posts SET status = 'removed' WHERE id = (SELECT post_id FROM moderation_flags WHERE id = $1::uuid)`, id)
		}
	}

	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, details) VALUES ($1, $2, 'moderation', $3)`,
		adminUUID, "bulk_"+req.Action+"_moderation", fmt.Sprintf(`{"count":%d}`, affected))

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("%d flags updated", affected), "affected": affected})
}

func (h *AdminHandler) BulkUpdateReports(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		IDs    []string `json:"ids" binding:"required"`
		Action string   `json:"action" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Action != "actioned" && req.Action != "dismissed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid action, must be actioned or dismissed"})
		return
	}

	var affected int64
	for _, id := range req.IDs {
		tag, err := h.pool.Exec(ctx, `UPDATE reports SET status = $1 WHERE id = $2::uuid AND status = 'pending'`, req.Action, id)
		if err != nil {
			log.Error().Err(err).Str("report_id", id).Msg("Bulk report action failed")
		}
		affected += tag.RowsAffected()
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, details) VALUES ($1, $2, 'report', $3)`,
		adminUUID, "bulk_"+req.Action+"_reports", fmt.Sprintf(`{"count":%d}`, affected))

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("%d reports updated", affected), "affected": affected})
}

// ──────────────────────────────────────────────
// Moderation Queue
// ──────────────────────────────────────────────

func (h *AdminHandler) GetModerationQueue(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	statusFilter := c.DefaultQuery("status", "pending")

	if limit > 200 {
		limit = 200
	}

	rows, err := h.pool.Query(ctx, `
		SELECT mf.id, mf.post_id, mf.comment_id, mf.flag_reason, mf.scores,
		       mf.status, mf.reviewed_by, mf.reviewed_at, mf.created_at,
		       p.body as post_body, p.image_url as post_image, p.video_url as post_video, p.author_id as post_author_id,
		       c.body as comment_body, c.author_id as comment_author_id,
		       COALESCE(pr_post.handle, pr_comment.handle) as author_handle,
		       COALESCE(pr_post.display_name, pr_comment.display_name) as author_display_name
		FROM moderation_flags mf
		LEFT JOIN posts p ON mf.post_id = p.id
		LEFT JOIN comments c ON mf.comment_id = c.id
		LEFT JOIN profiles pr_post ON p.author_id = pr_post.id
		LEFT JOIN profiles pr_comment ON c.author_id = pr_comment.id
		WHERE mf.status = $1
		ORDER BY mf.created_at ASC
		LIMIT $2 OFFSET $3
	`, statusFilter, limit, offset)
	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch moderation queue")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch moderation queue"})
		return
	}
	defer rows.Close()

	var total int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM moderation_flags WHERE status = $1`, statusFilter).Scan(&total)

	var items []gin.H
	for rows.Next() {
		var fID uuid.UUID
		var postID, commentID *uuid.UUID
		var flagReason, fStatus string
		var fScores []byte
		var reviewedBy *uuid.UUID
		var reviewedAt *time.Time
		var fCreatedAt time.Time
		var postBody, postImage, postVideo *string
		var postAuthorID, commentAuthorID *uuid.UUID
		var commentBody *string
		var authorHandle, authorDisplayName *string

		if err := rows.Scan(&fID, &postID, &commentID, &flagReason, &fScores,
			&fStatus, &reviewedBy, &reviewedAt, &fCreatedAt,
			&postBody, &postImage, &postVideo, &postAuthorID,
			&commentBody, &commentAuthorID,
			&authorHandle, &authorDisplayName); err != nil {
			log.Error().Err(err).Msg("Failed to scan moderation flag")
			continue
		}

		var scores map[string]float64
		json.Unmarshal(fScores, &scores)

		contentType := "post"
		if commentID != nil {
			contentType = "comment"
		}

		items = append(items, gin.H{
			"id": fID, "post_id": postID, "comment_id": commentID,
			"flag_reason": flagReason, "scores": scores, "status": fStatus,
			"reviewed_by": reviewedBy, "reviewed_at": reviewedAt, "created_at": fCreatedAt,
			"content_type":      contentType,
			"post_body":         postBody,
			"post_image":        postImage,
			"post_video":        postVideo,
			"comment_body":      commentBody,
			"author_handle":     authorHandle,
			"author_name":       authorDisplayName,
			"post_author_id":    postAuthorID,
			"comment_author_id": commentAuthorID,
		})
	}

	if items == nil {
		items = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"items":  items,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *AdminHandler) ReviewModerationFlag(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	flagID := c.Param("id")

	var req struct {
		Action string `json:"action" binding:"required,oneof=approve dismiss remove_content ban_user"`
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	flagUUID, err := uuid.Parse(flagID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid flag ID"})
		return
	}

	switch req.Action {
	case "approve":
		// Content is fine, dismiss the flag
		h.moderationService.UpdateFlagStatus(ctx, flagUUID, "dismissed", adminUUID)

	case "dismiss":
		h.moderationService.UpdateFlagStatus(ctx, flagUUID, "dismissed", adminUUID)

	case "remove_content":
		// Remove the flagged content
		h.moderationService.UpdateFlagStatus(ctx, flagUUID, "actioned", adminUUID)

		// Get the post/comment ID and remove
		var postID, commentID *uuid.UUID
		h.pool.QueryRow(ctx, `SELECT post_id, comment_id FROM moderation_flags WHERE id = $1`, flagUUID).Scan(&postID, &commentID)
		if postID != nil {
			h.pool.Exec(ctx, `UPDATE posts SET status = 'removed', deleted_at = NOW() WHERE id = $1`, postID)
		}
		if commentID != nil {
			h.pool.Exec(ctx, `UPDATE comments SET status = 'removed', deleted_at = NOW() WHERE id = $1`, commentID)
		}

	case "ban_user":
		h.moderationService.UpdateFlagStatus(ctx, flagUUID, "actioned", adminUUID)

		// Get the author and ban them
		var postID, commentID *uuid.UUID
		h.pool.QueryRow(ctx, `SELECT post_id, comment_id FROM moderation_flags WHERE id = $1`, flagUUID).Scan(&postID, &commentID)

		// Remove the flagged content
		if postID != nil {
			h.pool.Exec(ctx, `UPDATE posts SET status = 'removed', deleted_at = NOW() WHERE id = $1`, postID)
		}
		if commentID != nil {
			h.pool.Exec(ctx, `UPDATE comments SET status = 'removed', deleted_at = NOW() WHERE id = $1`, commentID)
		}

		var authorID *uuid.UUID
		if postID != nil {
			h.pool.QueryRow(ctx, `SELECT author_id FROM posts WHERE id = $1`, postID).Scan(&authorID)
		}
		if commentID != nil && authorID == nil {
			h.pool.QueryRow(ctx, `SELECT author_id FROM comments WHERE id = $1`, commentID).Scan(&authorID)
		}
		if authorID != nil {
			// Ban the user
			h.pool.Exec(ctx, `UPDATE users SET status = 'banned' WHERE id = $1`, authorID)
			// Revoke all refresh tokens
			h.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1`, authorID)
			// Jail all their content
			h.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, authorID)
			h.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, authorID)
			// Log status change
			h.pool.Exec(ctx, `INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by) VALUES ($1, 'active', 'banned', $2, $3)`, authorID, req.Reason, adminUUID)
			// Send ban email
			if h.emailService != nil {
				var userEmail, displayName string
				h.pool.QueryRow(ctx, `SELECT u.email, COALESCE(p.display_name, '') FROM users u LEFT JOIN profiles p ON p.id = u.id WHERE u.id = $1`, authorID).Scan(&userEmail, &displayName)
				if userEmail != "" {
					go func() {
						h.emailService.SendBanNotificationEmail(userEmail, displayName, req.Reason)
					}()
				}
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "Flag reviewed", "action": req.Action})
}

// ──────────────────────────────────────────────
// Appeal Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListAppeals(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	statusFilter := c.DefaultQuery("status", "pending")

	if limit > 200 {
		limit = 200
	}

	rows, err := h.pool.Query(ctx, `
		SELECT ua.id, ua.user_violation_id, ua.user_id, ua.appeal_reason, ua.appeal_context,
		       ua.status, ua.reviewed_by, ua.review_decision, ua.reviewed_at, ua.created_at,
		       uv.violation_type, uv.violation_reason, uv.severity_score,
		       mf.flag_reason, mf.scores,
		       p.body as post_body, p.image_url,
		       c.body as comment_body,
		       pr.handle, pr.display_name, pr.avatar_url
		FROM user_appeals ua
		JOIN user_violations uv ON ua.user_violation_id = uv.id
		LEFT JOIN moderation_flags mf ON uv.moderation_flag_id = mf.id
		LEFT JOIN posts p ON mf.post_id = p.id
		LEFT JOIN comments c ON mf.comment_id = c.id
		JOIN profiles pr ON ua.user_id = pr.id
		WHERE ua.status = $1
		ORDER BY ua.created_at ASC
		LIMIT $2 OFFSET $3
	`, statusFilter, limit, offset)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list appeals")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list appeals"})
		return
	}
	defer rows.Close()

	var total int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_appeals WHERE status = $1`, statusFilter).Scan(&total)

	var appeals []gin.H
	for rows.Next() {
		var aID, violationID, userID uuid.UUID
		var appealReason, appealContext, aStatus string
		var reviewedBy *uuid.UUID
		var reviewDecision *string
		var reviewedAt *time.Time
		var aCreatedAt time.Time
		var violationType, violationReason string
		var severityScore float64
		var flagReason *string
		var flagScores []byte
		var postBody, postImage, commentBody *string
		var handle, displayName, avatarURL *string

		if err := rows.Scan(&aID, &violationID, &userID, &appealReason, &appealContext,
			&aStatus, &reviewedBy, &reviewDecision, &reviewedAt, &aCreatedAt,
			&violationType, &violationReason, &severityScore,
			&flagReason, &flagScores,
			&postBody, &postImage, &commentBody,
			&handle, &displayName, &avatarURL); err != nil {
			log.Error().Err(err).Msg("Failed to scan appeal")
			continue
		}

		var scores map[string]float64
		if flagScores != nil {
			json.Unmarshal(flagScores, &scores)
		}

		appeals = append(appeals, gin.H{
			"id": aID, "violation_id": violationID, "user_id": userID,
			"appeal_reason": appealReason, "appeal_context": appealContext,
			"status": aStatus, "reviewed_by": reviewedBy, "review_decision": reviewDecision,
			"reviewed_at": reviewedAt, "created_at": aCreatedAt,
			"violation_type": violationType, "violation_reason": violationReason,
			"severity_score": severityScore, "flag_reason": flagReason, "flag_scores": scores,
			"post_body": postBody, "post_image": postImage, "comment_body": commentBody,
			"user": gin.H{
				"handle": handle, "display_name": displayName, "avatar_url": avatarURL,
			},
		})
	}

	if appeals == nil {
		appeals = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{
		"appeals": appeals,
		"total":   total,
		"limit":   limit,
		"offset":  offset,
	})
}

func (h *AdminHandler) ReviewAppeal(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	appealID := c.Param("id")

	var req struct {
		Decision       string `json:"decision" binding:"required,oneof=approved rejected"`
		ReviewDecision string `json:"review_decision" binding:"required,min=5"`
		RestoreContent bool   `json:"restore_content"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	appealUUID, err := uuid.Parse(appealID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid appeal ID"})
		return
	}

	err = h.appealService.ReviewAppeal(ctx, appealUUID, adminUUID, req.Decision, req.ReviewDecision)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to review appeal"})
		return
	}

	// If approved and restore_content, restore the content
	if req.Decision == "approved" && req.RestoreContent {
		var violationID uuid.UUID
		h.pool.QueryRow(ctx, `SELECT user_violation_id FROM user_appeals WHERE id = $1`, appealUUID).Scan(&violationID)

		var flagID uuid.UUID
		h.pool.QueryRow(ctx, `SELECT moderation_flag_id FROM user_violations WHERE id = $1`, violationID).Scan(&flagID)

		var postID, commentID *uuid.UUID
		h.pool.QueryRow(ctx, `SELECT post_id, comment_id FROM moderation_flags WHERE id = $1`, flagID).Scan(&postID, &commentID)

		if postID != nil {
			h.pool.Exec(ctx, `UPDATE posts SET status = 'active', deleted_at = NULL WHERE id = $1`, postID)
		}
		if commentID != nil {
			h.pool.Exec(ctx, `UPDATE comments SET status = 'active', deleted_at = NULL WHERE id = $1`, commentID)
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "Appeal reviewed", "decision": req.Decision})
}

// ──────────────────────────────────────────────
// Reports Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListReports(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	statusFilter := c.DefaultQuery("status", "pending")

	rows, err := h.pool.Query(ctx, `
		SELECT r.id, r.reporter_id, r.target_user_id, r.post_id, r.comment_id,
		       r.violation_type, r.description, r.status, r.created_at,
		       pr_reporter.handle as reporter_handle,
		       pr_target.handle as target_handle
		FROM reports r
		LEFT JOIN profiles pr_reporter ON r.reporter_id = pr_reporter.id
		LEFT JOIN profiles pr_target ON r.target_user_id = pr_target.id
		WHERE r.status = $1
		ORDER BY r.created_at ASC
		LIMIT $2 OFFSET $3
	`, statusFilter, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list reports"})
		return
	}
	defer rows.Close()

	var total int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM reports WHERE status = $1`, statusFilter).Scan(&total)

	var reports []gin.H
	for rows.Next() {
		var rID, reporterID, targetUserID uuid.UUID
		var postID, commentID *uuid.UUID
		var violationType, description, rStatus string
		var rCreatedAt time.Time
		var reporterHandle, targetHandle *string

		if err := rows.Scan(&rID, &reporterID, &targetUserID, &postID, &commentID,
			&violationType, &description, &rStatus, &rCreatedAt,
			&reporterHandle, &targetHandle); err != nil {
			continue
		}

		reports = append(reports, gin.H{
			"id": rID, "reporter_id": reporterID, "target_user_id": targetUserID,
			"post_id": postID, "comment_id": commentID,
			"violation_type": violationType, "description": description,
			"status": rStatus, "created_at": rCreatedAt,
			"reporter_handle": reporterHandle, "target_handle": targetHandle,
		})
	}

	if reports == nil {
		reports = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"reports": reports, "total": total, "limit": limit, "offset": offset})
}

func (h *AdminHandler) UpdateReportStatus(c *gin.Context) {
	ctx := c.Request.Context()
	reportID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required,oneof=reviewed dismissed actioned"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx, `UPDATE reports SET status = $1 WHERE id = $2::uuid`, req.Status, reportID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update report"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Report updated"})
}

// ──────────────────────────────────────────────
// Capsule Reports
// ──────────────────────────────────────────────

func (h *AdminHandler) ListCapsuleReports(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	statusFilter := c.DefaultQuery("status", "pending")

	rows, err := h.pool.Query(ctx, `
		SELECT cr.id, cr.reporter_id, cr.capsule_id, cr.entry_id,
		       cr.decrypted_sample, cr.reason, cr.status, cr.created_at,
		       g.name  AS capsule_name,
		       p.handle AS reporter_handle
		FROM capsule_reports cr
		JOIN groups  g ON cr.capsule_id = g.id
		JOIN profiles p ON cr.reporter_id = p.id
		WHERE cr.status = $1
		ORDER BY cr.created_at ASC
		LIMIT $2 OFFSET $3
	`, statusFilter, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list capsule reports"})
		return
	}
	defer rows.Close()

	var total int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM capsule_reports WHERE status = $1`, statusFilter).Scan(&total)

	var reports []gin.H
	for rows.Next() {
		var rID, reporterID, capsuleID, entryID uuid.UUID
		var decryptedSample *string
		var reason, status, capsuleName, reporterHandle string
		var createdAt time.Time

		if err := rows.Scan(&rID, &reporterID, &capsuleID, &entryID,
			&decryptedSample, &reason, &status, &createdAt,
			&capsuleName, &reporterHandle); err != nil {
			continue
		}

		reports = append(reports, gin.H{
			"id": rID, "reporter_id": reporterID,
			"capsule_id": capsuleID, "capsule_name": capsuleName,
			"entry_id": entryID, "decrypted_sample": decryptedSample,
			"reason": reason, "status": status,
			"created_at": createdAt, "reporter_handle": reporterHandle,
		})
	}

	if reports == nil {
		reports = []gin.H{}
	}
	c.JSON(http.StatusOK, gin.H{"reports": reports, "total": total, "limit": limit, "offset": offset})
}

func (h *AdminHandler) UpdateCapsuleReportStatus(c *gin.Context) {
	ctx := c.Request.Context()
	reportID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required,oneof=reviewed dismissed actioned"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx,
		`UPDATE capsule_reports SET status = $1, updated_at = NOW() WHERE id = $2::uuid`,
		req.Status, reportID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update report"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Report updated"})
}

// ──────────────────────────────────────────────
// Algorithm / Feed Settings
// ──────────────────────────────────────────────

func (h *AdminHandler) GetAlgorithmConfig(c *gin.Context) {
	ctx := c.Request.Context()

	rows, err := h.pool.Query(ctx, `
		SELECT key, value, description, updated_at
		FROM algorithm_config
		ORDER BY key
	`)
	if err != nil {
		// Table may not exist yet, return defaults
		c.JSON(http.StatusOK, gin.H{
			"config": []gin.H{
				{"key": "feed_recency_weight", "value": "0.4", "description": "Weight for post recency in feed ranking"},
				{"key": "feed_engagement_weight", "value": "0.3", "description": "Weight for engagement metrics"},
				{"key": "feed_harmony_weight", "value": "0.2", "description": "Weight for author harmony score"},
				{"key": "feed_diversity_weight", "value": "0.1", "description": "Weight for content diversity"},
				{"key": "feed_cooling_multiplier", "value": "0.2", "description": "Score multiplier for previously-seen posts (0–1, lower = stronger penalty)"},
				{"key": "feed_diversity_personal_pct", "value": "60", "description": "% of feed from top personal scores"},
				{"key": "feed_diversity_category_pct", "value": "20", "description": "% of feed from under-represented categories"},
				{"key": "feed_diversity_discovery_pct", "value": "20", "description": "% of feed from authors viewer doesn't follow"},
				{"key": "moderation_auto_flag_threshold", "value": "0.7", "description": "AI score threshold for auto-flagging"},
				{"key": "moderation_auto_remove_threshold", "value": "0.95", "description": "AI score threshold for auto-removal"},
			},
		})
		return
	}
	defer rows.Close()

	var configs []gin.H
	for rows.Next() {
		var key, value string
		var description *string
		var updatedAt time.Time
		if err := rows.Scan(&key, &value, &description, &updatedAt); err == nil {
			configs = append(configs, gin.H{
				"key": key, "value": value, "description": description, "updated_at": updatedAt,
			})
		}
	}

	if configs == nil {
		configs = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"config": configs})
}

func (h *AdminHandler) UpdateAlgorithmConfig(c *gin.Context) {
	ctx := c.Request.Context()

	var req struct {
		Key   string `json:"key" binding:"required"`
		Value string `json:"value" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx, `
		INSERT INTO algorithm_config (key, value, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW()
	`, req.Key, req.Value)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update config"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Config updated"})
}

// ──────────────────────────────────────────────
// Categories Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListCategories(c *gin.Context) {
	ctx := c.Request.Context()

	rows, err := h.pool.Query(ctx, `
		SELECT id, slug, name, description, is_sensitive, created_at
		FROM categories ORDER BY name
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list categories"})
		return
	}
	defer rows.Close()

	var categories []gin.H
	for rows.Next() {
		var id uuid.UUID
		var slug, name string
		var description *string
		var isSensitive bool
		var createdAt time.Time

		if err := rows.Scan(&id, &slug, &name, &description, &isSensitive, &createdAt); err == nil {
			categories = append(categories, gin.H{
				"id": id, "slug": slug, "name": name, "description": description,
				"is_sensitive": isSensitive, "created_at": createdAt,
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

func (h *AdminHandler) CreateCategory(c *gin.Context) {
	ctx := c.Request.Context()

	var req struct {
		Slug        string `json:"slug" binding:"required"`
		Name        string `json:"name" binding:"required"`
		Description string `json:"description"`
		IsSensitive bool   `json:"is_sensitive"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var id uuid.UUID
	err := h.pool.QueryRow(ctx, `
		INSERT INTO categories (slug, name, description, is_sensitive)
		VALUES ($1, $2, $3, $4) RETURNING id
	`, req.Slug, req.Name, req.Description, req.IsSensitive).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create category"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id, "message": "Category created"})
}

func (h *AdminHandler) UpdateCategory(c *gin.Context) {
	ctx := c.Request.Context()
	catID := c.Param("id")

	var req struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		IsSensitive *bool  `json:"is_sensitive"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Name != "" {
		h.pool.Exec(ctx, `UPDATE categories SET name = $1 WHERE id = $2::uuid`, req.Name, catID)
	}
	if req.Description != "" {
		h.pool.Exec(ctx, `UPDATE categories SET description = $1 WHERE id = $2::uuid`, req.Description, catID)
	}
	if req.IsSensitive != nil {
		h.pool.Exec(ctx, `UPDATE categories SET is_sensitive = $1 WHERE id = $2::uuid`, *req.IsSensitive, catID)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Category updated"})
}

// ──────────────────────────────────────────────
// System Health
// ──────────────────────────────────────────────

func (h *AdminHandler) GetSystemHealth(c *gin.Context) {
	ctx := c.Request.Context()

	health := gin.H{"status": "healthy"}

	// Database check
	start := time.Now()
	err := h.pool.Ping(ctx)
	dbLatency := time.Since(start).Milliseconds()
	if err != nil {
		health["database"] = gin.H{"status": "unhealthy", "error": err.Error()}
	} else {
		health["database"] = gin.H{"status": "healthy", "latency_ms": dbLatency}
	}

	// Pool stats
	poolStats := h.pool.Stat()
	health["connection_pool"] = gin.H{
		"total":        poolStats.TotalConns(),
		"idle":         poolStats.IdleConns(),
		"acquired":     poolStats.AcquiredConns(),
		"max":          poolStats.MaxConns(),
		"constructing": poolStats.ConstructingConns(),
	}

	// Table sizes
	var dbSize string
	h.pool.QueryRow(ctx, `SELECT pg_size_pretty(pg_database_size('sojorn'))`).Scan(&dbSize)
	health["database_size"] = dbSize

	c.JSON(http.StatusOK, health)
}

// ──────────────────────────────────────────────
// Audit Log
// ──────────────────────────────────────────────

func (h *AdminHandler) GetAuditLog(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	rows, err := h.pool.Query(ctx, `
		SELECT al.id, al.actor_id, al.action, al.target_type, al.target_id, al.details, al.created_at,
		       pr.handle as actor_handle
		FROM audit_log al
		LEFT JOIN profiles pr ON al.actor_id = pr.id
		ORDER BY al.created_at DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		// Table may not exist
		c.JSON(http.StatusOK, gin.H{"entries": []gin.H{}, "total": 0})
		return
	}
	defer rows.Close()

	var entries []gin.H
	for rows.Next() {
		var id uuid.UUID
		var actorID *uuid.UUID
		var action, targetType string
		var targetID *uuid.UUID
		var details *string
		var createdAt time.Time
		var actorHandle *string

		if err := rows.Scan(&id, &actorID, &action, &targetType, &targetID, &details, &createdAt, &actorHandle); err == nil {
			entries = append(entries, gin.H{
				"id": id, "actor_id": actorID, "action": action,
				"target_type": targetType, "target_id": targetID,
				"details": details, "created_at": createdAt, "actor_handle": actorHandle,
			})
		}
	}

	if entries == nil {
		entries = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"entries": entries, "limit": limit, "offset": offset})
}

// ──────────────────────────────────────────────
// R2 Storage Browser
// ──────────────────────────────────────────────

func (h *AdminHandler) GetStorageStats(c *gin.Context) {
	if h.s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "R2 storage not configured"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	type bucketStats struct {
		Name        string `json:"name"`
		ObjectCount int    `json:"object_count"`
		TotalSize   int64  `json:"total_size"`
		Domain      string `json:"domain"`
	}

	getBucketStats := func(bucket, domain string) bucketStats {
		stats := bucketStats{Name: bucket, Domain: domain}
		var continuationToken *string
		for {
			input := &s3.ListObjectsV2Input{
				Bucket:            aws.String(bucket),
				ContinuationToken: continuationToken,
				MaxKeys:           aws.Int32(1000),
			}
			output, err := h.s3Client.ListObjectsV2(ctx, input)
			if err != nil {
				log.Error().Err(err).Str("bucket", bucket).Msg("Failed to list R2 objects for stats")
				break
			}
			for _, obj := range output.Contents {
				stats.ObjectCount++
				stats.TotalSize += aws.ToInt64(obj.Size)
			}
			if !aws.ToBool(output.IsTruncated) {
				break
			}
			continuationToken = output.NextContinuationToken
		}
		return stats
	}

	mediaStats := getBucketStats(h.mediaBucket, h.imgDomain)
	videoStats := getBucketStats(h.videoBucket, h.vidDomain)

	c.JSON(http.StatusOK, gin.H{
		"buckets":       []bucketStats{mediaStats, videoStats},
		"total_objects": mediaStats.ObjectCount + videoStats.ObjectCount,
		"total_size":    mediaStats.TotalSize + videoStats.TotalSize,
	})
}

func (h *AdminHandler) ListStorageObjects(c *gin.Context) {
	if h.s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "R2 storage not configured"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	bucket := c.DefaultQuery("bucket", h.mediaBucket)
	prefix := c.Query("prefix")
	marker := c.Query("cursor")
	limitStr := c.DefaultQuery("limit", "50")
	limit, _ := strconv.Atoi(limitStr)
	if limit > 200 {
		limit = 200
	}

	// Validate bucket
	if bucket != h.mediaBucket && bucket != h.videoBucket {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid bucket name"})
		return
	}

	// Determine public domain
	domain := h.imgDomain
	if bucket == h.videoBucket {
		domain = h.vidDomain
	}

	input := &s3.ListObjectsV2Input{
		Bucket:  aws.String(bucket),
		MaxKeys: aws.Int32(int32(limit)),
	}
	if prefix != "" {
		input.Prefix = aws.String(prefix)
		input.Delimiter = aws.String("/")
	}
	if marker != "" {
		input.ContinuationToken = aws.String(marker)
	}

	output, err := h.s3Client.ListObjectsV2(ctx, input)
	if err != nil {
		log.Error().Err(err).Str("bucket", bucket).Msg("Failed to list R2 objects")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list objects"})
		return
	}

	// Folders (common prefixes)
	var folders []string
	for _, cp := range output.CommonPrefixes {
		folders = append(folders, aws.ToString(cp.Prefix))
	}

	// Objects
	var objects []gin.H
	for _, obj := range output.Contents {
		key := aws.ToString(obj.Key)
		publicURL := fmt.Sprintf("https://%s/%s", domain, key)

		objects = append(objects, gin.H{
			"key":           key,
			"size":          aws.ToInt64(obj.Size),
			"last_modified": obj.LastModified,
			"etag":          strings.Trim(aws.ToString(obj.ETag), "\""),
			"url":           publicURL,
		})
	}

	if objects == nil {
		objects = []gin.H{}
	}
	if folders == nil {
		folders = []string{}
	}

	var nextCursor *string
	if aws.ToBool(output.IsTruncated) {
		nextCursor = output.NextContinuationToken
	}

	c.JSON(http.StatusOK, gin.H{
		"objects":     objects,
		"folders":     folders,
		"bucket":      bucket,
		"prefix":      prefix,
		"next_cursor": nextCursor,
		"count":       len(objects),
	})
}

func (h *AdminHandler) GetStorageObject(c *gin.Context) {
	if h.s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "R2 storage not configured"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	bucket := c.DefaultQuery("bucket", h.mediaBucket)
	key := c.Query("key")
	if key == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "key parameter required"})
		return
	}

	if bucket != h.mediaBucket && bucket != h.videoBucket {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid bucket name"})
		return
	}

	domain := h.imgDomain
	if bucket == h.videoBucket {
		domain = h.vidDomain
	}

	output, err := h.s3Client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Object not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"key":           key,
		"bucket":        bucket,
		"size":          aws.ToInt64(output.ContentLength),
		"content_type":  aws.ToString(output.ContentType),
		"last_modified": output.LastModified,
		"etag":          strings.Trim(aws.ToString(output.ETag), "\""),
		"url":           fmt.Sprintf("https://%s/%s", domain, key),
		"cache_control": aws.ToString(output.CacheControl),
	})
}

func (h *AdminHandler) DeleteStorageObject(c *gin.Context) {
	if h.s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "R2 storage not configured"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	adminID, _ := c.Get("user_id")

	var req struct {
		Bucket string `json:"bucket" binding:"required"`
		Key    string `json:"key" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Bucket != h.mediaBucket && req.Bucket != h.videoBucket {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid bucket name"})
		return
	}

	_, err := h.s3Client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(req.Bucket),
		Key:    aws.String(req.Key),
	})
	if err != nil {
		log.Error().Err(err).Str("bucket", req.Bucket).Str("key", req.Key).Msg("Failed to delete R2 object")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete object"})
		return
	}

	// Audit log
	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, target_id, details)
		VALUES ($1, 'admin_delete_storage_object', 'storage', NULL, $2)
	`, adminUUID, fmt.Sprintf(`{"bucket":"%s","key":"%s"}`, req.Bucket, req.Key))

	c.JSON(http.StatusOK, gin.H{"message": "Object deleted"})
}

// ──────────────────────────────────────────────
// Reserved Usernames Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListReservedUsernames(c *gin.Context) {
	ctx := c.Request.Context()
	category := c.Query("category")
	search := c.Query("search")
	limit := 50
	offset := 0
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 {
		limit = v
	}
	if v, err := strconv.Atoi(c.Query("offset")); err == nil && v >= 0 {
		offset = v
	}

	query := `SELECT id, username, category, reason, created_at FROM reserved_usernames WHERE 1=1`
	args := []interface{}{}
	argIdx := 1

	if category != "" {
		query += fmt.Sprintf(` AND category = $%d`, argIdx)
		args = append(args, category)
		argIdx++
	}
	if search != "" {
		query += fmt.Sprintf(` AND username ILIKE $%d`, argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}

	// Count
	countQuery := strings.Replace(query, "id, username, category, reason, created_at", "COUNT(*)", 1)
	var total int
	h.pool.QueryRow(ctx, countQuery, args...).Scan(&total)

	query += fmt.Sprintf(` ORDER BY username ASC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list reserved usernames"})
		return
	}
	defer rows.Close()

	type ReservedUsername struct {
		ID        string    `json:"id"`
		Username  string    `json:"username"`
		Category  string    `json:"category"`
		Reason    *string   `json:"reason"`
		CreatedAt time.Time `json:"created_at"`
	}
	var items []ReservedUsername
	for rows.Next() {
		var item ReservedUsername
		if err := rows.Scan(&item.ID, &item.Username, &item.Category, &item.Reason, &item.CreatedAt); err == nil {
			items = append(items, item)
		}
	}
	if items == nil {
		items = []ReservedUsername{}
	}
	c.JSON(http.StatusOK, gin.H{"reserved_usernames": items, "total": total})
}

func (h *AdminHandler) AddReservedUsername(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		Username string `json:"username" binding:"required"`
		Category string `json:"category"`
		Reason   string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.Username = strings.ToLower(strings.TrimSpace(req.Username))
	if req.Category == "" {
		req.Category = "custom"
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	_, err := h.pool.Exec(ctx, `
		INSERT INTO reserved_usernames (username, category, reason, added_by)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (username) DO UPDATE SET category = $2, reason = $3
	`, req.Username, req.Category, req.Reason, adminUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add reserved username"})
		return
	}

	// Audit
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, details)
		VALUES ($1, 'admin_reserve_username', 'username', $2)
	`, adminUUID, fmt.Sprintf(`{"username":"%s","category":"%s"}`, req.Username, req.Category))

	c.JSON(http.StatusOK, gin.H{"message": "Username reserved"})
}

func (h *AdminHandler) RemoveReservedUsername(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	id := c.Param("id")

	var username string
	h.pool.QueryRow(ctx, `SELECT username FROM reserved_usernames WHERE id = $1`, id).Scan(&username)

	_, err := h.pool.Exec(ctx, `DELETE FROM reserved_usernames WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove reserved username"})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, details)
		VALUES ($1, 'admin_unreserve_username', 'username', $2)
	`, adminUUID, fmt.Sprintf(`{"username":"%s"}`, username))

	c.JSON(http.StatusOK, gin.H{"message": "Reserved username removed"})
}

func (h *AdminHandler) BulkAddReservedUsernames(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		Usernames []string `json:"usernames" binding:"required"`
		Category  string   `json:"category"`
		Reason    string   `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Category == "" {
		req.Category = "custom"
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	added := 0
	for _, u := range req.Usernames {
		u = strings.ToLower(strings.TrimSpace(u))
		if u == "" {
			continue
		}
		_, err := h.pool.Exec(ctx, `
			INSERT INTO reserved_usernames (username, category, reason, added_by)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (username) DO NOTHING
		`, u, req.Category, req.Reason, adminUUID)
		if err == nil {
			added++
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Added %d reserved usernames", added), "added": added})
}

// ──────────────────────────────────────────────
// Username Claim Requests
// ──────────────────────────────────────────────

func (h *AdminHandler) ListClaimRequests(c *gin.Context) {
	ctx := c.Request.Context()
	status := c.DefaultQuery("status", "pending")
	limit := 50
	offset := 0
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 {
		limit = v
	}
	if v, err := strconv.Atoi(c.Query("offset")); err == nil && v >= 0 {
		offset = v
	}

	var total int
	h.pool.QueryRow(ctx, `SELECT COUNT(*) FROM username_claim_requests WHERE status = $1`, status).Scan(&total)

	rows, err := h.pool.Query(ctx, `
		SELECT id, requested_username, requester_email, requester_name, requester_user_id,
		       organization, justification, proof_url, status, review_notes, reviewed_at, created_at
		FROM username_claim_requests
		WHERE status = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, status, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list claim requests"})
		return
	}
	defer rows.Close()

	type ClaimRequest struct {
		ID                string     `json:"id"`
		RequestedUsername string     `json:"requested_username"`
		RequesterEmail    string     `json:"requester_email"`
		RequesterName     *string    `json:"requester_name"`
		RequesterUserID   *string    `json:"requester_user_id"`
		Organization      *string    `json:"organization"`
		Justification     string     `json:"justification"`
		ProofURL          *string    `json:"proof_url"`
		Status            string     `json:"status"`
		ReviewNotes       *string    `json:"review_notes"`
		ReviewedAt        *time.Time `json:"reviewed_at"`
		CreatedAt         time.Time  `json:"created_at"`
	}

	var items []ClaimRequest
	for rows.Next() {
		var item ClaimRequest
		if err := rows.Scan(
			&item.ID, &item.RequestedUsername, &item.RequesterEmail, &item.RequesterName,
			&item.RequesterUserID, &item.Organization, &item.Justification, &item.ProofURL,
			&item.Status, &item.ReviewNotes, &item.ReviewedAt, &item.CreatedAt,
		); err == nil {
			items = append(items, item)
		}
	}
	if items == nil {
		items = []ClaimRequest{}
	}
	c.JSON(http.StatusOK, gin.H{"claim_requests": items, "total": total})
}

func (h *AdminHandler) ReviewClaimRequest(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	id := c.Param("id")

	var req struct {
		Decision string `json:"decision" binding:"required"` // approved, denied
		Notes    string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Decision != "approved" && req.Decision != "denied" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Decision must be 'approved' or 'denied'"})
		return
	}

	adminUUID, _ := uuid.Parse(adminID.(string))
	_, err := h.pool.Exec(ctx, `
		UPDATE username_claim_requests
		SET status = $1, reviewer_id = $2, review_notes = $3, reviewed_at = NOW(), updated_at = NOW()
		WHERE id = $4
	`, req.Decision, adminUUID, req.Notes, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update claim request"})
		return
	}

	// If approved, remove from reserved list so user can register it
	if req.Decision == "approved" {
		var username string
		h.pool.QueryRow(ctx, `SELECT requested_username FROM username_claim_requests WHERE id = $1`, id).Scan(&username)
		if username != "" {
			h.pool.Exec(ctx, `DELETE FROM reserved_usernames WHERE username = $1`, strings.ToLower(username))
		}
	}

	// Audit
	h.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, action, target_type, target_id, details)
		VALUES ($1, 'admin_review_claim', 'claim_request', $2, $3)
	`, adminUUID, id, fmt.Sprintf(`{"decision":"%s"}`, req.Decision))

	c.JSON(http.StatusOK, gin.H{"message": "Claim request " + req.Decision})
}

// ──────────────────────────────────────────────
// Public: Submit a claim request (no auth required)
// ──────────────────────────────────────────────

func (h *AdminHandler) SubmitClaimRequest(c *gin.Context) {
	ctx := c.Request.Context()

	var req struct {
		RequestedUsername string `json:"requested_username" binding:"required"`
		Email             string `json:"email" binding:"required,email"`
		Name              string `json:"name"`
		Organization      string `json:"organization"`
		Justification     string `json:"justification" binding:"required"`
		ProofURL          string `json:"proof_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check for duplicate pending request
	var existing int
	h.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM username_claim_requests
		WHERE requested_username = $1 AND requester_email = $2 AND status = 'pending'
	`, strings.ToLower(req.RequestedUsername), strings.ToLower(req.Email)).Scan(&existing)
	if existing > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "You already have a pending claim for this username"})
		return
	}

	_, err := h.pool.Exec(ctx, `
		INSERT INTO username_claim_requests (requested_username, requester_email, requester_name, organization, justification, proof_url)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, strings.ToLower(req.RequestedUsername), strings.ToLower(req.Email), req.Name, req.Organization, req.Justification, req.ProofURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to submit claim request"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Your claim request has been submitted and will be reviewed by our team."})
}

// ──────────────────────────────────────────────
// AI Moderation Config
// ──────────────────────────────────────────────

// ListModels returns an empty model list (legacy endpoint, kept for route compatibility).
func (h *AdminHandler) ListModels(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"models": []any{}, "total": 0})
}

// ListLocalModels returns models available on the local Ollama instance.
func (h *AdminHandler) ListLocalModels(c *gin.Context) {
	ctx := c.Request.Context()

	// Query Ollama's /api/tags endpoint for locally available models
	req, err := http.NewRequestWithContext(ctx, "GET", "http://localhost:11434/api/tags", nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Ollama not reachable", "models": []any{}})
		return
	}
	defer resp.Body.Close()

	var result struct {
		Models []struct {
			Name       string `json:"name"`
			Model      string `json:"model"`
			ModifiedAt string `json:"modified_at"`
			Size       int64  `json:"size"`
		} `json:"models"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse Ollama response"})
		return
	}

	type localModel struct {
		ID   string `json:"id"`
		Name string `json:"name"`
		Size int64  `json:"size"`
	}
	models := make([]localModel, 0, len(result.Models))
	for _, m := range result.Models {
		models = append(models, localModel{
			ID:   m.Name,
			Name: m.Name,
			Size: m.Size,
		})
	}

	c.JSON(http.StatusOK, gin.H{"models": models, "total": len(models)})
}

func (h *AdminHandler) GetAIModerationConfigs(c *gin.Context) {
	configs, err := h.moderationService.GetModerationConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to fetch configs: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"configs": configs})
}

func (h *AdminHandler) SetAIModerationConfig(c *gin.Context) {
	var req struct {
		ModerationType string   `json:"moderation_type" binding:"required"`
		ModelID        string   `json:"model_id"`
		ModelName      string   `json:"model_name"`
		SystemPrompt   string   `json:"system_prompt"`
		Enabled        bool     `json:"enabled"`
		Engines        []string `json:"engines"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	allowedTypes := map[string]bool{"text": true, "image": true, "video": true, "group_text": true, "group_image": true, "beacon_text": true, "beacon_image": true}
	if !allowedTypes[req.ModerationType] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid moderation_type"})
		return
	}

	adminID := c.GetString("user_id")
	err := h.moderationService.SetModerationConfig(c.Request.Context(), req.ModerationType, req.ModelID, req.ModelName, req.SystemPrompt, req.Enabled, req.Engines, adminID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to save config: %v", err)})
		return
	}

	// Audit log
	h.pool.Exec(c.Request.Context(), `
		INSERT INTO audit_log (admin_id, action, target_type, details)
		VALUES ($1, 'update_ai_moderation', 'ai_config', $2)
	`, adminID, fmt.Sprintf("Set %s moderation model to %s (enabled=%v)", req.ModerationType, req.ModelID, req.Enabled))

	c.JSON(http.StatusOK, gin.H{"message": "Configuration updated"})
}

func (h *AdminHandler) TestAIModeration(c *gin.Context) {
	var req struct {
		ModerationType string `json:"moderation_type" binding:"required"`
		Content        string `json:"content"`
		ImageURL       string `json:"image_url"`
		Engine         string `json:"engine"` // "local_ai", "sightengine" — empty = sightengine
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	engine := req.Engine
	if engine == "" {
		engine = "sightengine"
	}

	ctx := c.Request.Context()

	// Determine the input text for display
	inputDisplay := req.Content
	if inputDisplay == "" && req.ImageURL != "" {
		inputDisplay = req.ImageURL
	}

	response := gin.H{
		"engine":          engine,
		"moderation_type": req.ModerationType,
		"input":           inputDisplay,
	}

	switch engine {
	case "local_ai":
		if h.localAIService == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Local AI not configured"})
			return
		}
		// Local AI only does text moderation
		content := req.Content
		if content == "" {
			content = req.ImageURL // fallback
		}
		localResult, err := h.localAIService.ModerateText(ctx, content)
		if err != nil {
			response["error"] = err.Error()
			c.JSON(http.StatusOK, response)
			return
		}
		action := "clean"
		flagged := false
		if !localResult.Allowed {
			action = "flag"
			flagged = true
		}
		explanation := "Local AI (llama-guard) determined this content is safe."
		if flagged {
			explanation = fmt.Sprintf("Local AI (llama-guard) flagged this content. Categories: %v, Severity: %s", localResult.Categories, localResult.Severity)
		}
		response["result"] = gin.H{
			"action":      action,
			"flagged":     flagged,
			"reason":      localResult.Reason,
			"categories":  localResult.Categories,
			"explanation": explanation,
			"raw_content": fmt.Sprintf("allowed=%v cached=%v categories=%v severity=%s reason=%s", localResult.Allowed, localResult.Cached, localResult.Categories, localResult.Severity, localResult.Reason),
		}

	case "sightengine":
		if h.sightEngineService == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "SightEngine not configured"})
			return
		}
		isImage := strings.Contains(req.ModerationType, "image") || req.ModerationType == "video"
		if isImage && req.ImageURL != "" {
			result, err := h.sightEngineService.ModerateImage(ctx, req.ImageURL)
			if err != nil {
				response["error"] = err.Error()
				c.JSON(http.StatusOK, response)
				return
			}
			response["result"] = gin.H{
				"action":      result.Action,
				"flagged":     result.Action == "flag",
				"reason":      result.Reason,
				"nsfw_reason": result.NSFWReason,
				"hate":        result.Scores.Hate,
				"greed":       result.Scores.Greed,
				"delusion":    result.Scores.Delusion,
				"explanation": fmt.Sprintf("SightEngine image analysis. Hate=%.3f, Greed=%.3f, Delusion=%.3f. %s", result.Scores.Hate, result.Scores.Greed, result.Scores.Delusion, result.Reason),
			}
		} else {
			content := req.Content
			if content == "" {
				content = req.ImageURL
			}
			result, err := h.sightEngineService.ModerateText(ctx, content)
			if err != nil {
				response["error"] = err.Error()
				c.JSON(http.StatusOK, response)
				return
			}
			response["result"] = gin.H{
				"action":      result.Action,
				"flagged":     result.Action == "flag",
				"reason":      result.Reason,
				"hate":        result.Scores.Hate,
				"greed":       result.Scores.Greed,
				"delusion":    result.Scores.Delusion,
				"explanation": fmt.Sprintf("SightEngine text analysis. Hate=%.3f, Greed=%.3f, Delusion=%.3f. %s", result.Scores.Hate, result.Scores.Greed, result.Scores.Delusion, result.Reason),
			}
		}

	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid engine: " + engine})
		return
	}

	c.JSON(http.StatusOK, response)
}

// ──────────────────────────────────────────────
// AI Moderation Audit Log
// ──────────────────────────────────────────────

func (h *AdminHandler) GetAIModerationLog(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	decision := c.Query("decision")
	contentType := c.Query("content_type")
	search := c.Query("search")
	feedbackFilter := c.Query("feedback")

	items, total, err := h.moderationService.GetAIModerationLog(ctx, limit, offset, decision, contentType, search, feedbackFilter)
	if err != nil {
		log.Error().Err(err).Msg("Failed to fetch AI moderation log")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch AI moderation log"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"items":  items,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *AdminHandler) SubmitAIModerationFeedback(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")
	logID := c.Param("id")

	var req struct {
		Correct bool   `json:"correct"`
		Reason  string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	logUUID, err := uuid.Parse(logID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid log ID"})
		return
	}
	adminUUID, _ := uuid.Parse(adminID.(string))

	if err := h.moderationService.SubmitAIFeedback(ctx, logUUID, req.Correct, req.Reason, adminUUID); err != nil {
		log.Error().Err(err).Msg("Failed to submit AI feedback")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to submit feedback"})
		return
	}

	// Audit log
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'ai_moderation_feedback', 'ai_moderation_log', $2, $3)`,
		adminUUID, logID, fmt.Sprintf(`{"correct":%v,"reason":"%s"}`, req.Correct, req.Reason))

	c.JSON(http.StatusOK, gin.H{"message": "Feedback submitted"})
}

func (h *AdminHandler) ExportAITrainingData(c *gin.Context) {
	ctx := c.Request.Context()

	data, err := h.moderationService.GetAITrainingData(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to export AI training data")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to export training data"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"training_data": data,
		"count":         len(data),
	})
}

// ──────────────────────────────────────────────
// Admin Create User
// ──────────────────────────────────────────────

func (h *AdminHandler) AdminCreateUser(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		Email       string `json:"email" binding:"required,email"`
		Password    string `json:"password" binding:"required,min=8"`
		Handle      string `json:"handle" binding:"required"`
		DisplayName string `json:"display_name" binding:"required"`
		Bio         string `json:"bio"`
		Role        string `json:"role"`
		Verified    bool   `json:"verified"`
		Official    bool   `json:"official"`
		SkipEmail   bool   `json:"skip_email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.Handle = strings.ToLower(strings.TrimSpace(req.Handle))

	// Check for existing email
	var existsCount int
	h.pool.QueryRow(ctx, "SELECT COUNT(*) FROM public.users WHERE email = $1", req.Email).Scan(&existsCount)
	if existsCount > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "Email already registered"})
		return
	}

	// Check for existing handle
	h.pool.QueryRow(ctx, "SELECT COUNT(*) FROM public.profiles WHERE handle = $1", req.Handle).Scan(&existsCount)
	if existsCount > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "Handle already taken"})
		return
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	userID := uuid.New()
	now := time.Now()

	tx, err := h.pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to start transaction"})
		return
	}
	defer tx.Rollback(ctx)

	// Create user (already active + verified, admin-created)
	_, err = tx.Exec(ctx, `
		INSERT INTO public.users (id, email, encrypted_password, status, mfa_enabled, created_at, updated_at)
		VALUES ($1, $2, $3, 'active', false, $4, $4)
	`, userID, req.Email, string(hashedBytes), now)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user: " + err.Error()})
		return
	}

	role := "user"
	if req.Role != "" {
		role = req.Role
	}

	// Create profile
	_, err = tx.Exec(ctx, `
		INSERT INTO public.profiles (id, handle, display_name, bio, is_verified, is_official, role, has_completed_onboarding)
		VALUES ($1, $2, $3, $4, $5, $6, $7, true)
	`, userID, req.Handle, req.DisplayName, req.Bio, req.Verified, req.Official, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create profile: " + err.Error()})
		return
	}

	// Initialize trust state
	_, err = tx.Exec(ctx, `
		INSERT INTO public.trust_state (user_id, harmony_score, tier)
		VALUES ($1, 50, 'new')
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to init trust state: " + err.Error()})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to commit: " + err.Error()})
		return
	}

	// Audit log
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'admin_create_user', 'user', $2, $3)`,
		adminID, userID.String(), fmt.Sprintf(`{"email":"%s","handle":"%s"}`, req.Email, req.Handle))

	log.Info().Str("admin", adminID.(string)).Str("new_user", userID.String()).Str("handle", req.Handle).Msg("Admin created user")

	c.JSON(http.StatusCreated, gin.H{
		"message": "User created successfully",
		"user_id": userID.String(),
		"email":   req.Email,
		"handle":  req.Handle,
	})
}

// ──────────────────────────────────────────────
// Admin Import Content (Posts / Quips / Beacons)
// ──────────────────────────────────────────────

func (h *AdminHandler) AdminImportContent(c *gin.Context) {
	ctx := c.Request.Context()
	adminID, _ := c.Get("user_id")

	var req struct {
		AuthorID    string `json:"author_id" binding:"required"`
		ContentType string `json:"content_type" binding:"required"` // post, quip, beacon
		Items       []struct {
			Body         string   `json:"body"`
			MediaURL     string   `json:"media_url"`
			ThumbnailURL string   `json:"thumbnail_url"`
			DurationMS   int      `json:"duration_ms"`
			Tags         []string `json:"tags"`
			CategoryID   string   `json:"category_id"`
			IsNSFW       bool     `json:"is_nsfw"`
			NSFWReason   string   `json:"nsfw_reason"`
			Visibility   string   `json:"visibility"`
			BeaconType   string   `json:"beacon_type"`
			Lat          float64  `json:"lat"`
			Long         float64  `json:"long"`
		} `json:"items" binding:"required,min=1"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	authorUUID, err := uuid.Parse(req.AuthorID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid author_id"})
		return
	}

	// Verify author exists
	var authorExists int
	h.pool.QueryRow(ctx, "SELECT COUNT(*) FROM public.profiles WHERE id = $1", authorUUID).Scan(&authorExists)
	if authorExists == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Author not found"})
		return
	}

	validTypes := map[string]bool{"post": true, "quip": true, "beacon": true}
	if !validTypes[req.ContentType] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "content_type must be post, quip, or beacon"})
		return
	}

	var created []string
	var errors []string

	for i, item := range req.Items {
		postID := uuid.New()
		visibility := item.Visibility
		if visibility == "" {
			visibility = "public"
		}

		var imageURL, videoURL, thumbnailURL *string
		var categoryID *uuid.UUID
		var beaconType *string
		var lat, long *float64
		isBeacon := false
		durationMS := item.DurationMS

		// Determine media type from URL
		mediaURL := strings.TrimSpace(item.MediaURL)
		if mediaURL != "" {
			lower := strings.ToLower(mediaURL)
			if strings.HasSuffix(lower, ".mp4") || strings.HasSuffix(lower, ".mov") || strings.HasSuffix(lower, ".webm") || req.ContentType == "quip" {
				videoURL = &mediaURL
			} else {
				imageURL = &mediaURL
			}
		}

		if item.ThumbnailURL != "" {
			thumbnailURL = &item.ThumbnailURL
		}

		if item.CategoryID != "" {
			if catUUID, err := uuid.Parse(item.CategoryID); err == nil {
				categoryID = &catUUID
			}
		}

		if req.ContentType == "beacon" {
			isBeacon = true
			if item.BeaconType != "" {
				beaconType = &item.BeaconType
			} else {
				bt := "general"
				beaconType = &bt
			}
			if item.Lat != 0 || item.Long != 0 {
				lat = &item.Lat
				long = &item.Long
			}
		}

		tx, err := h.pool.Begin(ctx)
		if err != nil {
			errors = append(errors, fmt.Sprintf("item %d: tx start failed", i))
			continue
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO public.posts (
				id, author_id, category_id, body, status, tone_label, cis_score,
				image_url, video_url, thumbnail_url, duration_ms, body_format, tags,
				is_beacon, beacon_type, location, confidence_score,
				is_active_beacon, allow_chain, visibility,
				is_nsfw, nsfw_reason
			) VALUES (
				$1, $2, $3, $4, 'active', 'neutral', 0.8,
				$5, $6, $7, $8, 'plain', $9,
				$10, $11,
				CASE WHEN ($12::double precision) IS NOT NULL AND ($13::double precision) IS NOT NULL
					THEN ST_SetSRID(ST_MakePoint(($13::double precision), ($12::double precision)), 4326)::geography
					ELSE NULL END,
				0.5, $10, true, $14,
				$15, $16
			) RETURNING id
		`, postID, authorUUID, categoryID, item.Body,
			imageURL, videoURL, thumbnailURL, durationMS, item.Tags,
			isBeacon, beaconType, lat, long, visibility,
			item.IsNSFW, item.NSFWReason,
		)
		if err != nil {
			tx.Rollback(ctx)
			errors = append(errors, fmt.Sprintf("item %d: %s", i, err.Error()))
			continue
		}

		// Initialize metrics
		_, err = tx.Exec(ctx, "INSERT INTO public.post_metrics (post_id) VALUES ($1)", postID)
		if err != nil {
			tx.Rollback(ctx)
			errors = append(errors, fmt.Sprintf("item %d: metrics init failed", i))
			continue
		}

		if err := tx.Commit(ctx); err != nil {
			errors = append(errors, fmt.Sprintf("item %d: commit failed", i))
			continue
		}

		created = append(created, postID.String())
	}

	// Audit log
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'admin_import_content', 'post', $2, $3)`,
		adminID, req.AuthorID, fmt.Sprintf(`{"type":"%s","count":%d,"errors":%d}`, req.ContentType, len(created), len(errors)))

	log.Info().Str("admin", adminID.(string)).Str("type", req.ContentType).Int("created", len(created)).Int("errors", len(errors)).Msg("Admin import content")

	c.JSON(http.StatusOK, gin.H{
		"message":  fmt.Sprintf("Imported %d/%d items", len(created), len(req.Items)),
		"created":  created,
		"errors":   errors,
		"total":    len(req.Items),
		"success":  len(created),
		"failures": len(errors),
	})
}

// ──────────────────────────────────────────────────────
// Official Accounts Management
// ──────────────────────────────────────────────────────

func (h *AdminHandler) ListOfficialAccounts(c *gin.Context) {
	configs, err := h.officialAccountsService.ListConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if configs == nil {
		configs = []services.OfficialAccountConfig{}
	}
	c.JSON(http.StatusOK, gin.H{"configs": configs})
}

func (h *AdminHandler) ListOfficialProfiles(c *gin.Context) {
	profiles, err := h.officialAccountsService.ListOfficialProfiles(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if profiles == nil {
		profiles = []services.OfficialProfile{}
	}
	c.JSON(http.StatusOK, gin.H{"profiles": profiles})
}

func (h *AdminHandler) GetOfficialAccount(c *gin.Context) {
	id := c.Param("id")
	cfg, err := h.officialAccountsService.GetConfig(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Config not found"})
		return
	}
	c.JSON(http.StatusOK, cfg)
}

func (h *AdminHandler) UpsertOfficialAccount(c *gin.Context) {
	var req struct {
		ProfileID           string                `json:"profile_id"`
		Handle              string                `json:"handle"`
		AccountType         string                `json:"account_type"`
		Enabled             bool                  `json:"enabled"`
		ModelID             string                `json:"model_id"`
		SystemPrompt        string                `json:"system_prompt"`
		Temperature         float64               `json:"temperature"`
		MaxTokens           int                   `json:"max_tokens"`
		PostIntervalMinutes int                   `json:"post_interval_minutes"`
		MaxPostsPerDay      int                   `json:"max_posts_per_day"`
		NewsSources         []services.NewsSource `json:"news_sources"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Resolve handle to profile_id if provided
	profileID := req.ProfileID
	if profileID == "" && req.Handle != "" {
		pid, err := h.officialAccountsService.LookupProfileID(ctx, req.Handle)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		profileID = pid
	}
	if profileID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "profile_id or handle required"})
		return
	}

	// Defaults
	if req.ModelID == "" {
		req.ModelID = "google/gemini-2.0-flash-001"
	}
	if req.MaxTokens == 0 {
		req.MaxTokens = 500
	}
	if req.PostIntervalMinutes == 0 {
		req.PostIntervalMinutes = 60
	}
	if req.MaxPostsPerDay == 0 {
		req.MaxPostsPerDay = 24
	}
	if req.AccountType == "" {
		req.AccountType = "general"
	}

	newsJSON, _ := json.Marshal(req.NewsSources)

	cfg := services.OfficialAccountConfig{
		ProfileID:           profileID,
		AccountType:         req.AccountType,
		Enabled:             req.Enabled,
		ModelID:             req.ModelID,
		SystemPrompt:        req.SystemPrompt,
		Temperature:         req.Temperature,
		MaxTokens:           req.MaxTokens,
		PostIntervalMinutes: req.PostIntervalMinutes,
		MaxPostsPerDay:      req.MaxPostsPerDay,
		NewsSources:         newsJSON,
	}

	result, err := h.officialAccountsService.UpsertConfig(ctx, cfg)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	adminID, _ := c.Get("user_id")
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'admin_upsert_official_account', 'official_account', $2, $3)`,
		adminID, result.ID, fmt.Sprintf(`{"profile_id":"%s","type":"%s"}`, profileID, req.AccountType))

	c.JSON(http.StatusOK, result)
}

func (h *AdminHandler) DeleteOfficialAccount(c *gin.Context) {
	id := c.Param("id")
	ctx := c.Request.Context()

	if err := h.officialAccountsService.DeleteConfig(ctx, id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	adminID, _ := c.Get("user_id")
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id) VALUES ($1, 'admin_delete_official_account', 'official_account', $2)`, adminID, id)

	c.JSON(http.StatusOK, gin.H{"message": "Deleted"})
}

func (h *AdminHandler) ToggleOfficialAccount(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.officialAccountsService.ToggleEnabled(c.Request.Context(), id, req.Enabled); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"enabled": req.Enabled})
}

// Manually trigger a post for an official account.
// Accepts query param ?count=N to post multiple articles at once.
// count=0 or count=all posts ALL pending articles.
func (h *AdminHandler) TriggerOfficialPost(c *gin.Context) {
	id := c.Param("id")
	ctx := c.Request.Context()

	cfg, err := h.officialAccountsService.GetConfig(ctx, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Config not found"})
		return
	}

	// Parse count param: default 1, "all" or "0" = post everything
	countStr := c.DefaultQuery("count", "1")
	postAll := countStr == "all" || countStr == "0"
	count := 1
	if !postAll {
		if n, err := strconv.Atoi(countStr); err == nil && n > 0 {
			count = n
		}
	}

	switch cfg.AccountType {
	case "news", "rss":
		// Phase 1: Discover new articles
		discovered, discErr := h.officialAccountsService.DiscoverArticles(ctx, id)
		if discErr != nil {
			// Log but continue — there may be previously discovered articles
			log.Warn().Err(discErr).Str("config", id).Msg("Discover error during trigger")
		}

		// If posting all, get the pending count
		if postAll {
			stats, _ := h.officialAccountsService.GetArticleStats(ctx, id)
			if stats != nil {
				count = stats.Discovered
			}
		}

		// Phase 2: Post N articles from the queue
		var posted []gin.H
		var errors []string
		for i := 0; i < count; i++ {
			article, postID, err := h.officialAccountsService.PostNextArticle(ctx, id)
			if err != nil {
				errors = append(errors, err.Error())
				continue
			}
			if article == nil {
				break // no more articles
			}
			posted = append(posted, gin.H{
				"post_id": postID,
				"title":   article.Title,
				"link":    article.Link,
				"source":  article.SourceName,
			})
		}

		if len(posted) == 0 && len(errors) == 0 {
			msg := "No new articles found"
			if discErr != nil {
				msg += " (discover error: " + discErr.Error() + ")"
			}
			c.JSON(http.StatusOK, gin.H{"message": msg, "post_id": nil, "discovered": discovered})
			return
		}

		stats, _ := h.officialAccountsService.GetArticleStats(ctx, id)
		c.JSON(http.StatusOK, gin.H{
			"message":    fmt.Sprintf("Posted %d article(s)", len(posted)),
			"posted":     posted,
			"errors":     errors,
			"discovered": discovered,
			"stats":      stats,
		})

	default:
		postID, body, err := h.officialAccountsService.GenerateAndPost(ctx, id, nil, "")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"message": "Post created",
			"post_id": postID,
			"body":    body,
		})
	}
}

// Preview what AI would generate without actually posting
func (h *AdminHandler) PreviewOfficialPost(c *gin.Context) {
	id := c.Param("id")
	ctx := c.Request.Context()

	cfg, err := h.officialAccountsService.GetConfig(ctx, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Config not found"})
		return
	}

	switch cfg.AccountType {
	case "news", "rss":
		// Discover then show the next article that would be posted
		_, _ = h.officialAccountsService.DiscoverArticles(ctx, id)

		pending, err := h.officialAccountsService.GetArticleQueue(ctx, id, "discovered", 10)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if len(pending) == 0 {
			c.JSON(http.StatusOK, gin.H{"message": "No pending articles", "preview": nil})
			return
		}

		next := pending[0]
		stats, _ := h.officialAccountsService.GetArticleStats(ctx, id)
		c.JSON(http.StatusOK, gin.H{
			"preview":       next.Link,
			"source":        next.SourceName,
			"article_title": next.Title,
			"article_link":  next.Link,
			"pending_count": len(pending),
			"stats":         stats,
		})

	default:
		body, err := h.officialAccountsService.GeneratePost(ctx, id, nil, "")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"preview": body})
	}
}

// Fetch available news articles (without posting)
func (h *AdminHandler) FetchNewsArticles(c *gin.Context) {
	id := c.Param("id")
	ctx := c.Request.Context()

	// Discover new articles first
	_, _ = h.officialAccountsService.DiscoverArticles(ctx, id)

	// Return the full CachedArticle objects so frontend has IDs for per-article actions
	articles, err := h.officialAccountsService.GetArticleQueue(ctx, id, "discovered", 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if articles == nil {
		articles = []services.CachedArticle{}
	}
	stats, _ := h.officialAccountsService.GetArticleStats(ctx, id)
	c.JSON(http.StatusOK, gin.H{"articles": articles, "count": len(articles), "stats": stats})
}

// Get articles by status for an account (defaults to "posted")
func (h *AdminHandler) GetPostedArticles(c *gin.Context) {
	id := c.Param("id")
	status := c.DefaultQuery("status", "posted")
	limit := 50
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 {
			limit = parsed
		}
	}

	articles, err := h.officialAccountsService.GetArticleQueue(c.Request.Context(), id, status, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if articles == nil {
		articles = []services.CachedArticle{}
	}
	stats, _ := h.officialAccountsService.GetArticleStats(c.Request.Context(), id)
	c.JSON(http.StatusOK, gin.H{"articles": articles, "stats": stats})
}

// ── Article Pipeline Management ──────────────────────

// SkipArticle marks a pending article as skipped.
func (h *AdminHandler) SkipArticle(c *gin.Context) {
	articleID := c.Param("article_id")
	if err := h.officialAccountsService.SkipArticle(c.Request.Context(), articleID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Article skipped"})
}

// DeleteArticle permanently removes an article from the pipeline.
func (h *AdminHandler) DeleteArticle(c *gin.Context) {
	articleID := c.Param("article_id")
	if err := h.officialAccountsService.DeleteArticle(c.Request.Context(), articleID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Article deleted"})
}

// PostSpecificArticle posts a single pending article by its ID.
func (h *AdminHandler) PostSpecificArticle(c *gin.Context) {
	articleID := c.Param("article_id")
	article, postID, err := h.officialAccountsService.PostSpecificArticle(c.Request.Context(), articleID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "Article posted",
		"post_id": postID,
		"title":   article.Title,
		"link":    article.Link,
	})
}

// CleanupPendingArticles skips or deletes all pending articles older than a date.
func (h *AdminHandler) CleanupPendingArticles(c *gin.Context) {
	configID := c.Param("id")
	var req struct {
		Before string `json:"before" binding:"required"` // ISO date: 2026-02-10
		Action string `json:"action" binding:"required"` // "skip" or "delete"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	before, err := time.Parse("2006-01-02", req.Before)
	if err != nil {
		before, err = time.Parse(time.RFC3339, req.Before)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD or RFC3339."})
			return
		}
	}

	affected, err := h.officialAccountsService.CleanupPendingByDate(c.Request.Context(), configID, before, req.Action)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stats, _ := h.officialAccountsService.GetArticleStats(c.Request.Context(), configID)
	c.JSON(http.StatusOK, gin.H{
		"message":  fmt.Sprintf("%d article(s) %sed", affected, req.Action),
		"affected": affected,
		"stats":    stats,
	})
}

// ── Safe Domains Management ─────────────────────────

func (h *AdminHandler) ListSafeDomains(c *gin.Context) {
	category := c.Query("category")
	approvedOnly := c.Query("approved_only") == "true"

	domains, err := h.linkPreviewService.ListSafeDomains(c.Request.Context(), category, approvedOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"domains": domains})
}

func (h *AdminHandler) UpsertSafeDomain(c *gin.Context) {
	var req struct {
		Domain     string `json:"domain" binding:"required"`
		Category   string `json:"category"`
		IsApproved *bool  `json:"is_approved"`
		Notes      string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cat := req.Category
	if cat == "" {
		cat = "general"
	}
	approved := true
	if req.IsApproved != nil {
		approved = *req.IsApproved
	}

	domain, err := h.linkPreviewService.UpsertSafeDomain(c.Request.Context(), req.Domain, cat, approved, req.Notes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"domain": domain})
}

func (h *AdminHandler) DeleteSafeDomain(c *gin.Context) {
	id := c.Param("id")
	if err := h.linkPreviewService.DeleteSafeDomain(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

// GetAIEngines returns the status of all moderation engines (local AI, SightEngine).
func (h *AdminHandler) GetAIEngines(c *gin.Context) {
	type EngineStatus struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Description string `json:"description"`
		Status      string `json:"status"`
		Configured  bool   `json:"configured"`
		Details     any    `json:"details,omitempty"`
	}

	engines := []EngineStatus{}

	// 1. Local AI (Ollama via AI Gateway)
	localEngine := EngineStatus{
		ID:          "local_ai",
		Name:        "Local AI (Ollama)",
		Description: "On-server moderation via llama-guard3:1b + content generation via qwen2.5:7b. Free, private, ~2s latency.",
		Configured:  h.localAIService != nil,
	}
	if h.localAIService != nil {
		health, err := h.localAIService.Healthz(c.Request.Context())
		if err != nil {
			localEngine.Status = "down"
			localEngine.Details = map[string]string{"error": err.Error()}
		} else {
			localEngine.Status = health.Status
			localEngine.Details = health
		}
	} else {
		localEngine.Status = "not_configured"
	}
	engines = append(engines, localEngine)

	// 2. SightEngine (text + image moderation API)
	sightEngine := EngineStatus{
		ID:          "sightengine",
		Name:        "SightEngine",
		Description: "Dedicated content moderation API. Supports text (profanity, spam, violence) and image (nudity, gore, weapons, drugs) analysis.",
		Configured:  h.sightEngineService != nil,
	}
	if h.sightEngineService != nil {
		status, err := h.sightEngineService.Healthz(c.Request.Context())
		if err != nil {
			sightEngine.Status = "down"
			sightEngine.Details = map[string]string{"error": err.Error()}
		} else {
			sightEngine.Status = status
		}
	} else {
		sightEngine.Status = "not_configured"
	}
	engines = append(engines, sightEngine)

	c.JSON(http.StatusOK, gin.H{"engines": engines})
}

func (h *AdminHandler) UploadTestImage(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file uploaded"})
		return
	}
	defer file.Close()

	// Validate file type
	if !strings.HasPrefix(header.Header.Get("Content-Type"), "image/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only image files are allowed"})
		return
	}

	// Validate file size (5MB limit)
	if header.Size > 5*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File too large (max 5MB)"})
		return
	}

	// Generate unique filename
	ext := filepath.Ext(header.Filename)
	filename := fmt.Sprintf("test-%s%s", uuid.New().String()[:8], ext)

	// Upload to R2
	key := fmt.Sprintf("test-images/%s", filename)

	// Read file content
	fileData, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file"})
		return
	}

	// Upload to R2
	contentType := header.Header.Get("Content-Type")
	_, err = h.s3Client.PutObject(c.Request.Context(), &s3.PutObjectInput{
		Bucket:      aws.String(h.mediaBucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(fileData),
		ContentType: aws.String(contentType),
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Upload failed"})
		return
	}

	// Return the URL
	url := fmt.Sprintf("https://%s/%s", h.imgDomain, key)
	c.JSON(http.StatusOK, gin.H{"url": url, "filename": filename})
}

func (h *AdminHandler) CheckURLSafety(c *gin.Context) {
	urlStr := c.Query("url")
	if urlStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url parameter required"})
		return
	}
	result := h.linkPreviewService.CheckURLSafety(c.Request.Context(), urlStr)
	c.JSON(http.StatusOK, result)
}

// ──────────────────────────────────────────────
// Email Template Management
// ──────────────────────────────────────────────

func (h *AdminHandler) ListEmailTemplates(c *gin.Context) {
	rows, err := h.pool.Query(c.Request.Context(),
		`SELECT id, slug, name, description, subject, title, header, content, button_text, button_url, button_color, footer, text_body, enabled, updated_at, created_at
		 FROM email_templates ORDER BY name ASC`)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list email templates")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list templates"})
		return
	}
	defer rows.Close()

	type EmailTemplate struct {
		ID          string    `json:"id"`
		Slug        string    `json:"slug"`
		Name        string    `json:"name"`
		Description string    `json:"description"`
		Subject     string    `json:"subject"`
		Title       string    `json:"title"`
		Header      string    `json:"header"`
		Content     string    `json:"content"`
		ButtonText  string    `json:"button_text"`
		ButtonURL   string    `json:"button_url"`
		ButtonColor string    `json:"button_color"`
		Footer      string    `json:"footer"`
		TextBody    string    `json:"text_body"`
		Enabled     bool      `json:"enabled"`
		UpdatedAt   time.Time `json:"updated_at"`
		CreatedAt   time.Time `json:"created_at"`
	}

	var templates []EmailTemplate
	for rows.Next() {
		var t EmailTemplate
		if err := rows.Scan(&t.ID, &t.Slug, &t.Name, &t.Description, &t.Subject, &t.Title, &t.Header, &t.Content, &t.ButtonText, &t.ButtonURL, &t.ButtonColor, &t.Footer, &t.TextBody, &t.Enabled, &t.UpdatedAt, &t.CreatedAt); err != nil {
			log.Error().Err(err).Msg("Failed to scan email template")
			continue
		}
		templates = append(templates, t)
	}

	c.JSON(http.StatusOK, gin.H{"templates": templates})
}

func (h *AdminHandler) GetEmailTemplate(c *gin.Context) {
	id := c.Param("id")

	type EmailTemplate struct {
		ID          string    `json:"id"`
		Slug        string    `json:"slug"`
		Name        string    `json:"name"`
		Description string    `json:"description"`
		Subject     string    `json:"subject"`
		Title       string    `json:"title"`
		Header      string    `json:"header"`
		Content     string    `json:"content"`
		ButtonText  string    `json:"button_text"`
		ButtonURL   string    `json:"button_url"`
		ButtonColor string    `json:"button_color"`
		Footer      string    `json:"footer"`
		TextBody    string    `json:"text_body"`
		Enabled     bool      `json:"enabled"`
		UpdatedAt   time.Time `json:"updated_at"`
		CreatedAt   time.Time `json:"created_at"`
	}

	var t EmailTemplate
	err := h.pool.QueryRow(c.Request.Context(),
		`SELECT id, slug, name, description, subject, title, header, content, button_text, button_url, button_color, footer, text_body, enabled, updated_at, created_at
		 FROM email_templates WHERE id = $1`, id).
		Scan(&t.ID, &t.Slug, &t.Name, &t.Description, &t.Subject, &t.Title, &t.Header, &t.Content, &t.ButtonText, &t.ButtonURL, &t.ButtonColor, &t.Footer, &t.TextBody, &t.Enabled, &t.UpdatedAt, &t.CreatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	c.JSON(http.StatusOK, t)
}

func (h *AdminHandler) UpdateEmailTemplate(c *gin.Context) {
	id := c.Param("id")

	var req struct {
		Subject     *string `json:"subject"`
		Title       *string `json:"title"`
		Header      *string `json:"header"`
		Content     *string `json:"content"`
		ButtonText  *string `json:"button_text"`
		ButtonURL   *string `json:"button_url"`
		ButtonColor *string `json:"button_color"`
		Footer      *string `json:"footer"`
		TextBody    *string `json:"text_body"`
		Enabled     *bool   `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	// Build dynamic UPDATE
	sets := []string{}
	args := []interface{}{}
	argIdx := 1

	if req.Subject != nil {
		sets = append(sets, fmt.Sprintf("subject = $%d", argIdx))
		args = append(args, *req.Subject)
		argIdx++
	}
	if req.Title != nil {
		sets = append(sets, fmt.Sprintf("title = $%d", argIdx))
		args = append(args, *req.Title)
		argIdx++
	}
	if req.Header != nil {
		sets = append(sets, fmt.Sprintf("header = $%d", argIdx))
		args = append(args, *req.Header)
		argIdx++
	}
	if req.Content != nil {
		sets = append(sets, fmt.Sprintf("content = $%d", argIdx))
		args = append(args, *req.Content)
		argIdx++
	}
	if req.ButtonText != nil {
		sets = append(sets, fmt.Sprintf("button_text = $%d", argIdx))
		args = append(args, *req.ButtonText)
		argIdx++
	}
	if req.ButtonURL != nil {
		sets = append(sets, fmt.Sprintf("button_url = $%d", argIdx))
		args = append(args, *req.ButtonURL)
		argIdx++
	}
	if req.ButtonColor != nil {
		sets = append(sets, fmt.Sprintf("button_color = $%d", argIdx))
		args = append(args, *req.ButtonColor)
		argIdx++
	}
	if req.Footer != nil {
		sets = append(sets, fmt.Sprintf("footer = $%d", argIdx))
		args = append(args, *req.Footer)
		argIdx++
	}
	if req.TextBody != nil {
		sets = append(sets, fmt.Sprintf("text_body = $%d", argIdx))
		args = append(args, *req.TextBody)
		argIdx++
	}
	if req.Enabled != nil {
		sets = append(sets, fmt.Sprintf("enabled = $%d", argIdx))
		args = append(args, *req.Enabled)
		argIdx++
	}

	if len(sets) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No fields to update"})
		return
	}

	sets = append(sets, "updated_at = NOW()")
	args = append(args, id)

	query := fmt.Sprintf("UPDATE email_templates SET %s WHERE id = $%d RETURNING id", strings.Join(sets, ", "), argIdx)

	var returnedID string
	err := h.pool.QueryRow(c.Request.Context(), query, args...).Scan(&returnedID)
	if err != nil {
		log.Error().Err(err).Str("template_id", id).Msg("Failed to update email template")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update template"})
		return
	}

	// Log to audit
	adminID, _ := c.Get("user_id")
	_, _ = h.pool.Exec(c.Request.Context(),
		`INSERT INTO audit_log (admin_id, action, target_type, target_id, details) VALUES ($1, 'update_email_template', 'email_template', $2, $3)`,
		adminID, id, fmt.Sprintf("Updated email template %s", id))

	c.JSON(http.StatusOK, gin.H{"message": "Template updated", "id": returnedID})
}

func (h *AdminHandler) SendTestEmail(c *gin.Context) {
	var req struct {
		TemplateID string `json:"template_id"`
		ToEmail    string `json:"to_email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	if req.TemplateID == "" || req.ToEmail == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "template_id and to_email are required"})
		return
	}

	var subject, title, header, content, buttonText, buttonURL, buttonColor, footer, textBody string
	err := h.pool.QueryRow(c.Request.Context(),
		`SELECT subject, title, header, content, button_text, button_url, button_color, footer, text_body
		 FROM email_templates WHERE id = $1`, req.TemplateID).
		Scan(&subject, &title, &header, &content, &buttonText, &buttonURL, &buttonColor, &footer, &textBody)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	// Replace placeholders with sample data for test
	replacer := strings.NewReplacer(
		"{{name}}", "Test User",
		"{{verify_url}}", "https://mp.ls/verified",
		"{{reset_url}}", "https://mp.ls/sojorn",
		"{{reason}}", "This is a test reason",
		"{{duration}}", "7 days",
		"{{deletion_date}}", time.Now().AddDate(0, 0, 14).Format("January 2, 2006"),
		"{{confirm_url}}", "https://mp.ls/destroyed",
		"{{content_type}}", "post",
		"{{strike_count}}", "1",
		"{{strike_warning}}", "",
	)

	subject = replacer.Replace(subject)
	header = replacer.Replace(header)
	content = replacer.Replace(content)
	buttonText = replacer.Replace(buttonText)
	buttonURL = replacer.Replace(buttonURL)
	textBody = replacer.Replace(textBody)

	htmlBody := h.emailService.BuildHTMLEmailWithColor(title, header, content, buttonURL, buttonText, footer, buttonColor)

	if err := h.emailService.SendGenericEmail(req.ToEmail, "Test User", subject, htmlBody, textBody); err != nil {
		log.Error().Err(err).Msg("Failed to send test email")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send test email: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Test email sent to " + req.ToEmail})
}

func (h *AdminHandler) GetAltchaChallenge(c *gin.Context) {
	altchaService := services.NewAltchaService(h.jwtSecret)

	challenge, err := altchaService.GenerateChallenge()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate challenge"})
		return
	}

	c.JSON(http.StatusOK, challenge)
}

// ──────────────────────────────────────────────────────────────────────────────
// Groups admin
// ──────────────────────────────────────────────────────────────────────────────

// AdminListGroups GET /admin/groups?search=&limit=50&offset=0
func (h *AdminHandler) AdminListGroups(c *gin.Context) {
	search := c.Query("search")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	query := `
		SELECT g.id, g.name, g.description, g.is_private, g.status,
		       g.created_at, g.key_version, g.key_rotation_needed,
		       COUNT(DISTINCT gm.user_id) AS member_count,
		       COUNT(DISTINCT gp.post_id)  AS post_count
		FROM groups g
		LEFT JOIN group_members gm ON gm.group_id = g.id
		LEFT JOIN group_posts   gp ON gp.group_id = g.id
	`
	args := []interface{}{}
	if search != "" {
		query += " WHERE g.name ILIKE $1 OR g.description ILIKE $1"
		args = append(args, "%"+search+"%")
	}
	query += fmt.Sprintf(`
		GROUP BY g.id
		ORDER BY g.created_at DESC
		LIMIT $%d OFFSET $%d`, len(args)+1, len(args)+2)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(c.Request.Context(), query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type groupRow struct {
		ID                 string    `json:"id"`
		Name               string    `json:"name"`
		Description        string    `json:"description"`
		IsPrivate          bool      `json:"is_private"`
		Status             string    `json:"status"`
		CreatedAt          time.Time `json:"created_at"`
		KeyVersion         int       `json:"key_version"`
		KeyRotationNeeded  bool      `json:"key_rotation_needed"`
		MemberCount        int       `json:"member_count"`
		PostCount          int       `json:"post_count"`
	}

	var groups []groupRow
	for rows.Next() {
		var g groupRow
		if err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.IsPrivate, &g.Status,
			&g.CreatedAt, &g.KeyVersion, &g.KeyRotationNeeded, &g.MemberCount, &g.PostCount); err != nil {
			continue
		}
		groups = append(groups, g)
	}
	c.JSON(http.StatusOK, gin.H{"groups": groups, "limit": limit, "offset": offset})
}

// AdminGetGroup GET /admin/groups/:id
func (h *AdminHandler) AdminGetGroup(c *gin.Context) {
	groupID := c.Param("id")
	row := h.pool.QueryRow(c.Request.Context(), `
		SELECT g.id, g.name, g.description, g.is_private, g.status, g.created_at,
		       g.key_version, g.key_rotation_needed,
		       COUNT(DISTINCT gm.user_id) AS member_count,
		       COUNT(DISTINCT gp.post_id)  AS post_count
		FROM groups g
		LEFT JOIN group_members gm ON gm.group_id = g.id
		LEFT JOIN group_posts   gp ON gp.group_id = g.id
		WHERE g.id = $1
		GROUP BY g.id
	`, groupID)

	var g struct {
		ID                string    `json:"id"`
		Name              string    `json:"name"`
		Description       string    `json:"description"`
		IsPrivate         bool      `json:"is_private"`
		Status            string    `json:"status"`
		CreatedAt         time.Time `json:"created_at"`
		KeyVersion        int       `json:"key_version"`
		KeyRotationNeeded bool      `json:"key_rotation_needed"`
		MemberCount       int       `json:"member_count"`
		PostCount         int       `json:"post_count"`
	}
	if err := row.Scan(&g.ID, &g.Name, &g.Description, &g.IsPrivate, &g.Status, &g.CreatedAt,
		&g.KeyVersion, &g.KeyRotationNeeded, &g.MemberCount, &g.PostCount); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}
	c.JSON(http.StatusOK, g)
}

// AdminDeleteGroup DELETE /admin/groups/:id  (soft delete)
func (h *AdminHandler) AdminDeleteGroup(c *gin.Context) {
	groupID := c.Param("id")
	_, err := h.pool.Exec(c.Request.Context(),
		`UPDATE groups SET status = 'inactive' WHERE id = $1`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "group deactivated"})
}

// AdminListGroupMembers GET /admin/groups/:id/members
func (h *AdminHandler) AdminListGroupMembers(c *gin.Context) {
	groupID := c.Param("id")
	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT gm.user_id, u.username, u.display_name, gm.role, gm.joined_at
		FROM group_members gm
		JOIN users u ON u.id = gm.user_id
		WHERE gm.group_id = $1
		ORDER BY gm.joined_at
	`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type member struct {
		UserID      string    `json:"user_id"`
		Username    string    `json:"username"`
		DisplayName string    `json:"display_name"`
		Role        string    `json:"role"`
		JoinedAt    time.Time `json:"joined_at"`
	}
	var members []member
	for rows.Next() {
		var m member
		if err := rows.Scan(&m.UserID, &m.Username, &m.DisplayName, &m.Role, &m.JoinedAt); err != nil {
			continue
		}
		members = append(members, m)
	}
	c.JSON(http.StatusOK, gin.H{"members": members})
}

// AdminRemoveGroupMember DELETE /admin/groups/:id/members/:userId
func (h *AdminHandler) AdminRemoveGroupMember(c *gin.Context) {
	groupID := c.Param("id")
	userID := c.Param("userId")
	_, err := h.pool.Exec(c.Request.Context(),
		`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`, groupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Flag group for key rotation (client will auto-rotate on next open)
	h.pool.Exec(c.Request.Context(),
		`UPDATE groups SET key_rotation_needed = true WHERE id = $1`, groupID)
	c.JSON(http.StatusOK, gin.H{"message": "member removed"})
}

// ──────────────────────────────────────────────────────────────────────────────
// Quip (video post) repair
// ──────────────────────────────────────────────────────────────────────────────

// GetBrokenQuips GET /admin/quips/broken
// Returns posts that have a video_url but are missing a thumbnail.
func (h *AdminHandler) GetBrokenQuips(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT id, user_id, video_url, created_at
		FROM posts
		WHERE video_url IS NOT NULL
		  AND (thumbnail_url IS NULL OR thumbnail_url = '')
		  AND status = 'active'
		ORDER BY created_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type quip struct {
		ID        string    `json:"id"`
		UserID    string    `json:"user_id"`
		VideoURL  string    `json:"video_url"`
		CreatedAt time.Time `json:"created_at"`
	}
	var quips []quip
	for rows.Next() {
		var q quip
		if err := rows.Scan(&q.ID, &q.UserID, &q.VideoURL, &q.CreatedAt); err != nil {
			continue
		}
		quips = append(quips, q)
	}
	c.JSON(http.StatusOK, gin.H{"quips": quips})
}

// SetPostThumbnail PATCH /admin/posts/:id/thumbnail
// Body: {"thumbnail_url": "..."}
func (h *AdminHandler) SetPostThumbnail(c *gin.Context) {
	postID := c.Param("id")
	var req struct {
		ThumbnailURL string `json:"thumbnail_url" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_, err := h.pool.Exec(c.Request.Context(),
		`UPDATE posts SET thumbnail_url = $1 WHERE id = $2`, req.ThumbnailURL, postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "thumbnail updated"})
}

// RepairQuip POST /admin/quips/:id/repair
// Triggers FFmpeg frame extraction on the server and sets thumbnail_url.
func (h *AdminHandler) RepairQuip(c *gin.Context) {
	postID := c.Param("id")

	// Fetch video_url
	var videoURL string
	err := h.pool.QueryRow(c.Request.Context(),
		`SELECT video_url FROM posts WHERE id = $1`, postID).Scan(&videoURL)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	if videoURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "post has no video_url"})
		return
	}

	vp := services.NewVideoProcessor(h.s3Client, h.videoBucket, h.vidDomain)
	frames, err := vp.ExtractFrames(c.Request.Context(), videoURL, 3)
	if err != nil || len(frames) == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "frame extraction failed: " + func() string {
			if err != nil {
				return err.Error()
			}
			return "no frames"
		}()})
		return
	}

	thumbnail := frames[0]
	_, err = h.pool.Exec(c.Request.Context(),
		`UPDATE posts SET thumbnail_url = $1 WHERE id = $2`, thumbnail, postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"thumbnail_url": thumbnail})
}

// ──────────────────────────────────────────────────────────────────────────────
// ──────────────────────────────────────────────
// Waitlist Management
// ──────────────────────────────────────────────

// AdminListWaitlist GET /admin/waitlist?status=&limit=&offset=
func (h *AdminHandler) AdminListWaitlist(c *gin.Context) {
	ctx := c.Request.Context()
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	status := c.DefaultQuery("status", "")
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	query := `SELECT id, email, name, referral_code, invited_by, status, notes, created_at, updated_at
	           FROM waitlist`
	args := []interface{}{}
	if status != "" {
		query += " WHERE status = $1"
		args = append(args, status)
	}
	query += fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	args = append(args, limit, offset)

	rows, err := h.pool.Query(ctx, query, args...)
	if err != nil {
		// Table may not exist yet
		c.JSON(http.StatusOK, gin.H{"entries": []gin.H{}, "total": 0})
		return
	}
	defer rows.Close()

	var entries []gin.H
	for rows.Next() {
		var id any // int or uuid depending on schema
		var email string
		var name, referralCode, invitedBy, wlStatus, notes *string
		var createdAt, updatedAt time.Time
		if err := rows.Scan(&id, &email, &name, &referralCode, &invitedBy, &wlStatus, &notes, &createdAt, &updatedAt); err == nil {
			entries = append(entries, gin.H{
				"id": fmt.Sprintf("%v", id), "email": email, "name": name,
				"referral_code": referralCode, "invited_by": invitedBy,
				"status": wlStatus, "notes": notes,
				"created_at": createdAt, "updated_at": updatedAt,
			})
		}
	}
	if entries == nil {
		entries = []gin.H{}
	}

	var total int
	countQuery := "SELECT COUNT(*) FROM waitlist"
	if status != "" {
		_ = h.pool.QueryRow(ctx, countQuery+" WHERE status = $1", status).Scan(&total)
	} else {
		_ = h.pool.QueryRow(ctx, countQuery).Scan(&total)
	}

	c.JSON(http.StatusOK, gin.H{"entries": entries, "total": total, "limit": limit, "offset": offset})
}

// AdminUpdateWaitlist PATCH /admin/waitlist/:id
func (h *AdminHandler) AdminUpdateWaitlist(c *gin.Context) {
	ctx := c.Request.Context()
	id := c.Param("id")

	var req struct {
		Status string `json:"status"`
		Notes  string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.pool.Exec(ctx,
		`UPDATE waitlist SET status = COALESCE(NULLIF($1,''), status), notes = COALESCE(NULLIF($2,''), notes), updated_at = NOW() WHERE id = $3`,
		req.Status, req.Notes, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update waitlist entry"})
		return
	}

	adminID, _ := c.Get("user_id")
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'waitlist_update', 'waitlist', $2, $3)`,
		adminID, id, fmt.Sprintf("status=%s", req.Status))

	c.JSON(http.StatusOK, gin.H{"message": "Updated"})
}

// AdminDeleteWaitlist DELETE /admin/waitlist/:id
func (h *AdminHandler) AdminDeleteWaitlist(c *gin.Context) {
	ctx := c.Request.Context()
	id := c.Param("id")

	_, err := h.pool.Exec(ctx, `DELETE FROM waitlist WHERE id = $1`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete waitlist entry"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Deleted"})
}

// ──────────────────────────────────────────────
// Feed Impression Reset
// ──────────────────────────────────────────────

// AdminResetFeedImpressions DELETE /admin/users/:id/feed-impressions
func (h *AdminHandler) AdminResetFeedImpressions(c *gin.Context) {
	ctx := c.Request.Context()
	userID := c.Param("id")

	result, err := h.pool.Exec(ctx, `DELETE FROM user_feed_impressions WHERE user_id = $1`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reset feed impressions"})
		return
	}

	adminID, _ := c.Get("user_id")
	h.pool.Exec(ctx, `INSERT INTO audit_log (actor_id, action, target_type, target_id, details) VALUES ($1, 'reset_feed_impressions', 'user', $2, $3)`,
		adminID, userID, "Admin reset feed impression history")

	c.JSON(http.StatusOK, gin.H{"message": "Feed impressions reset", "deleted": result.RowsAffected()})
}

// Feed scores viewer
// ──────────────────────────────────────────────────────────────────────────────

// AdminGetFeedScores GET /admin/feed-scores?limit=50
func (h *AdminHandler) AdminGetFeedScores(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := h.pool.Query(c.Request.Context(), `
		SELECT pfs.post_id,
		       LEFT(p.content, 80)  AS excerpt,
		       pfs.engagement_score,
		       pfs.quality_score,
		       pfs.recency_score,
		       pfs.network_score,
		       pfs.personalization,
		       pfs.score            AS total_score,
		       pfs.updated_at
		FROM post_feed_scores pfs
		JOIN posts p ON p.id = pfs.post_id
		WHERE p.status = 'active'
		ORDER BY pfs.score DESC
		LIMIT $1
	`, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type scoreRow struct {
		PostID          string    `json:"post_id"`
		Excerpt         string    `json:"excerpt"`
		EngagementScore float64   `json:"engagement_score"`
		QualityScore    float64   `json:"quality_score"`
		RecencyScore    float64   `json:"recency_score"`
		NetworkScore    float64   `json:"network_score"`
		Personalization float64   `json:"personalization"`
		TotalScore      float64   `json:"total_score"`
		UpdatedAt       time.Time `json:"updated_at"`
	}
	var scores []scoreRow
	for rows.Next() {
		var s scoreRow
		if err := rows.Scan(&s.PostID, &s.Excerpt, &s.EngagementScore, &s.QualityScore,
			&s.RecencyScore, &s.NetworkScore, &s.Personalization, &s.TotalScore, &s.UpdatedAt); err != nil {
			continue
		}
		scores = append(scores, s)
	}
	c.JSON(http.StatusOK, gin.H{"scores": scores})
}
