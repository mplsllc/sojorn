package handlers

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

type PostHandler struct {
	postRepo            *repository.PostRepository
	userRepo            *repository.UserRepository
	feedService         *services.FeedService
	assetService        *services.AssetService
	notificationService *services.NotificationService
	moderationService   *services.ModerationService
	contentFilter       *services.ContentFilter
	openRouterService   *services.OpenRouterService
	linkPreviewService  *services.LinkPreviewService
	localAIService      *services.LocalAIService
	videoProcessor      *services.VideoProcessor
	contentModerator    *services.ContentModerator
}

func NewPostHandler(postRepo *repository.PostRepository, userRepo *repository.UserRepository, feedService *services.FeedService, assetService *services.AssetService, notificationService *services.NotificationService, moderationService *services.ModerationService, contentFilter *services.ContentFilter, openRouterService *services.OpenRouterService, linkPreviewService *services.LinkPreviewService, localAIService *services.LocalAIService, s3Client *s3.Client, videoBucket, vidDomain string, contentModerator *services.ContentModerator) *PostHandler {
	return &PostHandler{
		postRepo:            postRepo,
		userRepo:            userRepo,
		feedService:         feedService,
		assetService:        assetService,
		notificationService: notificationService,
		moderationService:   moderationService,
		contentFilter:       contentFilter,
		openRouterService:   openRouterService,
		linkPreviewService:  linkPreviewService,
		localAIService:      localAIService,
		videoProcessor:      services.NewVideoProcessor(s3Client, videoBucket, vidDomain),
		contentModerator:    contentModerator,
	}
}

// enrichLinkPreviews populates link_preview fields on a slice of posts via batch query.
func (h *PostHandler) enrichLinkPreviews(ctx context.Context, posts []models.Post) {
	if h.linkPreviewService == nil || len(posts) == 0 {
		return
	}
	ids := make([]string, len(posts))
	for i, p := range posts {
		ids[i] = p.ID.String()
	}
	previews, err := h.linkPreviewService.EnrichPostsWithLinkPreviews(ctx, ids)
	if err != nil || len(previews) == 0 {
		return
	}
	for i := range posts {
		if lp, ok := previews[posts[i].ID.String()]; ok {
			posts[i].LinkPreviewURL = &lp.URL
			posts[i].LinkPreviewTitle = &lp.Title
			posts[i].LinkPreviewDescription = &lp.Description
			signed := h.assetService.SignImageURL(lp.ImageURL)
			posts[i].LinkPreviewImageURL = &signed
			posts[i].LinkPreviewSiteName = &lp.SiteName
		}
	}
}

// enrichSinglePostLinkPreview populates link_preview fields on a single post.
func (h *PostHandler) enrichSinglePostLinkPreview(ctx context.Context, post *models.Post) {
	if h.linkPreviewService == nil || post == nil {
		return
	}
	previews, err := h.linkPreviewService.EnrichPostsWithLinkPreviews(ctx, []string{post.ID.String()})
	if err != nil || len(previews) == 0 {
		return
	}
	if lp, ok := previews[post.ID.String()]; ok {
		post.LinkPreviewURL = &lp.URL
		post.LinkPreviewTitle = &lp.Title
		post.LinkPreviewDescription = &lp.Description
		signed := h.assetService.SignImageURL(lp.ImageURL)
		post.LinkPreviewImageURL = &signed
		post.LinkPreviewSiteName = &lp.SiteName
	}
}

func (h *PostHandler) CreateComment(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))
	postID := c.Param("id")

	var req struct {
		Body string `json:"body" binding:"required,max=500"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	parentUUID, err := uuid.Parse(postID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid post ID"})
		return
	}

	// Layer 0: Hard blocklist check — reject immediately, never save
	if h.contentFilter != nil {
		result := h.contentFilter.CheckContent(req.Body)
		if result.Blocked {
			strikeCount, consequence, _ := h.contentFilter.RecordStrikeWithIP(c.Request.Context(), userID, result.Category, req.Body, c.ClientIP())
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":       result.Message,
				"blocked":     true,
				"category":    result.Category,
				"strikes":     strikeCount,
				"consequence": consequence,
			})
			return
		}
	}

	tags := utils.ExtractHashtags(req.Body)
	tone := "neutral"
	cis := 0.8

	// AI Moderation — cascade through all admin-enabled engines
	var cachedScores *services.ThreePoisonsScore
	var cachedReason string
	commentStatus := "active"
	ctx := c.Request.Context()

	if h.contentModerator != nil {
		modResult := h.contentModerator.ModerateText(ctx, "text", req.Body)
		cachedScores = modResult.Scores
		cachedReason = modResult.Reason

		switch modResult.Action {
		case "flag":
			commentStatus = "removed"
		case "nsfw":
			commentStatus = "pending_moderation"
		}

		if cachedScores != nil {
			cis = 1.0 - (cachedScores.Hate+cachedScores.Greed+cachedScores.Delusion)/3.0
		}
	}

	post := &models.Post{
		AuthorID:       userID,
		Body:           req.Body,
		Status:         commentStatus,
		ToneLabel:      &tone,
		CISScore:       &cis,
		BodyFormat:     "plain",
		Tags:           tags,
		IsBeacon:       false,
		IsActiveBeacon: false,
		AllowChain:     true,
		Visibility:     "public",
		ChainParentID:  &parentUUID,
	}

	if err := h.postRepo.CreatePost(c.Request.Context(), post); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create comment", "details": err.Error()})
		return
	}

	comment := &models.Comment{
		ID:        post.ID,
		PostID:    postID,
		AuthorID:  post.AuthorID,
		Body:      post.Body,
		Status:    post.Status,
		CreatedAt: post.CreatedAt,
	}

	// Flag comment if needed — reuse cached scores
	if h.moderationService != nil && post.Status == "pending_moderation" && cachedScores != nil {
		_ = h.moderationService.FlagComment(c.Request.Context(), post.ID, cachedScores, cachedReason)
	}

	// Log AI moderation decision for comment — async
	if h.moderationService != nil {
		postID := post.ID
		postStatus := post.Status
		reqBody := req.Body
		go func() {
			decision := "pass"
			if postStatus == "pending_moderation" {
				decision = "flag"
			}
			invCis := 1.0 - cis
			scores := &services.ThreePoisonsScore{Hate: invCis, Greed: 0, Delusion: 0}
			h.moderationService.LogAIDecision(context.Background(), "comment", postID, userID, reqBody, scores, nil, decision, tone, "", nil)
		}()
	}

	// Get post details for notification
	rootPost, err := h.postRepo.GetPostByID(c.Request.Context(), postID, userIDStr.(string))
	if err == nil && rootPost.AuthorID.String() != userIDStr.(string) {
		// Get actor details
		actor, err := h.userRepo.GetProfileByID(c.Request.Context(), userIDStr.(string))
		if err == nil && h.notificationService != nil {
			// Determine post type for proper deep linking
			postType := "standard"
			if rootPost.IsBeacon {
				postType = "beacon"
			} else if rootPost.VideoURL != nil && *rootPost.VideoURL != "" {
				postType = "quip"
			}

			commentIDStr := comment.ID.String()
			metadata := map[string]interface{}{
				"actor_name": actor.DisplayName,
				"post_id":    postID,
				"post_type":  postType,
			}
			go h.notificationService.CreateNotification(
				context.Background(),
				rootPost.AuthorID.String(),
				userIDStr.(string),
				"comment",
				&postID,
				&commentIDStr,
				metadata,
			)
		}
	}

	c.JSON(http.StatusCreated, gin.H{"comment": comment})
}

func (h *PostHandler) GetNearbyBeacons(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryInt(c, "radius", 16000)

	beacons, err := h.postRepo.GetNearbyBeacons(c.Request.Context(), lat, long, radius)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch nearby beacons", "details": err.Error()})
		return
	}

	// Transform to beacon-specific JSON with correct field names for Flutter client
	results := make([]gin.H, 0, len(beacons))
	for _, b := range beacons {
		item := gin.H{
			"id":       b.ID,
			"body":     b.Body,
			// author_id is intentionally omitted — beacons are anonymous by policy.
			// The internal author_id is stored only for abuse prevention and is never exposed.
			"is_beacon":           true,
			"beacon_type":         b.BeaconType,
			"confidence_score":    b.Confidence,
			"is_active_beacon":    b.IsActiveBeacon,
			"created_at":          b.CreatedAt,
			"image_url":           b.ImageURL,
			"tags":                b.Tags,
			"beacon_lat":          b.Lat,
			"beacon_long":         b.Long,
			"severity":            b.Severity,
			"incident_status":     b.IncidentStatus,
			"radius":              b.Radius,
			"distance_meters":     b.DistanceMeters,
			"vouch_count":         b.LikeCount,    // mapped from vouch subquery
			"report_count":        b.CommentCount, // mapped from report subquery
			"verification_count":  b.LikeCount,    // vouches = verification
			"status_color":        beaconStatusColor(b.Confidence),
			"author_handle":       "Anonymous",
			"author_display_name": "Anonymous",
		}
		results = append(results, item)
	}

	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// fuzzyCoord rounds a coordinate to 2 decimal places (~1.1 km precision).
// This ensures no exact location is ever stored for an anonymous beacon.
func fuzzyCoord(v float64) float64 {
	return math.Round(v*100) / 100
}

// CreateBeacon creates a fully anonymous beacon pin on the map.
// author_id is NEVER stored — beacons are untraceable by design.
// Coordinates are fuzzed to ~1 km precision before storage.
// AI moderation runs for text + images — flagged beacons stay visible but go to admin review.
// Does NOT create a feed post.
func (h *PostHandler) CreateBeacon(c *gin.Context) {
	// userID is used only for rate-limiting and AI-moderation context — never stored on the beacon.
	userIDStr, _ := c.Get("user_id")
	_, _ = uuid.Parse(userIDStr.(string))

	var req struct {
		Body       string  `json:"body" binding:"required"`
		BeaconType string  `json:"beacon_type" binding:"required"`
		Lat        float64 `json:"lat" binding:"required"`
		Long       float64 `json:"long" binding:"required"`
		Severity   string  `json:"severity"`
		ImageURL   *string `json:"image_url"`
		TTLHours   *int    `json:"ttl_hours"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if req.Lat < -90 || req.Lat > 90 || req.Long < -180 || req.Long > 180 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid coordinates"})
		return
	}

	// Sanitize beacon text — replace agency/enforcement terms with neutral language.
	req.Body, _ = utils.SanitizeBeaconText(req.Body)

	severity := "medium"
	if req.Severity != "" {
		severity = req.Severity
	}

	var expiresAt *time.Time
	if req.TTLHours != nil && *req.TTLHours > 0 {
		t := time.Now().Add(time.Duration(*req.TTLHours) * time.Hour)
		expiresAt = &t
	}

	beaconType := req.BeaconType
	// Fuzz coordinates to ~1.1 km precision — no exact location stored for anonymous beacons.
	lat := fuzzyCoord(req.Lat)
	long := fuzzyCoord(req.Long)

	post := &models.Post{
		// AuthorID intentionally omitted — beacons are fully anonymous, no user linkage stored.
		Body:           req.Body,
		Status:         "active",
		BodyFormat:     "plain",
		Tags:           []string{},
		IsBeacon:       true,
		BeaconType:     &beaconType,
		Lat:            &lat,
		Long:           &long,
		Severity:       severity,
		IncidentStatus: "active",
		Radius:         500,
		Confidence:     0.5,
		IsActiveBeacon: true,
		AllowChain:     false,
		Visibility:     "public",
		ExpiresAt:      expiresAt,
		ImageURL:       req.ImageURL,
	}

	// AI Moderation — text cascade (local AI → OpenAI → OpenRouter with beacon_text config).
	modFlagged := false
	if h.contentModerator != nil {
		modResult := h.contentModerator.ModerateText(c.Request.Context(), "beacon_text", req.Body)
		switch modResult.Action {
		case "flag":
			post.Status = "removed"
			modFlagged = true
			if modResult.Scores != nil {
				cis := 1.0 - (modResult.Scores.Hate+modResult.Scores.Greed+modResult.Scores.Delusion)/3.0
				post.CISScore = &cis
			}
			post.ToneLabel = &modResult.Reason
			log.Warn().Str("reason", modResult.Reason).Str("engine", modResult.Engine).Msg("Beacon flagged — removed")
		case "nsfw":
			post.IsNSFW = true
			modFlagged = true
			log.Info().Str("reason", modResult.Reason).Msg("Beacon marked NSFW")
		}
	}

	if err := h.postRepo.CreatePost(c.Request.Context(), post); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create beacon", "details": err.Error()})
		return
	}

	// Flag for admin review if moderation triggered (beacon stays active unless "removed")
	if modFlagged && h.moderationService != nil && post.Status != "removed" {
		_ = h.moderationService.FlagPost(c.Request.Context(), post.ID, nil, "beacon_moderation_flag")
	}

	log.Info().
		Str("beacon_id", post.ID.String()).
		Str("beacon_type", beaconType).
		Str("status", post.Status).
		Bool("mod_flagged", modFlagged).
		Float64("lat", lat).
		Float64("long", long).
		Msg("Beacon created anonymously")

	// Return anonymous beacon data — no author info
	c.JSON(http.StatusCreated, gin.H{
		"beacon": gin.H{
			"id":               post.ID,
			"body":             post.Body,
			"beacon_type":      beaconType,
			"beacon_lat":       lat,
			"beacon_long":      long,
			"severity":         severity,
			"confidence_score": post.Confidence,
			"is_active_beacon": true,
			"incident_status":  "active",
			"radius":           500,
			"status_color":     beaconStatusColor(post.Confidence),
			"image_url":        post.ImageURL,
			"created_at":       post.CreatedAt,
			"vouch_count":      0,
			"report_count":     0,
		},
	})
}

// beaconStatusColor returns green/yellow/red based on confidence score.
func beaconStatusColor(confidence float64) string {
	if confidence > 0.7 {
		return "green"
	} else if confidence >= 0.3 {
		return "yellow"
	}
	return "red"
}

func (h *PostHandler) CreatePost(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req struct {
		CategoryID    *string  `json:"category_id"`
		Body          string   `json:"body" binding:"required,max=500"`
		ImageURL      *string  `json:"image_url"`
		VideoURL      *string  `json:"video_url"`
		Thumbnail     *string  `json:"thumbnail_url"`
		DurationMS    *int     `json:"duration_ms"`
		AllowChain    *bool    `json:"allow_chain"`
		ChainParentID *string  `json:"chain_parent_id"`
		IsBeacon      bool     `json:"is_beacon"`
		BeaconType    *string  `json:"beacon_type"`
		Severity      *string  `json:"severity"`
		BeaconLat     *float64 `json:"beacon_lat"`
		BeaconLong    *float64 `json:"beacon_long"`
		TTLHours      *int     `json:"ttl_hours"`
		IsNSFW        bool     `json:"is_nsfw"`
		NSFWReason    string   `json:"nsfw_reason"`
		Visibility      string   `json:"visibility"`
		OverlayJSON     *string  `json:"overlay_json"`
		AudioOverlayURL *string  `json:"audio_overlay_url"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Layer 0: Hard blocklist check — reject immediately, never save
	if h.contentFilter != nil {
		result := h.contentFilter.CheckContent(req.Body)
		if result.Blocked {
			strikeCount, consequence, _ := h.contentFilter.RecordStrikeWithIP(c.Request.Context(), userID, result.Category, req.Body, c.ClientIP())
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":       result.Message,
				"blocked":     true,
				"category":    result.Category,
				"strikes":     strikeCount,
				"consequence": consequence,
			})
			return
		}
	}

	// 1. Check rate limit (Simplification)
	trustState, err := h.userRepo.GetTrustState(c.Request.Context(), userID.String())
	if err == nil && trustState.PostsToday >= 50 { // Example hard limit
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "Daily post limit reached"})
		return
	}

	// 2. Extract tags
	tags := utils.ExtractHashtags(req.Body)

	// 3. Mock Tone Check (In production, this would call a service or AI model)
	tone := "neutral"
	cis := 0.8

	// 4. Resolve TTL
	var expiresAt *time.Time
	if req.TTLHours != nil && *req.TTLHours > 0 {
		t := time.Now().Add(time.Duration(*req.TTLHours) * time.Hour)
		expiresAt = &t
	}

	duration := 0
	if req.DurationMS != nil {
		duration = *req.DurationMS
	}

	allowChain := !req.IsBeacon
	if req.AllowChain != nil {
		allowChain = *req.AllowChain
	}

	if req.ChainParentID != nil && *req.ChainParentID != "" {
		log.Info().
			Str("chain_parent_id", *req.ChainParentID).
			Bool("allow_chain", allowChain).
			Msg("CreatePost with chain parent")
	} else {
		log.Info().
			Bool("allow_chain", allowChain).
			Msg("CreatePost without chain parent")
	}

	severity := "medium"
	if req.Severity != nil && *req.Severity != "" {
		severity = *req.Severity
	}

	post := &models.Post{
		AuthorID:       userID,
		Body:           req.Body,
		Status:         "active",
		ToneLabel:      &tone,
		CISScore:       &cis,
		ImageURL:       req.ImageURL,
		VideoURL:       req.VideoURL,
		ThumbnailURL:   req.Thumbnail,
		DurationMS:     duration,
		BodyFormat:     "plain",
		Tags:           tags,
		IsBeacon:       req.IsBeacon,
		BeaconType:     req.BeaconType,
		Severity:       severity,
		IncidentStatus: "active",
		Radius:         500,
		Confidence:     0.5, // Initial confidence
		IsActiveBeacon: req.IsBeacon,
		AllowChain:     allowChain,
		Visibility: func() string {
			switch req.Visibility {
			case "neighborhood", "followers", "only_me", "circle":
				return req.Visibility
			default:
				return "public"
			}
		}(),
		ExpiresAt:       expiresAt,
		IsNSFW:          req.IsNSFW,
		NSFWReason:      req.NSFWReason,
		Lat:             req.BeaconLat,
		Long:            req.BeaconLong,
		OverlayJSON:     req.OverlayJSON,
		AudioOverlayURL: req.AudioOverlayURL,
	}

	if req.CategoryID != nil {
		catID, _ := uuid.Parse(*req.CategoryID)
		post.CategoryID = &catID
	}

	if req.ChainParentID != nil && *req.ChainParentID != "" {
		parentID, err := uuid.Parse(*req.ChainParentID)
		if err == nil {
			post.ChainParentID = &parentID
		}
	}

	// 5. AI Moderation — cascade through all admin-enabled engines (local AI → OpenAI → OpenRouter)
	userSelfLabeledNSFW := req.IsNSFW
	orDecision := ""
	var cachedScores *services.ThreePoisonsScore
	var cachedReason string
	ctx := c.Request.Context()

	if h.contentModerator != nil {
		modResult := h.contentModerator.ModerateText(ctx, "text", req.Body)
		cachedScores = modResult.Scores
		cachedReason = modResult.Reason
		orDecision = modResult.Action

		switch modResult.Action {
		case "flag":
			post.Status = "removed"
		case "nsfw":
			post.IsNSFW = true
			if modResult.NSFWReason != "" {
				post.NSFWReason = modResult.NSFWReason
			}
		}

		if cachedScores != nil {
			cis = 1.0 - (cachedScores.Hate+cachedScores.Greed+cachedScores.Delusion)/3.0
			post.CISScore = &cis
		}
	}

	// Create post
	err = h.postRepo.CreatePost(c.Request.Context(), post)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create post", "details": err.Error()})
		return
	}

	// Handle Flags — reuse cached scores from parallel moderation (no duplicate API call)
	if h.moderationService != nil && (post.Status == "pending_moderation" || post.Status == "removed") {
		if cachedScores != nil {
			_ = h.moderationService.FlagPost(c.Request.Context(), post.ID, cachedScores, cachedReason)
		}
	}

	// NSFW auto-reclassify: AI says NSFW but user didn't self-label → send warning
	if post.IsNSFW && !userSelfLabeledNSFW && h.notificationService != nil {
		go func() {
			ctx := context.Background()
			h.notificationService.NotifyNSFWWarning(ctx, userID.String(), post.ID.String())
			log.Info().Str("post_id", post.ID.String()).Str("author_id", userID.String()).Msg("NSFW warning sent — post auto-labeled")
		}()
	}

	// NOT ALLOWED: AI flagged → post removed, create violation, send appeal notification + email
	if post.Status == "removed" && orDecision == "flag" {
		go func() {
			ctx := context.Background()

			// Send in-app notification
			if h.notificationService != nil {
				h.notificationService.NotifyContentRemoved(ctx, userID.String(), post.ID.String())
			}

			// Create moderation violation record
			if h.moderationService != nil {
				h.moderationService.FlagPost(ctx, post.ID, &services.ThreePoisonsScore{Hate: 1.0}, "not_allowed")
			}

			// Send appeal email — get email from users table, display name from profiles
			var userEmail string
			h.postRepo.Pool().QueryRow(ctx, `SELECT email FROM users WHERE id = $1`, userID).Scan(&userEmail)
			profile, _ := h.userRepo.GetProfileByID(ctx, userID.String())
			if userEmail != "" {
				displayName := "there"
				if profile != nil && profile.DisplayName != nil {
					displayName = *profile.DisplayName
				}
				snippet := req.Body
				if len(snippet) > 100 {
					snippet = snippet[:100] + "..."
				}
				appealBody := fmt.Sprintf(
					"Hi %s,\n\n"+
						"Your recent post on Sojorn was removed because it was found to violate our community guidelines.\n\n"+
						"Post content: \"%s\"\n\n"+
						"If you believe this was a mistake, you can appeal this decision in your Sojorn app:\n"+
						"Go to Profile → Settings → Appeals\n\n"+
						"Our moderation team will review your appeal within 48 hours.\n\n"+
						"— The Sojorn Team",
					displayName, snippet,
				)
				log.Info().Str("email", userEmail).Msg("Sending content removal appeal email")
				h.postRepo.Pool().Exec(ctx,
					`INSERT INTO email_queue (to_email, subject, body, created_at) VALUES ($1, $2, $3, NOW()) ON CONFLICT DO NOTHING`,
					userEmail, "Your Sojorn post was removed", appealBody,
				)
			}

			log.Warn().Str("post_id", post.ID.String()).Str("author_id", userID.String()).Msg("Post removed by AI moderation — not allowed content")
		}()
	}

	// Log AI moderation decision to audit log — async
	if h.moderationService != nil {
		postID := post.ID
		postStatus := post.Status
		postIsNSFW := post.IsNSFW
		postCIS := post.CISScore
		postTone := post.ToneLabel
		reqBody := req.Body
		go func() {
			decision := "pass"
			flagReason := ""
			if postTone != nil && *postTone != "" {
				flagReason = *postTone
			}
			if postStatus == "removed" || postStatus == "pending_moderation" {
				decision = "flag"
			} else if postIsNSFW {
				decision = "nsfw"
			}
			var scores *services.ThreePoisonsScore
			if postCIS != nil {
				invCis := 1.0 - *postCIS
				scores = &services.ThreePoisonsScore{Hate: invCis, Greed: 0, Delusion: 0}
			} else {
				scores = &services.ThreePoisonsScore{}
			}
			h.moderationService.LogAIDecision(context.Background(), "post", postID, userID, reqBody, scores, nil, decision, flagReason, orDecision, nil)
		}()
	}

	// Auto-extract link preview — fully async, never blocks the response
	if h.linkPreviewService != nil {
		linkURL := services.ExtractFirstURL(req.Body)
		if linkURL != "" {
			postID := post.ID.String()
			go func() {
				bgCtx, bgCancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer bgCancel()
				var isOfficial bool
				_ = h.postRepo.Pool().QueryRow(bgCtx, `SELECT COALESCE(is_official, false) FROM profiles WHERE id = $1`, userID).Scan(&isOfficial)
				lp, lpErr := h.linkPreviewService.FetchPreview(bgCtx, linkURL, isOfficial)
				if lpErr == nil && lp != nil {
					h.linkPreviewService.ProxyImageToR2(bgCtx, lp)
					_ = h.linkPreviewService.SaveLinkPreview(bgCtx, postID, lp)
				}
			}()
		}
	}

	// Check for @mentions and notify mentioned users
	go func() {
		if h.notificationService != nil && strings.Contains(req.Body, "@") {
			postIDStr := post.ID.String()
			h.notificationService.NotifyMention(c.Request.Context(), userIDStr.(string), postIDStr, req.Body)
		}
	}()

	c.JSON(http.StatusCreated, gin.H{
		"post": post,
		"tags": tags,
		"tone_analysis": gin.H{
			"tone": tone,
			"cis":  cis,
		},
	})
}

func (h *PostHandler) GetFeed(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)
	category := c.Query("category")
	hasVideo := c.Query("has_video") == "true"

	// Check user's NSFW preference
	showNSFW := false
	if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), userIDStr.(string)); err == nil && settings.NSFWEnabled != nil {
		showNSFW = *settings.NSFWEnabled
	}

	posts, err := h.feedService.GetFeed(c.Request.Context(), userIDStr.(string), category, hasVideo, limit, offset, showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch feed", "details": err.Error()})
		return
	}

	h.enrichLinkPreviews(c.Request.Context(), posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *PostHandler) GetProfilePosts(c *gin.Context) {
	authorID := c.Param("id")
	if authorID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Author ID required"})
		return
	}

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)
	onlyChains := c.Query("chained") == "true"

	viewerID := ""
	if val, exists := c.Get("user_id"); exists {
		viewerID = val.(string)
	}

	// Check viewer's NSFW preference
	showNSFW := false
	if viewerID != "" {
		if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), viewerID); err == nil && settings.NSFWEnabled != nil {
			showNSFW = *settings.NSFWEnabled
		}
	}

	posts, err := h.postRepo.GetPostsByAuthor(c.Request.Context(), authorID, viewerID, limit, offset, onlyChains, showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch profile posts", "details": err.Error()})
		return
	}

	h.enrichLinkPreviews(c.Request.Context(), posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *PostHandler) GetPost(c *gin.Context) {
	log.Error().Msg("=== DEBUG: GetPost handler called ===")
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	// Check viewer's NSFW preference
	showNSFW := false
	if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), userIDStr.(string)); err == nil && settings.NSFWEnabled != nil {
		showNSFW = *settings.NSFWEnabled
	}

	post, err := h.postRepo.GetPostByID(c.Request.Context(), postID, userIDStr.(string), showNSFW)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	// Sign URL
	if post.ImageURL != nil {
		signed := h.assetService.SignImageURL(*post.ImageURL)
		post.ImageURL = &signed
	}
	if post.VideoURL != nil {
		signed := h.assetService.SignVideoURL(*post.VideoURL)
		post.VideoURL = &signed
	}
	if post.ThumbnailURL != nil {
		signed := h.assetService.SignImageURL(*post.ThumbnailURL)
		post.ThumbnailURL = &signed
	}

	h.enrichSinglePostLinkPreview(c.Request.Context(), post)
	c.JSON(http.StatusOK, gin.H{"post": post})
}

func (h *PostHandler) UpdatePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	var req struct {
		Body string `json:"body" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.postRepo.UpdatePost(c.Request.Context(), postID, userIDStr.(string), req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post updated"})
}

func (h *PostHandler) DeletePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.DeletePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post deleted"})
}

func (h *PostHandler) PinPost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	var req struct {
		Pinned bool `json:"pinned"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.postRepo.PinPost(c.Request.Context(), postID, userIDStr.(string), req.Pinned)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to pin/unpin post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post pin status updated"})
}

func (h *PostHandler) UpdateVisibility(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	var req struct {
		Visibility string `json:"visibility" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.postRepo.UpdateVisibility(c.Request.Context(), postID, userIDStr.(string), req.Visibility)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update visibility", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post visibility updated"})
}

func (h *PostHandler) LikePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.LikePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like post", "details": err.Error()})
		return
	}

	// Send push notification to post author
	go func() {
		// Use Background context because the request context will be cancelled
		bgCtx := context.Background()
		post, err := h.postRepo.GetPostByID(bgCtx, postID, userIDStr.(string))
		if err != nil || post.AuthorID.String() == userIDStr.(string) {
			return // Don't notify self
		}

		if h.notificationService != nil {
			postType := "standard"
			if post.IsBeacon {
				postType = "beacon"
			} else if post.VideoURL != nil && *post.VideoURL != "" {
				postType = "quip"
			}

			h.notificationService.NotifyLike(
				bgCtx,
				post.AuthorID.String(),
				userIDStr.(string),
				postID,
				postType,
				"❤️",
			)
		}
	}()

	c.JSON(http.StatusOK, gin.H{"message": "Post liked"})
}

func (h *PostHandler) UnlikePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.UnlikePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post unliked"})
}

// HidePost records a "Not Interested" signal for a post.
// The post will be excluded from all subsequent feed queries for this user,
// and repeated hides of the same author trigger algorithmic suppression.
func (h *PostHandler) HidePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.HidePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hide post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post hidden"})
}

func (h *PostHandler) SavePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.SavePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save post", "details": err.Error()})
		return
	}

	// Send push notification to post author
	go func() {
		bgCtx := context.Background()
		post, err := h.postRepo.GetPostByID(bgCtx, postID, userIDStr.(string))
		if err != nil || post.AuthorID.String() == userIDStr.(string) {
			return // Don't notify self
		}

		actor, err := h.userRepo.GetProfileByID(bgCtx, userIDStr.(string))
		if err != nil || h.notificationService == nil {
			return
		}

		// Determine post type for proper deep linking
		postType := "standard"
		if post.IsBeacon {
			postType = "beacon"
		} else if post.VideoURL != nil && *post.VideoURL != "" {
			postType = "quip"
		}

		metadata := map[string]interface{}{
			"actor_name": actor.DisplayName,
			"post_id":    postID,
			"post_type":  postType,
		}
		h.notificationService.CreateNotification(
			context.Background(),
			post.AuthorID.String(),
			userIDStr.(string),
			"save",
			&postID,
			nil,
			metadata,
		)
	}()

	c.JSON(http.StatusOK, gin.H{"message": "Post saved"})
}

func (h *PostHandler) UnsavePost(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.UnsavePost(c.Request.Context(), postID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unsave post", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Post unsaved"})
}

func (h *PostHandler) GetSavedPosts(c *gin.Context) {
	userID := c.Param("id")
	if userID == "" || userID == "me" {
		userIDStr, exists := c.Get("user_id")
		if exists {
			userID = userIDStr.(string)
		}
	}

	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	// Check viewer's NSFW preference
	showNSFW := false
	if viewerID, exists := c.Get("user_id"); exists {
		if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), viewerID.(string)); err == nil && settings.NSFWEnabled != nil {
			showNSFW = *settings.NSFWEnabled
		}
	}

	posts, err := h.postRepo.GetSavedPosts(c.Request.Context(), userID, limit, offset, showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch saved posts", "details": err.Error()})
		return
	}

	h.enrichLinkPreviews(c.Request.Context(), posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *PostHandler) GetLikedPosts(c *gin.Context) {
	userID := c.Param("id")
	if userID == "" || userID == "me" {
		userIDStr, exists := c.Get("user_id")
		if exists {
			userID = userIDStr.(string)
		}
	}

	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	// Check viewer's NSFW preference
	showNSFW := false
	if viewerID, exists := c.Get("user_id"); exists {
		if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), viewerID.(string)); err == nil && settings.NSFWEnabled != nil {
			showNSFW = *settings.NSFWEnabled
		}
	}

	posts, err := h.postRepo.GetLikedPosts(c.Request.Context(), userID, limit, offset, showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch liked posts", "details": err.Error()})
		return
	}

	h.enrichLinkPreviews(c.Request.Context(), posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *PostHandler) GetPostChain(c *gin.Context) {
	postID := c.Param("id")

	// Check viewer's NSFW preference
	showNSFW := false
	if viewerID, exists := c.Get("user_id"); exists {
		if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), viewerID.(string)); err == nil && settings.NSFWEnabled != nil {
			showNSFW = *settings.NSFWEnabled
		}
	}

	posts, err := h.postRepo.GetPostChain(c.Request.Context(), postID, showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch post chain", "details": err.Error()})
		return
	}

	// Sign URLs for all posts in the chain
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

	h.enrichLinkPreviews(c.Request.Context(), posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func (h *PostHandler) GetPostFocusContext(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	// Check viewer's NSFW preference
	showNSFW := false
	if settings, err := h.userRepo.GetUserSettings(c.Request.Context(), userIDStr.(string)); err == nil && settings.NSFWEnabled != nil {
		showNSFW = *settings.NSFWEnabled
	}

	focusContext, err := h.postRepo.GetPostFocusContext(c.Request.Context(), postID, userIDStr.(string), showNSFW)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch focus context", "details": err.Error()})
		return
	}

	h.signPostMedia(focusContext.TargetPost)
	h.signPostMedia(focusContext.ParentPost)
	for i := range focusContext.Children {
		h.signPostMedia(&focusContext.Children[i])
	}

	// Enrich link previews for all posts in focus context
	h.enrichSinglePostLinkPreview(c.Request.Context(), focusContext.TargetPost)
	h.enrichSinglePostLinkPreview(c.Request.Context(), focusContext.ParentPost)
	for i := range focusContext.Children {
		h.enrichSinglePostLinkPreview(c.Request.Context(), &focusContext.Children[i])
	}

	c.JSON(http.StatusOK, focusContext)
}

func (h *PostHandler) signPostMedia(post *models.Post) {
	if post == nil {
		return
	}
	if post.ImageURL != nil {
		signed := h.assetService.SignImageURL(*post.ImageURL)
		post.ImageURL = &signed
	}
	if post.VideoURL != nil {
		signed := h.assetService.SignVideoURL(*post.VideoURL)
		post.VideoURL = &signed
	}
	if post.ThumbnailURL != nil {
		signed := h.assetService.SignImageURL(*post.ThumbnailURL)
		post.ThumbnailURL = &signed
	}
}

func (h *PostHandler) VouchBeacon(c *gin.Context) {
	beaconID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.VouchBeacon(c.Request.Context(), beaconID, userIDStr.(string))
	if err != nil {
		if err.Error() == "post is not a beacon" {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to vouch for beacon", "details": err.Error()})
		return
	}

	// Beacons are anonymous — no notifications sent to preserve privacy

	c.JSON(http.StatusOK, gin.H{"message": "Beacon vouched successfully"})
}

func (h *PostHandler) ReportBeacon(c *gin.Context) {
	beaconID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.ReportBeacon(c.Request.Context(), beaconID, userIDStr.(string))
	if err != nil {
		if err.Error() == "post is not a beacon" {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to report beacon", "details": err.Error()})
		return
	}

	// Beacons are anonymous — no notifications sent to preserve privacy

	c.JSON(http.StatusOK, gin.H{"message": "Beacon reported successfully"})
}

func (h *PostHandler) RemoveBeaconVote(c *gin.Context) {
	beaconID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	err := h.postRepo.RemoveBeaconVote(c.Request.Context(), beaconID, userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove beacon vote", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Beacon vote removed successfully"})
}

func (h *PostHandler) ToggleReaction(c *gin.Context) {
	postID := c.Param("id")
	userIDStr, _ := c.Get("user_id")

	var req struct {
		Emoji string `json:"emoji" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	emoji := strings.TrimSpace(req.Emoji)
	if emoji == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Emoji is required"})
		return
	}

	counts, myReactions, err := h.postRepo.ToggleReaction(c.Request.Context(), postID, userIDStr.(string), emoji)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to toggle reaction", "details": err.Error()})
		return
	}

	// Check if reaction was added (exists in myReactions)
	reactionAdded := false
	for _, r := range myReactions {
		if r == emoji {
			reactionAdded = true
			break
		}
	}

	if reactionAdded {
		go func() {
			bgCtx := context.Background()
			post, err := h.postRepo.GetPostByID(bgCtx, postID, userIDStr.(string))
			if err != nil || post.AuthorID.String() == userIDStr.(string) {
				return // Don't notify self
			}

			if h.notificationService != nil {
				// Get actor details
				actor, err := h.userRepo.GetProfileByID(bgCtx, userIDStr.(string))
				if err != nil {
					return
				}

				metadata := map[string]interface{}{
					"actor_name": actor.DisplayName,
					"post_id":    postID,
					"emoji":      emoji,
				}

				// Using "like" type for now, or "quip_reaction" if quip
				notifType := "like"
				if post.VideoURL != nil && *post.VideoURL != "" {
					notifType = "quip_reaction"
					metadata["post_type"] = "quip"
				} else {
					metadata["post_type"] = "post"
				}

				h.notificationService.CreateNotification(
					bgCtx,
					post.AuthorID.String(),
					userIDStr.(string),
					notifType,
					&postID,
					nil,
					metadata,
				)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"reactions":    counts,
		"my_reactions": myReactions,
	})
}

// GetSafeDomains returns the list of approved safe domains for the Flutter app.
func (h *PostHandler) GetSafeDomains(c *gin.Context) {
	if h.linkPreviewService == nil {
		c.JSON(http.StatusOK, gin.H{"domains": []string{}})
		return
	}
	domains, err := h.linkPreviewService.ListSafeDomains(c.Request.Context(), "", true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"domains": domains})
}

// CheckURLSafety checks if a URL is from a safe domain.
func (h *PostHandler) CheckURLSafety(c *gin.Context) {
	urlStr := c.Query("url")
	if urlStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url parameter required"})
		return
	}
	if h.linkPreviewService == nil {
		c.JSON(http.StatusOK, gin.H{"safe": false, "status": "unknown"})
		return
	}
	result := h.linkPreviewService.CheckURLSafety(c.Request.Context(), urlStr)
	c.JSON(http.StatusOK, result)
}
