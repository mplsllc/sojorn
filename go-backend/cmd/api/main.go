// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	aws "github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/middleware"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/monitoring"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/realtime"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

func main() {
	cfg := config.LoadConfig()

	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339})

	if cfg.DatabaseURL == "" {
		log.Fatal().Msg("DATABASE_URL is not set")
	}

	pgxConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("Unable to parse database config")
	}

	dbPool, err := pgxpool.NewWithConfig(context.Background(), pgxConfig)
	if err != nil {
		log.Fatal().Err(err).Msg("Unable to connect to database")
	}
	defer dbPool.Close()

	// Background service context — cancelled when the server shuts down.
	bgCtx, bgCancel := context.WithCancel(context.Background())
	defer bgCancel()

	if err := dbPool.Ping(context.Background()); err != nil {
		log.Fatal().Err(err).Msg("Unable to ping database")
	}

	r := gin.Default()

	allowedOrigins := strings.Split(cfg.CORSOrigins, ",")
	allowAllOrigins := false
	allowedOriginSet := make(map[string]struct{}, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		trimmed := strings.TrimSpace(origin)
		if trimmed == "" {
			continue
		}
		if trimmed == "*" {
			allowAllOrigins = true
			break
		}
		allowedOriginSet[trimmed] = struct{}{}
	}

	isProduction := cfg.Env == "production"
	r.Use(cors.New(cors.Config{
		AllowOriginFunc: func(origin string) bool {
			if allowAllOrigins {
				return true
			}
			// Only allow localhost origins in non-production environments
			if !isProduction {
				if strings.HasPrefix(origin, "http://localhost") ||
					strings.HasPrefix(origin, "https://localhost") ||
					strings.HasPrefix(origin, "http://127.0.0.1") ||
					strings.HasPrefix(origin, "https://127.0.0.1") {
					return true
				}
			}
			_, ok := allowedOriginSet[origin]
			return ok
		},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization", "X-Request-ID", "X-Timestamp", "X-Signature", "X-Algorithm"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Sojorn is a private community — instruct all crawlers not to index any content.
	r.GET("/robots.txt", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/plain; charset=utf-8", []byte(
			"User-agent: *\nDisallow: /\n",
		))
	})

	// Attach X-Robots-Tag to every API response so crawlers that ignore robots.txt
	// also receive an explicit noindex directive.
	r.Use(func(c *gin.Context) {
		c.Header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
		c.Next()
	})

	r.NoRoute(func(c *gin.Context) {
		log.Debug().Msgf("No route found for %s %s", c.Request.Method, c.Request.URL.Path)
		c.JSON(404, gin.H{"error": "route not found", "path": c.Request.URL.Path, "method": c.Request.Method})
	})

	userRepo := repository.NewUserRepository(dbPool)
	postRepo := repository.NewPostRepository(dbPool)
	chatRepo := repository.NewChatRepository(dbPool)
	categoryRepo := repository.NewCategoryRepository(dbPool)
	notifRepo := repository.NewNotificationRepository(dbPool)
	tagRepo := repository.NewTagRepository(dbPool)

	// Refresh trending hashtag scores periodically (every 15 min) so Discover page has data
	go func() {
		if err := tagRepo.RefreshTrendingScores(context.Background()); err != nil {
			log.Warn().Err(err).Msg("Initial trending score refresh failed")
		}
		ticker := time.NewTicker(15 * time.Minute)
		for range ticker.C {
			if err := tagRepo.RefreshTrendingScores(context.Background()); err != nil {
				log.Warn().Err(err).Msg("Trending score refresh failed")
			}
		}
	}()

	assetService := services.NewAssetService(cfg.R2SigningSecret, cfg.R2PublicBaseURL, cfg.R2ImgDomain, cfg.R2VidDomain)
	feedAlgorithmService := services.NewFeedAlgorithmService(dbPool)
	feedService := services.NewFeedService(postRepo, assetService, feedAlgorithmService)

	pushService, err := services.NewPushService(userRepo, cfg.FirebaseCredentialsFile)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to initialize PushService")
	}

	notificationService := services.NewNotificationService(notifRepo, pushService, userRepo)

	emailService := services.NewEmailService(cfg, dbPool)
	sendPulseService := services.NewSendPulseService(cfg.SendPulseID, cfg.SendPulseSecret)

	// Initialize moderation service (DB operations)
	moderationService := services.NewModerationService(dbPool)

	// Initialize appeal service
	appealService := services.NewAppealService(dbPool)

	// Initialize SightEngine service (text + image moderation API)
	sightEngineService := services.NewSightEngineService(cfg.SightEngineUser, cfg.SightEngineSecret)
	if sightEngineService != nil {
		log.Info().Msg("SightEngine service initialized")
	} else {
		log.Warn().Msg("SightEngine credentials not provided, SightEngine service disabled")
	}

	// Initialize content filter (hard blocklist + strike system)
	contentFilter := services.NewContentFilter(dbPool)

	// Initialize local AI gateway service (on-server Ollama via localhost:8099)
	localAIService := services.NewLocalAIService(cfg.AIGatewayURL, cfg.AIGatewayToken)
	if localAIService != nil {
		log.Info().Str("url", cfg.AIGatewayURL).Msg("Local AI gateway configured")
	} else {
		log.Info().Msg("Local AI gateway not configured (AI_GATEWAY_URL not set)")
	}

	hub := realtime.NewHub()
	wsHandler := handlers.NewWSHandler(hub, cfg.JWTSecret)

	var s3Client *s3.Client
	if cfg.R2AccessKey != "" && cfg.R2SecretKey != "" && cfg.R2Endpoint != "" {
		resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
			return aws.Endpoint{URL: cfg.R2Endpoint, PartitionID: "aws", SigningRegion: "auto"}, nil
		})
		awsCfg, err := awsconfig.LoadDefaultConfig(
			context.Background(),
			awsconfig.WithRegion("auto"),
			awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(cfg.R2AccessKey, cfg.R2SecretKey, "")),
			awsconfig.WithEndpointResolverWithOptions(resolver),
		)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to load AWS/R2 config, falling back to R2 API token flow")
		} else {
			s3Client = s3.NewFromConfig(awsCfg)
		}
	}

	// Initialize link preview service (after S3 client setup)
	linkPreviewService := services.NewLinkPreviewService(dbPool, s3Client, cfg.R2MediaBucket, cfg.R2ImgDomain)

	// Shared content moderation cascade (local AI → SightEngine → fail-open)
	contentModerator := services.NewContentModerator(localAIService, sightEngineService, moderationService)

	userHandler := handlers.NewUserHandler(userRepo, postRepo, notificationService, assetService)
	postHandler := handlers.NewPostHandler(postRepo, userRepo, feedService, assetService, notificationService, moderationService, contentFilter, linkPreviewService, localAIService, s3Client, cfg.R2VideoBucket, cfg.R2VidDomain, contentModerator)
	chatHandler := handlers.NewChatHandler(chatRepo, notificationService, hub)
	mfaRepo := repository.NewMFARepository(dbPool)
	totpService := services.NewTOTPService()
	authHandler := handlers.NewAuthHandler(userRepo, cfg, emailService, sendPulseService, mfaRepo, totpService)
	categoryHandler := handlers.NewCategoryHandler(categoryRepo)
	keyHandler := handlers.NewKeyHandler(userRepo)
	backupHandler := handlers.NewBackupHandler(repository.NewBackupRepository(dbPool))
	settingsHandler := handlers.NewSettingsHandler(userRepo, notifRepo)
	analysisHandler := handlers.NewAnalysisHandler()
	appealHandler := handlers.NewAppealHandler(appealService)

	// Initialize official accounts service
	officialAccountsService := services.NewOfficialAccountsService(dbPool, localAIService, linkPreviewService)
	officialAccountsService.StartScheduler()
	defer officialAccountsService.StopScheduler()

	icedHandler := handlers.NewIcedHandler(cfg.IcedAPIBase)
	moderationHandler := handlers.NewModerationHandler(moderationService, sightEngineService, localAIService)

	// Unified beacon alerts system
	beaconAlertRepo := repository.NewBeaconAlertRepository(dbPool)
	beaconUnifiedHandler := handlers.NewBeaconUnifiedHandler(beaconAlertRepo)
	beaconIngestion := services.NewBeaconIngestionService(beaconAlertRepo, "http://127.0.0.1:8787", cfg.IcedAPIBase, s3Client, cfg.R2MediaBucket, cfg.R2ImgDomain)
	beaconIngestion.Start()
	defer beaconIngestion.Stop()

	adminHandler := handlers.NewAdminHandler(dbPool, moderationService, appealService, emailService, sightEngineService, officialAccountsService, linkPreviewService, localAIService, beaconAlertRepo, beaconIngestion, feedAlgorithmService, cfg.JWTSecret, cfg.Env == "production", s3Client, cfg.R2MediaBucket, cfg.R2VideoBucket, cfg.R2ImgDomain, cfg.R2VidDomain)

	accountHandler := handlers.NewAccountHandler(userRepo, emailService, cfg)

	// Capsule system handlers (E2EE groups)
	capsuleHandler := handlers.NewCapsuleHandler(dbPool)
	capsuleEscrowHandler := handlers.NewCapsuleEscrowHandler(dbPool)

	// Group feature handler (posts, chat, forum, members)
	groupHandler := handlers.NewGroupHandler(dbPool, notificationService)

	// Neighborhood board handler (standalone message board)
	boardHandler := handlers.NewBoardHandler(dbPool, contentFilter, moderationService, contentModerator, notificationService)

	// Beacon search handler (search beacons, board, public groups)
	beaconSearchHandler := handlers.NewBeaconSearchHandler(dbPool)

	mediaHandler := handlers.NewMediaHandler(
		s3Client,
		cfg.R2AccountID,
		cfg.R2APIToken,
		cfg.R2MediaBucket,
		cfg.R2VideoBucket,
		cfg.R2ImgDomain,
		cfg.R2VidDomain,
	)

	// Health check service
	hcService := monitoring.NewHealthCheckService(dbPool)

	// Repost & profile layout handlers
	repostHandler := handlers.NewRepostHandler(dbPool)
	profileLayoutHandler := handlers.NewProfileLayoutHandler(dbPool)

	// Image proxy (CORS bypass for web.archive.org, imgur, giphy)
	imageProxyHandler := handlers.NewImageProxyHandler()

	// Audio library proxy (Freesound — gracefully returns 503 until FREESOUND_API_KEY is set)
	audioHandler := handlers.NewAudioHandler(cfg.FreesoundAPIKey)

	// Group events handler
	eventHandler := handlers.NewEventHandler(dbPool)

	// Dashboard layout handler (customizable home page widgets)
	dashboardLayoutHandler := handlers.NewDashboardLayoutHandler(dbPool)

	// Harmony Score calculator — daily trust recalculation (Discourse-inspired, clean-room)
	harmonyCalc := services.NewHarmonyCalculator(dbPool)
	harmonyCalc.ScheduleDailyRecalculation(bgCtx)

	// Event ingestion — fetch from Eventbrite & Ticketmaster every 2 hours
	if cfg.EventbriteAPIKey != "" || cfg.TicketmasterAPIKey != "" {
		eventIngestion := services.NewEventIngestionService(dbPool, cfg.EventbriteAPIKey, cfg.TicketmasterAPIKey)
		go func() {
			// Initial sync after 30s delay (let other services start first)
			time.Sleep(30 * time.Second)
			if err := eventIngestion.SyncAll(context.Background()); err != nil {
				log.Warn().Err(err).Msg("Initial event ingestion sync failed")
			}
			ticker := time.NewTicker(2 * time.Hour)
			defer ticker.Stop()
			for range ticker.C {
				if err := eventIngestion.SyncAll(context.Background()); err != nil {
					log.Warn().Err(err).Msg("Event ingestion sync failed")
				}
			}
		}()
		log.Info().Msg("Event ingestion service started (Eventbrite + Ticketmaster)")
	}

	r.GET("/ws", wsHandler.ServeWS)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(200)
	})
	r.GET("/health/detailed", gin.WrapF(hcService.HealthCheckHandler))
	r.GET("/health/ready", gin.WrapF(hcService.ReadinessHandler))
	r.GET("/health/live", gin.WrapF(hcService.LivenessHandler))

	// ALTCHA challenge endpoints (direct to main router for testing)
	r.GET("/api/v1/auth/altcha-challenge", authHandler.GetAltchaChallenge)
	r.GET("/api/v1/admin/altcha-challenge", adminHandler.GetAltchaChallenge)
	r.GET("/api/v1/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"message": "Route test successful"})
	})

	v1 := r.Group("/api/v1")
	{
		// Public waitlist signup (no auth required)
		waitlist := v1.Group("/waitlist")
		waitlist.Use(middleware.RateLimit(0.2, 3))
		{
			waitlist.POST("", func(c *gin.Context) {
				var req struct {
					Email string `json:"email" binding:"required,email"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": "Valid email required"})
					return
				}
				// Store locally
				_, err := dbPool.Exec(c.Request.Context(),
					`INSERT INTO public.waitlist (email) VALUES ($1) ON CONFLICT (email) DO NOTHING`, req.Email)
				if err != nil {
					c.JSON(500, gin.H{"error": "Failed to join waitlist"})
					return
				}
				// Add to SendPulse waitlist in background
				go sendPulseService.AddToWaitlist(req.Email)
				c.JSON(200, gin.H{"message": "You're on the list!"})
			})
		}

		// Image proxy (public — no auth needed, CORS bypass for Flutter web)
		v1.GET("/image-proxy", imageProxyHandler.ProxyImage)

		auth := v1.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/signup", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.RefreshSession)
			auth.POST("/resend-verification", authHandler.ResendVerificationEmail)
			auth.GET("/verify", authHandler.VerifyEmail)
			auth.POST("/forgot-password", authHandler.ForgotPassword)
			auth.POST("/reset-password", authHandler.ResetPassword)
			auth.POST("/mfa/verify", authHandler.VerifyMFA) // No auth — user is mid-login
		}

		authorized := v1.Group("")
		authorized.Use(middleware.AuthMiddleware(cfg.JWTSecret, dbPool))
		{
			authorized.GET("/profiles/:id", userHandler.GetProfile)
			authorized.GET("/profile", userHandler.GetProfile)
			authorized.PATCH("/profile", userHandler.UpdateProfile)
			authorized.POST("/complete-onboarding", authHandler.CompleteOnboarding)
			authorized.POST("/auth/mfa/setup", authHandler.SetupMFA)
			authorized.POST("/auth/mfa/confirm", authHandler.ConfirmMFA)
			authorized.POST("/auth/mfa/disable", authHandler.DisableMFA)
			authorized.GET("/profile/trust-state", userHandler.GetTrustState)

			settings := authorized.Group("/settings")
			{
				settings.GET("/privacy", settingsHandler.GetPrivacySettings)
				settings.PATCH("/privacy", settingsHandler.UpdatePrivacySettings)
				settings.GET("/user", settingsHandler.GetUserSettings)
				settings.PATCH("/user", settingsHandler.UpdateUserSettings)
			}

			users := authorized.Group("/users")
			{
				users.POST("/:id/follow", userHandler.Follow)
				users.DELETE("/:id/follow", userHandler.Unfollow)
				users.POST("/:id/accept", userHandler.AcceptFollowRequest)
				users.DELETE("/:id/reject", userHandler.RejectFollowRequest)
				users.GET("/requests", userHandler.GetPendingFollowRequests)
				users.GET("/:id/posts", postHandler.GetProfilePosts)
				users.GET("/:id/saved", userHandler.GetSavedPosts)
				users.GET("/me/liked", userHandler.GetLikedPosts)
				users.POST("/:id/block", userHandler.BlockUser)
				users.DELETE("/:id/block", userHandler.UnblockUser)
				users.GET("/blocked", userHandler.GetBlockedUsers)
				users.POST("/report", userHandler.ReportUser)
				users.POST("/block_by_handle", userHandler.BlockUserByHandle)
				users.POST("/me/blocks/bulk", userHandler.BulkBlockUsers)

				// Social Graph: Followers & Following
				users.GET("/:id/followers", userHandler.GetFollowers)
				users.GET("/:id/following", userHandler.GetFollowing)

				// Circle Management
				users.POST("/circle/:id", userHandler.AddToCircle)
				users.DELETE("/circle/:id", userHandler.RemoveFromCircle)
				users.GET("/circle/members", userHandler.GetCircleMembers)

				// Data Export
				users.GET("/me/export", userHandler.ExportData)

			}

			authorized.POST("/posts", postHandler.CreatePost)
			authorized.GET("/posts/:id", postHandler.GetPost)
			authorized.GET("/posts/:id/chain", postHandler.GetPostChain)
			authorized.GET("/posts/:id/thread", postHandler.GetPostChain)
			authorized.GET("/posts/:id/focus-context", postHandler.GetPostFocusContext)
			authorized.PATCH("/posts/:id", postHandler.UpdatePost)
			authorized.DELETE("/posts/:id", postHandler.DeletePost)
			authorized.POST("/posts/:id/pin", postHandler.PinPost)
			authorized.PATCH("/posts/:id/visibility", postHandler.UpdateVisibility)
			authorized.POST("/posts/:id/hide", postHandler.HidePost)
			authorized.POST("/posts/:id/view", postHandler.RecordView)
			authorized.GET("/posts/:id/score", postHandler.GetPostScore)
			authorized.POST("/posts/:id/like", postHandler.LikePost)
			authorized.DELETE("/posts/:id/like", postHandler.UnlikePost)
			authorized.POST("/posts/:id/save", postHandler.SavePost)
			authorized.DELETE("/posts/:id/save", postHandler.UnsavePost)
			authorized.POST("/posts/:id/reactions/toggle", postHandler.ToggleReaction)
			authorized.POST("/posts/:id/comments", postHandler.CreateComment)
			authorized.GET("/feed", postHandler.GetFeed)
			authorized.GET("/feed/personal", postHandler.GetFeed)
			authorized.GET("/feed/sojorn", postHandler.GetSojornFeed)
			authorized.POST("/beacons", middleware.UserRateLimit(3.0/3600.0, 3), postHandler.CreateBeacon)
			authorized.GET("/beacons/nearby", postHandler.GetNearbyBeacons)
			authorized.GET("/beacons/unified", beaconUnifiedHandler.GetUnifiedBeacons)
			authorized.GET("/beacons/official", postHandler.GetOfficialAlerts)
			authorized.GET("/beacons/cameras", beaconUnifiedHandler.GetAllCameras)
			authorized.GET("/beacons/signs", postHandler.GetOfficialSigns)
			authorized.GET("/beacons/weather", postHandler.GetOfficialWeatherStations)
			authorized.GET("/beacons/iced", icedHandler.GetIcedAlerts)
			authorized.POST("/beacons/:id/vouch", postHandler.VouchBeacon)
			authorized.POST("/beacons/:id/report", postHandler.ReportBeacon)
			authorized.POST("/beacons/:id/resolve", postHandler.ResolveBeacon)
			authorized.DELETE("/beacons/:id/vouch", postHandler.RemoveBeaconVote)
			authorized.GET("/categories", categoryHandler.GetCategories)
			authorized.POST("/categories/settings", categoryHandler.SetUserCategorySettings)
			authorized.GET("/categories/settings", categoryHandler.GetUserCategorySettings)
			authorized.POST("/analysis/tone", analysisHandler.CheckTone)
			authorized.POST("/moderate", moderationHandler.CheckContent)

			// User reports
			authorized.GET("/reports/mine", userHandler.GetMyReports)

			// Chat routes
			authorized.GET("/conversations", chatHandler.GetConversations)
			authorized.GET("/conversation", chatHandler.GetOrCreateConversation)
			authorized.POST("/messages", chatHandler.SendMessage)
			authorized.GET("/conversations/:id/messages", chatHandler.GetMessages)
			authorized.DELETE("/conversations/:id", chatHandler.DeleteConversation)
			authorized.DELETE("/messages/:id", chatHandler.DeleteMessage)
			authorized.POST("/messages/:id/reactions", chatHandler.AddReaction)
			authorized.DELETE("/messages/:id/reactions", chatHandler.RemoveReaction)
			authorized.GET("/mutual-follows", chatHandler.GetMutualFollows)

			// Key routes
			authorized.POST("/keys", keyHandler.PublishKeys)
			authorized.GET("/keys/:id", keyHandler.GetKeyBundle)
			authorized.DELETE("/keys/otk/:keyId", keyHandler.DeleteUsedOTK)

			backupGroup := authorized.Group("/backup")
			{
				backupGroup.POST("/sync/generate-code", backupHandler.GenerateSyncCode)
				backupGroup.POST("/sync/verify-code", backupHandler.VerifySyncCode)
				backupGroup.POST("/upload", backupHandler.UploadBackup)
				backupGroup.GET("/download", backupHandler.DownloadBackup)
				backupGroup.GET("/download/:backupId", backupHandler.DownloadBackup)
				backupGroup.GET("/list", backupHandler.ListBackups)
				backupGroup.DELETE("/:backupId", backupHandler.DeleteBackup)
				backupGroup.GET("/preferences", backupHandler.GetBackupPreferences)
				backupGroup.PUT("/preferences", backupHandler.UpdateBackupPreferences)
			}

			recoveryGroup := authorized.Group("/recovery")
			{
				recoveryGroup.POST("/social/setup", backupHandler.SetupSocialRecovery)
				recoveryGroup.POST("/initiate", backupHandler.InitiateRecovery)
				recoveryGroup.POST("/submit-shard", backupHandler.SubmitShard)
				recoveryGroup.POST("/complete/:sessionId", backupHandler.CompleteRecovery)
			}

			// Device management routes
			authorized.GET("/devices", backupHandler.GetUserDevices)

			// Media routes
			authorized.POST("/upload", mediaHandler.Upload)
			authorized.GET("/media/sign", mediaHandler.GetSignedMediaURL)
			// Search & Discover routes
			discoverHandler := handlers.NewDiscoverHandler(userRepo, postRepo, tagRepo, categoryRepo, assetService)
			authorized.GET("/search", discoverHandler.Search)
			authorized.GET("/discover", discoverHandler.GetDiscover)
			authorized.GET("/hashtags/trending", discoverHandler.GetTrendingHashtags)
			authorized.GET("/hashtags/following", discoverHandler.GetFollowedHashtags)
			authorized.GET("/hashtags/:name", discoverHandler.GetHashtagPage)
			authorized.POST("/hashtags/:name/follow", discoverHandler.FollowHashtag)
			authorized.DELETE("/hashtags/:name/follow", discoverHandler.UnfollowHashtag)

			// User by-handle lookup (used by capsule invite to resolve public keys)
			authorized.GET("/users/by-handle/:handle", userHandler.GetUserByHandle)

			// Follow System (unique routes only — followers/following covered by users group above)
			followHandler := handlers.NewFollowHandler(dbPool)
			authorized.GET("/users/:id/is-following", followHandler.IsFollowing)
			authorized.GET("/users/:id/mutual-followers", followHandler.GetMutualFollowers)
			authorized.GET("/users/suggested", followHandler.GetSuggestedUsers)

			// Notifications
			notificationHandler := handlers.NewNotificationHandler(notifRepo, notificationService, dbPool)
			authorized.GET("/notifications", notificationHandler.GetNotifications)
			authorized.GET("/notifications/unread", notificationHandler.GetUnreadCount)
			authorized.GET("/notifications/badge", notificationHandler.GetBadgeCount)
			authorized.PUT("/notifications/:id/read", notificationHandler.MarkAsRead)
			authorized.POST("/notifications/read", notificationHandler.BulkMarkAsRead)
			authorized.PUT("/notifications/read-all", notificationHandler.MarkAllAsRead)
			authorized.POST("/notifications/archive", notificationHandler.Archive)
			authorized.POST("/notifications/archive-all", notificationHandler.ArchiveAll)
			authorized.DELETE("/notifications/:id", notificationHandler.DeleteNotification)
			authorized.GET("/notifications/preferences", notificationHandler.GetNotificationPreferences)
			authorized.PUT("/notifications/preferences", notificationHandler.UpdateNotificationPreferences)
			authorized.POST("/notifications/device", notificationHandler.RegisterDevice)
			authorized.DELETE("/notifications/device", notificationHandler.UnregisterDevice)
			authorized.DELETE("/notifications/devices", notificationHandler.UnregisterAllDevices)

			// Activity Log (user's own actions)
			authorized.GET("/users/me/activity", notificationHandler.GetActivityLog)

			// Safe domains (for external link warnings in app)
			authorized.GET("/safe-domains", postHandler.GetSafeDomains)
			authorized.GET("/safe-domains/check", postHandler.CheckURLSafety)

			// Account Lifecycle routes
			account := authorized.Group("/account")
			{
				account.GET("/status", accountHandler.GetAccountStatus)
				account.POST("/deactivate", accountHandler.DeactivateAccount)
				account.DELETE("", accountHandler.DeleteAccount)
				account.POST("/cancel-deletion", accountHandler.CancelDeletion)
				account.POST("/destroy", accountHandler.RequestImmediateDestroy)
			}

			// Appeal System routes
			appeals := authorized.Group("/appeals")
			{
				appeals.GET("", appealHandler.GetUserViolations)
				appeals.GET("/summary", appealHandler.GetUserViolationSummary)
				appeals.POST("", appealHandler.CreateAppeal)
				appeals.GET("/:id", appealHandler.GetAppeal)
			}

			// Neighborhood board (standalone message board — NOT posts)
			board := authorized.Group("/board")
			{
				board.GET("/nearby", boardHandler.ListNearby)
				board.POST("", boardHandler.CreateEntry)
				board.GET("/:id", boardHandler.GetEntry)
				board.POST("/:id/replies", boardHandler.CreateReply)
				board.POST("/vote", boardHandler.ToggleVote)
				board.POST("/:id/remove", boardHandler.RemoveEntry)
				board.PATCH("/:id/tag", boardHandler.UpdateTag)
				board.POST("/:id/flag", boardHandler.FlagEntry)
			}

			// Beacon ecosystem search (beacons, board entries, public groups — never private)
			authorized.GET("/beacon/search", beaconSearchHandler.Search)

			// Neighborhood system (on-demand OSM detection + auto-join)
			neighborhoodHandler := handlers.NewNeighborhoodHandler(dbPool)
			neighborhoods := authorized.Group("/neighborhoods")
			{
				neighborhoods.GET("/detect", neighborhoodHandler.Detect)
				neighborhoods.GET("/current", neighborhoodHandler.GetCurrent)
				neighborhoods.GET("/search", neighborhoodHandler.SearchByZip)
				neighborhoods.POST("/choose", neighborhoodHandler.Choose)
				neighborhoods.GET("/mine", neighborhoodHandler.GetMyNeighborhood)

				// Neighborhood moderation (admin/owner only)
				neighborhoods.GET("/:id/reports", neighborhoodHandler.GetNeighborhoodReports)
				neighborhoods.PATCH("/:id/reports/:reportId", neighborhoodHandler.UpdateNeighborhoodReport)
			}

			// Groups system (community groups with discovery and membership)
			groupsHandler := handlers.NewGroupsHandler(dbPool)
			groups := authorized.Group("/groups")
			{
				groups.GET("", groupsHandler.ListGroups)                                          // List all groups with optional category filter
				groups.GET("/mine", groupsHandler.GetMyGroups)                                    // Get user's joined groups
				groups.GET("/suggested", groupsHandler.GetSuggestedGroups)                        // Get suggested groups
				groups.POST("", groupsHandler.CreateGroup)                                        // Create new group
				groups.GET("/:id", groupsHandler.GetGroup)                                        // Get group details
				groups.POST("/:id/join", groupsHandler.JoinGroup)                                 // Join group or request to join
				groups.POST("/:id/leave", groupsHandler.LeaveGroup)                               // Leave group
				groups.GET("/:id/members", groupsHandler.GetGroupMembers)                         // Get group members
				groups.GET("/:id/requests", groupsHandler.GetPendingRequests)                     // Get pending join requests (admin)
				groups.POST("/:id/requests/:requestId/approve", groupsHandler.ApproveJoinRequest) // Approve join request
				groups.POST("/:id/requests/:requestId/reject", groupsHandler.RejectJoinRequest)   // Reject join request
				groups.GET("/:id/feed", groupsHandler.GetGroupFeed)
				groups.GET("/:id/key-status", groupsHandler.GetGroupKeyStatus)
				groups.POST("/:id/keys", groupsHandler.DistributeGroupKeys)
				groups.GET("/:id/members/public-keys", groupsHandler.GetGroupMemberPublicKeys)
				groups.POST("/:id/invite-member", groupsHandler.InviteMember)
				groups.DELETE("/:id/members/:userId", groupsHandler.RemoveMember)
				groups.PATCH("/:id/settings", groupsHandler.UpdateGroupSettings)

				// Group events
				groups.POST("/:id/events", eventHandler.CreateEvent)
				groups.GET("/:id/events", eventHandler.ListGroupEvents)
				groups.GET("/:id/events/:eventId", eventHandler.GetEvent)
				groups.PATCH("/:id/events/:eventId", eventHandler.UpdateEvent)
				groups.DELETE("/:id/events/:eventId", eventHandler.DeleteEvent)
				groups.POST("/:id/events/:eventId/rsvp", eventHandler.RSVPEvent)
				groups.DELETE("/:id/events/:eventId/rsvp", eventHandler.RemoveRSVP)
				groups.POST("/:id/events/:eventId/approve", eventHandler.ApproveEvent)
				groups.POST("/:id/events/:eventId/reject", eventHandler.RejectEvent)
			}

			// Capsule system (E2EE groups + clusters)
			capsules := authorized.Group("/capsules")
			{
				capsules.GET("/mine", capsuleHandler.ListMyGroups)
				capsules.GET("/discover", capsuleHandler.DiscoverGroups)
				capsules.POST("", capsuleHandler.CreateCapsule)
				capsules.GET("/:id", capsuleHandler.GetCapsule)
				capsules.POST("/:id/rotate-keys", capsuleHandler.RotateKeys)

				// Group features (posts, chat, forum, members)
				capsules.GET("/:id/posts", groupHandler.ListGroupPosts)
				capsules.POST("/:id/posts", groupHandler.CreateGroupPost)
				capsules.POST("/:id/posts/:postId/like", groupHandler.ToggleGroupPostLike)
				capsules.GET("/:id/posts/:postId/comments", groupHandler.ListGroupPostComments)
				capsules.POST("/:id/posts/:postId/comments", groupHandler.CreateGroupPostComment)
				capsules.GET("/:id/messages", groupHandler.ListGroupMessages)
				capsules.POST("/:id/messages", groupHandler.SendGroupMessage)
				capsules.GET("/:id/threads", groupHandler.ListGroupThreads)
				capsules.POST("/:id/threads", groupHandler.CreateGroupThread)
				capsules.GET("/:id/threads/:threadId", groupHandler.GetGroupThread)
				capsules.POST("/:id/threads/:threadId/replies", groupHandler.CreateGroupThreadReply)
				capsules.GET("/:id/members", groupHandler.ListGroupMembers)
				capsules.DELETE("/:id/members/:memberId", groupHandler.RemoveGroupMember)
				capsules.PATCH("/:id/members/:memberId", groupHandler.UpdateMemberRole)
				capsules.POST("/:id/leave", groupHandler.LeaveGroup)
				capsules.PATCH("/:id", groupHandler.UpdateGroup)
				capsules.DELETE("/:id", groupHandler.DeleteGroup)
				capsules.POST("/:id/invite-member", groupHandler.InviteToGroup)
				capsules.GET("/:id/search-users", groupHandler.SearchUsersForInvite)

				// Reporting & moderation (group admins + members)
				capsules.POST("/:id/entries/:entryId/report", groupHandler.ReportCapsuleEntry)
				capsules.POST("/:id/messages/:messageId/report", groupHandler.ReportGroupMessage)
				capsules.POST("/:id/posts/:postId/report", groupHandler.ReportGroupPost)
				capsules.GET("/:id/reports", groupHandler.GetGroupReports)
				capsules.PATCH("/:id/reports/:reportId", groupHandler.UpdateGroupReport)
				capsules.DELETE("/:id/messages/:messageId", groupHandler.DeleteGroupMessage)
			}

			// Capsule key management (per-user encrypted key store)
			capsuleKeys := authorized.Group("/capsule-keys")
			{
				capsuleKeys.GET("", capsuleEscrowHandler.GetMyKeys)
				capsuleKeys.POST("", capsuleEscrowHandler.StoreKey)
				capsuleKeys.GET("/:id", capsuleEscrowHandler.GetMyKeyForGroup)
				capsuleKeys.DELETE("/:id", capsuleEscrowHandler.DeleteKey)
			}

			// Capsule escrow backup (PIN-encrypted private key recovery)
			escrow := authorized.Group("/capsule/escrow")
			{
				escrow.GET("/status", capsuleEscrowHandler.GetBackupStatus)
				escrow.POST("/backup", capsuleEscrowHandler.UploadBackup)
				escrow.GET("/backup", capsuleEscrowHandler.GetBackup)
				escrow.DELETE("/backup", capsuleEscrowHandler.DeleteBackup)
			}

			// Repost & amplification system
			authorized.POST("/posts/repost", repostHandler.CreateRepost)
			authorized.POST("/posts/boost", repostHandler.BoostPost)
			authorized.GET("/posts/trending", repostHandler.GetTrendingPosts)
			authorized.GET("/posts/:id/reposts", repostHandler.GetRepostsForPost)
			authorized.GET("/posts/:id/amplification", repostHandler.GetAmplificationAnalytics)
			authorized.POST("/posts/:id/calculate-score", repostHandler.CalculateAmplificationScore)
			authorized.DELETE("/reposts/:id", repostHandler.DeleteRepost)
			authorized.POST("/reposts/:id/report", repostHandler.ReportRepost)
			authorized.GET("/amplification/rules", repostHandler.GetAmplificationRules)
			authorized.GET("/users/:id/reposts", repostHandler.GetUserReposts)
			authorized.GET("/users/:id/can-boost/:postId", repostHandler.CanBoostPost)
			authorized.GET("/users/:id/daily-boosts", repostHandler.GetDailyBoostCount)

			// Profile widget layout
			authorized.GET("/profile/layout", profileLayoutHandler.GetProfileLayout)
			authorized.PUT("/profile/layout", profileLayoutHandler.SaveProfileLayout)
			authorized.GET("/profiles/:id/layout", profileLayoutHandler.GetPublicProfileLayout)

			// Dashboard widget layout (customizable home page)
			authorized.GET("/dashboard/layout", dashboardLayoutHandler.GetDashboardLayout)
			authorized.PUT("/dashboard/layout", dashboardLayoutHandler.SaveDashboardLayout)
			authorized.GET("/users/:id/dashboard-layout", dashboardLayoutHandler.GetUserDashboardLayout)

			// Audio library (Freesound proxy — returns 503 until FREESOUND_API_KEY is set)
			authorized.GET("/audio/library", audioHandler.SearchAudioLibrary)
			authorized.GET("/audio/library/:trackId/listen", audioHandler.GetAudioTrackListen)

			// Events (public feed + user's groups)
			authorized.GET("/events/upcoming", eventHandler.GetUpcomingPublicEvents)
			authorized.GET("/events/mine", eventHandler.GetMyEvents)

		}
	}

	// Admin login (no auth middleware - this IS the auth step)
	r.POST("/api/v1/admin/login", middleware.RateLimit(0.1, 2), adminHandler.AdminLogin)
	r.POST("/api/v1/admin/logout", adminHandler.AdminLogout)

	// ──────────────────────────────────────────────
	// Admin Panel API (requires auth + admin role)
	// ──────────────────────────────────────────────
	admin := r.Group("/api/v1/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWTSecret, dbPool))
	admin.Use(middleware.AdminMiddleware(dbPool))
	{
		// ── Moderator-accessible routes ──────────────────────────
		// These routes are available to both admin and moderator roles.

		// Dashboard (read-only)
		admin.GET("/dashboard", adminHandler.GetDashboardStats)
		admin.GET("/growth", adminHandler.GetGrowthStats)

		// User lookup (read-only)
		admin.GET("/users", adminHandler.ListUsers)
		admin.GET("/users/:id", adminHandler.GetUser)

		// Warnings & strikes
		admin.POST("/users/:id/reset-strikes", adminHandler.ResetUserStrikes)
		admin.POST("/warn", adminHandler.WarnUser)

		// Post review
		admin.GET("/posts", adminHandler.ListPosts)
		admin.GET("/posts/:id", adminHandler.GetPost)
		admin.PATCH("/posts/:id/status", adminHandler.UpdatePostStatus)

		// Moderation Queue
		admin.GET("/moderation", adminHandler.GetModerationQueue)
		admin.PATCH("/moderation/:id/review", adminHandler.ReviewModerationFlag)
		admin.POST("/moderation/bulk", adminHandler.BulkReviewModeration)

		// Appeals
		admin.GET("/appeals", adminHandler.ListAppeals)
		admin.PATCH("/appeals/:id/review", adminHandler.ReviewAppeal)

		// Reports
		admin.GET("/reports", adminHandler.ListReports)
		admin.PATCH("/reports/:id", adminHandler.UpdateReportStatus)
		admin.POST("/reports/bulk", adminHandler.BulkUpdateReports)

		// Capsule (encrypted group) reports
		admin.GET("/capsule-reports", adminHandler.ListCapsuleReports)
		admin.PATCH("/capsule-reports/:id", adminHandler.UpdateCapsuleReportStatus)

		// Audit log (read-only)
		admin.GET("/audit-log", adminHandler.GetAuditLog)

		// ── Admin-only routes ────────────────────────────────────
		// These routes require full admin access (not moderators).
		adminOnly := admin.Group("")
		adminOnly.Use(middleware.AdminOnlyMiddleware())
		{
			// User mutations
			adminOnly.PATCH("/users/:id/status", adminHandler.UpdateUserStatus)
			adminOnly.PATCH("/users/:id/role", adminHandler.UpdateUserRole)
			adminOnly.PATCH("/users/:id/verification", adminHandler.UpdateUserVerification)
			adminOnly.PATCH("/users/:id/profile", adminHandler.AdminUpdateProfile)
			adminOnly.PATCH("/users/:id/email", adminHandler.AdminUpdateUserEmail)
			adminOnly.POST("/users/:id/follows", adminHandler.AdminManageFollow)
			adminOnly.GET("/users/:id/follows", adminHandler.AdminListFollows)
			adminOnly.DELETE("/users/:id", adminHandler.HardDeleteUser)
			adminOnly.POST("/users/bulk", adminHandler.BulkUpdateUsers)
			adminOnly.POST("/users/create", adminHandler.AdminCreateUser)
			adminOnly.DELETE("/users/:id/feed-impressions", adminHandler.AdminResetFeedImpressions)

			// Post mutations (beyond status changes)
			adminOnly.PATCH("/posts/:id", adminHandler.AdminUpdatePost)
			adminOnly.DELETE("/posts/:id", adminHandler.DeletePost)
			adminOnly.POST("/posts/bulk", adminHandler.BulkUpdatePosts)
			adminOnly.PATCH("/posts/:id/thumbnail", adminHandler.SetPostThumbnail)

			// Algorithm / Feed Config
			adminOnly.GET("/algorithm", adminHandler.GetAlgorithmConfig)
			adminOnly.PUT("/algorithm", adminHandler.UpdateAlgorithmConfig)
			adminOnly.GET("/feed-scores", adminHandler.AdminGetFeedScores)
			adminOnly.POST("/feed-scores/refresh", adminHandler.AdminRefreshFeedScores)
			adminOnly.POST("/video-moderation/backfill", adminHandler.AdminBackfillVideoModeration)

			// Categories
			adminOnly.GET("/categories", adminHandler.ListCategories)
			adminOnly.POST("/categories", adminHandler.CreateCategory)
			adminOnly.PATCH("/categories/:id", adminHandler.UpdateCategory)
			adminOnly.DELETE("/categories/:id", adminHandler.AdminDeleteCategory)

			// Neighborhoods
			adminOnly.GET("/neighborhoods", adminHandler.ListNeighborhoods)
			adminOnly.POST("/neighborhoods", adminHandler.AdminCreateNeighborhood)
			adminOnly.PATCH("/neighborhoods/:id", adminHandler.AdminUpdateNeighborhood)
			adminOnly.DELETE("/neighborhoods/:id", adminHandler.AdminDeleteNeighborhood)
			adminOnly.POST("/neighborhoods/:id/admins", adminHandler.SetNeighborhoodAdmin)
			adminOnly.GET("/neighborhoods/:id/admins", adminHandler.ListNeighborhoodAdmins)
			adminOnly.GET("/neighborhoods/:id/board", adminHandler.ListNeighborhoodBoardEntries)
			adminOnly.PATCH("/neighborhoods/:id/board/:entryId", adminHandler.UpdateNeighborhoodBoardEntry)

			// System
			adminOnly.GET("/health", adminHandler.GetSystemHealth)

			// R2 Storage
			adminOnly.GET("/storage/stats", adminHandler.GetStorageStats)
			adminOnly.GET("/storage/objects", adminHandler.ListStorageObjects)
			adminOnly.GET("/storage/object", adminHandler.GetStorageObject)
			adminOnly.DELETE("/storage/object", adminHandler.DeleteStorageObject)

			// Reserved Usernames
			adminOnly.GET("/usernames/reserved", adminHandler.ListReservedUsernames)
			adminOnly.POST("/usernames/reserved", adminHandler.AddReservedUsername)
			adminOnly.POST("/usernames/reserved/bulk", adminHandler.BulkAddReservedUsernames)
			adminOnly.DELETE("/usernames/reserved/:id", adminHandler.RemoveReservedUsername)

			// Username Claim Requests
			adminOnly.GET("/usernames/claims", adminHandler.ListClaimRequests)
			adminOnly.PATCH("/usernames/claims/:id", adminHandler.ReviewClaimRequest)

			// Ollama Model Management
			adminOnly.GET("/ai/ollama/status", adminHandler.OllamaModelStatus)
			adminOnly.POST("/ai/ollama/load/:name", adminHandler.OllamaLoadModel)
			adminOnly.POST("/ai/ollama/unload/:name", adminHandler.OllamaUnloadModel)
			adminOnly.DELETE("/ai/ollama/models/:name", adminHandler.OllamaDeleteModel)
			adminOnly.POST("/ai/ollama/pull", adminHandler.OllamaPullModel)

			// AI Moderation Config
			adminOnly.GET("/ai/models", adminHandler.ListModels)
			adminOnly.GET("/ai/models/local", adminHandler.ListLocalModels)
			adminOnly.GET("/ai/config", adminHandler.GetAIModerationConfigs)
			adminOnly.PUT("/ai/config", adminHandler.SetAIModerationConfig)
			adminOnly.POST("/ai/test", adminHandler.TestAIModeration)

			// AI Moderation Audit Log
			adminOnly.GET("/ai/moderation-log", adminHandler.GetAIModerationLog)
			adminOnly.POST("/ai/moderation-log/:id/feedback", adminHandler.SubmitAIModerationFeedback)
			adminOnly.GET("/ai/training-data", adminHandler.ExportAITrainingData)

			// Admin Content Creation & Import
			adminOnly.POST("/content/import", adminHandler.AdminImportContent)

			// Audit Log Retention
			adminOnly.DELETE("/audit-log/purge", adminHandler.PurgeAuditLog)

			// Social Media Import
			adminOnly.POST("/social/fetch", adminHandler.FetchSocialContent)
			adminOnly.POST("/social/download", adminHandler.DownloadSocialMedia)
			adminOnly.GET("/social/cookies", adminHandler.ListSocialCookies)
			adminOnly.POST("/social/cookies/:platform", adminHandler.UploadSocialCookies)
			adminOnly.DELETE("/social/cookies/:platform", adminHandler.DeleteSocialCookies)
			adminOnly.POST("/social/cookies/:platform/test", adminHandler.TestSocialCookies)

			// Official Accounts Management
			adminOnly.GET("/official-profiles", adminHandler.ListOfficialProfiles)
			adminOnly.GET("/official-accounts", adminHandler.ListOfficialAccounts)
			adminOnly.GET("/official-accounts/:id", adminHandler.GetOfficialAccount)
			adminOnly.POST("/official-accounts", adminHandler.UpsertOfficialAccount)
			adminOnly.DELETE("/official-accounts/:id", adminHandler.DeleteOfficialAccount)
			adminOnly.PATCH("/official-accounts/:id/toggle", adminHandler.ToggleOfficialAccount)
			adminOnly.POST("/official-accounts/:id/trigger", adminHandler.TriggerOfficialPost)
			adminOnly.POST("/official-accounts/:id/preview", adminHandler.PreviewOfficialPost)
			adminOnly.GET("/official-accounts/:id/articles", adminHandler.FetchNewsArticles)
			adminOnly.GET("/official-accounts/:id/posted", adminHandler.GetPostedArticles)
			adminOnly.POST("/official-accounts/:id/articles/cleanup", adminHandler.CleanupPendingArticles)
			adminOnly.POST("/official-accounts/articles/:article_id/skip", adminHandler.SkipArticle)
			adminOnly.POST("/official-accounts/articles/:article_id/post", adminHandler.PostSpecificArticle)
			adminOnly.DELETE("/official-accounts/articles/:article_id", adminHandler.DeleteArticle)

			// AI Engines Status
			adminOnly.GET("/ai-engines", adminHandler.GetAIEngines)
			adminOnly.POST("/upload-test-image", adminHandler.UploadTestImage)

			// Safe Domains Management
			adminOnly.GET("/safe-domains", adminHandler.ListSafeDomains)
			adminOnly.POST("/safe-domains", adminHandler.UpsertSafeDomain)
			adminOnly.DELETE("/safe-domains/:id", adminHandler.DeleteSafeDomain)
			adminOnly.GET("/safe-domains/check", adminHandler.CheckURLSafety)

			// Email Templates
			adminOnly.GET("/email-templates", adminHandler.ListEmailTemplates)
			adminOnly.GET("/email-templates/:id", adminHandler.GetEmailTemplate)
			adminOnly.PATCH("/email-templates/:id", adminHandler.UpdateEmailTemplate)
			adminOnly.POST("/email-templates/test", adminHandler.SendTestEmail)

			// Groups admin
			adminOnly.GET("/groups", adminHandler.AdminListGroups)
			adminOnly.GET("/groups/:id", adminHandler.AdminGetGroup)
			adminOnly.PATCH("/groups/:id", adminHandler.AdminUpdateGroup)
			adminOnly.DELETE("/groups/:id", adminHandler.AdminDeleteGroup)
			adminOnly.GET("/groups/:id/members", adminHandler.AdminListGroupMembers)
			adminOnly.DELETE("/groups/:id/members/:userId", adminHandler.AdminRemoveGroupMember)
			adminOnly.PATCH("/groups/:id/members/:userId", adminHandler.AdminUpdateMemberRole)

			// Quip repair
			adminOnly.GET("/quips/broken", adminHandler.GetBrokenQuips)
			adminOnly.POST("/quips/:id/repair", adminHandler.RepairQuip)

			// Events admin
			adminOnly.GET("/events", adminHandler.AdminListEvents)
			adminOnly.PATCH("/events/:id", adminHandler.AdminUpdateEvent)
			adminOnly.DELETE("/events/:id", adminHandler.AdminDeleteEvent)

			// Waitlist management
			adminOnly.GET("/waitlist", adminHandler.AdminListWaitlist)
			adminOnly.PATCH("/waitlist/:id", adminHandler.AdminUpdateWaitlist)
			adminOnly.DELETE("/waitlist/:id", adminHandler.AdminDeleteWaitlist)

			// Beacon Alerts Admin
			adminOnly.GET("/beacon-alerts", adminHandler.ListBeaconAlerts)
			adminOnly.GET("/beacon-alerts/stats", adminHandler.GetBeaconAlertStats)
			adminOnly.POST("/beacon-alerts/bulk", adminHandler.BulkUpdateBeaconAlerts)
			adminOnly.POST("/beacon-alerts/expire-source", adminHandler.ExpireBeaconsBySource)
			adminOnly.POST("/beacon-alerts/purge-source", adminHandler.PurgeBeaconsBySource)
			adminOnly.GET("/beacon-alerts/feeds", adminHandler.GetBeaconFeedStatus)
			adminOnly.PATCH("/beacon-alerts/feeds", adminHandler.ToggleBeaconFeed)
			adminOnly.POST("/beacon-alerts/feeds/sync", adminHandler.TriggerBeaconSync)
		}
	}

	// Public claim request endpoint (no auth)
	r.POST("/api/v1/username-claim", adminHandler.SubmitClaimRequest)

	// Account destroy confirmation (accessed via email link, no auth)
	r.GET("/api/v1/account/destroy/confirm", accountHandler.ConfirmImmediateDestroy)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: r,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("Failed to start server")
		}
	}()

	// Background job: update feed algorithm scores every 15 minutes
	go func() {
		// Run initial score refresh 30 seconds after startup
		time.Sleep(30 * time.Second)
		if err := feedAlgorithmService.RefreshAllScores(context.Background()); err != nil {
			log.Error().Err(err).Msg("[FeedAlgorithm] Initial score refresh failed")
		}
		ticker := time.NewTicker(15 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			if err := feedAlgorithmService.RefreshAllScores(context.Background()); err != nil {
				log.Error().Err(err).Msg("[FeedAlgorithm] Failed to refresh feed scores")
			}
		}
	}()

	// Background job: purge accounts past 14-day deletion window (runs every hour)
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			ids, err := userRepo.GetAccountsPendingPurge(context.Background())
			if err != nil {
				log.Error().Err(err).Msg("[Purge] Failed to fetch accounts pending purge")
				continue
			}
			for _, id := range ids {
				log.Warn().Str("user_id", id).Msg("[Purge] Auto-purging account past 14-day grace period")
				if err := userRepo.CascadePurgeUser(context.Background(), id); err != nil {
					log.Error().Err(err).Str("user_id", id).Msg("[Purge] FAILED to purge account")
				} else {
					log.Info().Str("user_id", id).Msg("[Purge] Account permanently destroyed")
				}
			}
		}
	}()

	// Background job: audit log retention — purge entries older than 90 days, runs daily at 3 AM UTC
	go func() {
		for {
			now := time.Now().UTC()
			next := time.Date(now.Year(), now.Month(), now.Day()+1, 3, 0, 0, 0, time.UTC)
			time.Sleep(time.Until(next))
			tag, err := dbPool.Exec(context.Background(), "DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '90 days'")
			if err != nil {
				log.Error().Err(err).Msg("[AuditRetention] Failed to purge old audit log entries")
			} else {
				log.Info().Int64("purged", tag.RowsAffected()).Msg("[AuditRetention] Daily cleanup complete")
			}
		}
	}()

	log.Info().Msgf("Server started on port %s", cfg.Port)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Info().Msg("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal().Err(err).Msg("Server forced to shutdown")
	}

	log.Info().Msg("Server exiting")
}

