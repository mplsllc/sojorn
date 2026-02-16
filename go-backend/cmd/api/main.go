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
	"github.com/patbritton/sojorn-backend/internal/config"
	"github.com/patbritton/sojorn-backend/internal/handlers"
	"github.com/patbritton/sojorn-backend/internal/middleware"
	"github.com/patbritton/sojorn-backend/internal/realtime"
	"github.com/patbritton/sojorn-backend/internal/repository"
	"github.com/patbritton/sojorn-backend/internal/services"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
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

	r.Use(cors.New(cors.Config{
		AllowOriginFunc: func(origin string) bool {
			log.Debug().Msgf("CORS origin: %s", origin)
			if allowAllOrigins {
				return true
			}
			if strings.HasPrefix(origin, "http://localhost") ||
				strings.HasPrefix(origin, "https://localhost") ||
				strings.HasPrefix(origin, "http://127.0.0.1") ||
				strings.HasPrefix(origin, "https://127.0.0.1") {
				return true
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

	assetService := services.NewAssetService(cfg.R2SigningSecret, cfg.R2PublicBaseURL, cfg.R2ImgDomain, cfg.R2VidDomain)
	feedService := services.NewFeedService(postRepo, assetService)

	pushService, err := services.NewPushService(userRepo, cfg.FirebaseCredentialsFile)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to initialize PushService")
	}

	notificationService := services.NewNotificationService(notifRepo, pushService, userRepo)

	emailService := services.NewEmailService(cfg, dbPool)
	sendPulseService := services.NewSendPulseService(cfg.SendPulseID, cfg.SendPulseSecret)

	// Load moderation configuration
	moderationConfig := config.NewModerationConfig()
	moderationService := services.NewModerationService(dbPool, moderationConfig.OpenAIKey, moderationConfig.GoogleKey, moderationConfig.GoogleCredsFile)

	// Initialize appeal service
	appealService := services.NewAppealService(dbPool)

	// Initialize OpenRouter service
	openRouterService := services.NewOpenRouterService(dbPool, cfg.OpenRouterAPIKey)

	// Initialize Azure OpenAI service
	var azureOpenAIService *services.AzureOpenAIService
	if cfg.AzureOpenAIAPIKey != "" && cfg.AzureOpenAIEndpoint != "" {
		azureOpenAIService = services.NewAzureOpenAIService(dbPool, cfg.AzureOpenAIAPIKey, cfg.AzureOpenAIEndpoint, cfg.AzureOpenAIAPIVersion)
		log.Info().Msg("Azure OpenAI service initialized")
	} else {
		log.Warn().Msg("Azure OpenAI credentials not provided, Azure OpenAI service disabled")
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

	userHandler := handlers.NewUserHandler(userRepo, postRepo, notificationService, assetService)
	postHandler := handlers.NewPostHandler(postRepo, userRepo, feedService, assetService, notificationService, moderationService, contentFilter, openRouterService, linkPreviewService, localAIService)
	chatHandler := handlers.NewChatHandler(chatRepo, notificationService, hub)
	authHandler := handlers.NewAuthHandler(userRepo, cfg, emailService, sendPulseService)
	categoryHandler := handlers.NewCategoryHandler(categoryRepo)
	keyHandler := handlers.NewKeyHandler(userRepo)
	backupHandler := handlers.NewBackupHandler(repository.NewBackupRepository(dbPool))
	settingsHandler := handlers.NewSettingsHandler(userRepo, notifRepo)
	analysisHandler := handlers.NewAnalysisHandler()
	appealHandler := handlers.NewAppealHandler(appealService)

	// Initialize official accounts service
	officialAccountsService := services.NewOfficialAccountsService(dbPool, openRouterService, localAIService, linkPreviewService, moderationConfig.OpenAIKey)
	officialAccountsService.StartScheduler()
	defer officialAccountsService.StopScheduler()

	moderationHandler := handlers.NewModerationHandler(moderationService, openRouterService, localAIService)

	adminHandler := handlers.NewAdminHandler(dbPool, moderationService, appealService, emailService, openRouterService, azureOpenAIService, officialAccountsService, linkPreviewService, localAIService, cfg.JWTSecret, cfg.TurnstileSecretKey, s3Client, cfg.R2MediaBucket, cfg.R2VideoBucket, cfg.R2ImgDomain, cfg.R2VidDomain)

	accountHandler := handlers.NewAccountHandler(userRepo, emailService, cfg)

	// Capsule system handlers (E2EE groups)
	capsuleHandler := handlers.NewCapsuleHandler(dbPool)
	capsuleEscrowHandler := handlers.NewCapsuleEscrowHandler(dbPool)

	// Group feature handler (posts, chat, forum, members)
	groupHandler := handlers.NewGroupHandler(dbPool)

	// Neighborhood board handler (standalone message board)
	boardHandler := handlers.NewBoardHandler(dbPool, contentFilter, moderationService)

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

	r.GET("/ws", wsHandler.ServeWS)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(200)
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

		auth := v1.Group("/auth")
		auth.Use(middleware.RateLimit(0.5, 3))
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/signup", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.RefreshSession)
			auth.POST("/resend-verification", authHandler.ResendVerificationEmail)
			auth.GET("/verify", authHandler.VerifyEmail)
			auth.POST("/forgot-password", authHandler.ForgotPassword)
			auth.POST("/reset-password", authHandler.ResetPassword)
		}

		authorized := v1.Group("")
		authorized.Use(middleware.AuthMiddleware(cfg.JWTSecret, dbPool))
		{
			authorized.GET("/profiles/:id", userHandler.GetProfile)
			authorized.GET("/profile", userHandler.GetProfile)
			authorized.PATCH("/profile", userHandler.UpdateProfile)
			authorized.POST("/complete-onboarding", authHandler.CompleteOnboarding)
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
				users.POST("/requests", userHandler.GetPendingFollowRequests)
				users.GET("/:id/posts", postHandler.GetProfilePosts)
				users.GET("/:id/saved", userHandler.GetSavedPosts)
				users.GET("/me/liked", userHandler.GetLikedPosts)
				users.POST("/:id/block", userHandler.BlockUser)
				users.DELETE("/:id/block", userHandler.UnblockUser)
				users.GET("/blocked", userHandler.GetBlockedUsers)
				users.POST("/report", userHandler.ReportUser)
				users.POST("/block_by_handle", userHandler.BlockUserByHandle)

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
			authorized.POST("/posts/:id/like", postHandler.LikePost)
			authorized.DELETE("/posts/:id/like", postHandler.UnlikePost)
			authorized.POST("/posts/:id/save", postHandler.SavePost)
			authorized.DELETE("/posts/:id/save", postHandler.UnsavePost)
			authorized.POST("/posts/:id/reactions/toggle", postHandler.ToggleReaction)
			authorized.POST("/posts/:id/comments", postHandler.CreateComment)
			authorized.GET("/feed", postHandler.GetFeed)
			authorized.POST("/beacons", postHandler.CreateBeacon)
			authorized.GET("/beacons/nearby", postHandler.GetNearbyBeacons)
			authorized.POST("/beacons/:id/vouch", postHandler.VouchBeacon)
			authorized.POST("/beacons/:id/report", postHandler.ReportBeacon)
			authorized.DELETE("/beacons/:id/vouch", postHandler.RemoveBeaconVote)
			authorized.GET("/categories", categoryHandler.GetCategories)
			authorized.POST("/categories/settings", categoryHandler.SetUserCategorySettings)
			authorized.GET("/categories/settings", categoryHandler.GetUserCategorySettings)
			authorized.POST("/analysis/tone", analysisHandler.CheckTone)
			authorized.POST("/moderate", moderationHandler.CheckContent)

			// Chat routes
			authorized.GET("/conversations", chatHandler.GetConversations)
			authorized.GET("/conversation", chatHandler.GetOrCreateConversation)
			authorized.POST("/messages", chatHandler.SendMessage)
			authorized.GET("/conversations/:id/messages", chatHandler.GetMessages)
			authorized.DELETE("/conversations/:id", chatHandler.DeleteConversation)
			authorized.DELETE("/messages/:id", chatHandler.DeleteMessage)
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

			// Search & Discover routes
			discoverHandler := handlers.NewDiscoverHandler(userRepo, postRepo, tagRepo, categoryRepo, assetService)
			authorized.GET("/search", discoverHandler.Search)
			authorized.GET("/discover", discoverHandler.GetDiscover)
			authorized.GET("/hashtags/trending", discoverHandler.GetTrendingHashtags)
			authorized.GET("/hashtags/following", discoverHandler.GetFollowedHashtags)
			authorized.GET("/hashtags/:name", discoverHandler.GetHashtagPage)
			authorized.POST("/hashtags/:name/follow", discoverHandler.FollowHashtag)
			authorized.DELETE("/hashtags/:name/follow", discoverHandler.UnfollowHashtag)

			// Notifications
			notificationHandler := handlers.NewNotificationHandler(notifRepo, notificationService)
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
			}

			// Capsule system (E2EE groups + clusters)
			capsules := authorized.Group("/capsules")
			{
				capsules.GET("/mine", capsuleHandler.ListMyGroups)
				capsules.GET("/public", capsuleHandler.ListPublicClusters)
				capsules.POST("", capsuleHandler.CreateCapsule)
				capsules.POST("/group", capsuleHandler.CreateGroup)
				capsules.GET("/:id", capsuleHandler.GetCapsule)
				capsules.POST("/:id/entries", capsuleHandler.PostCapsuleEntry)
				capsules.GET("/:id/entries", capsuleHandler.GetCapsuleEntries)
				capsules.POST("/:id/invite", capsuleHandler.InviteToCapsule)
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

		}
	}

	// Admin login (no auth middleware - this IS the auth step)
	r.POST("/api/v1/admin/login", adminHandler.AdminLogin)

	// ──────────────────────────────────────────────
	// Admin Panel API (requires auth + admin role)
	// ──────────────────────────────────────────────
	admin := r.Group("/api/v1/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWTSecret, dbPool))
	admin.Use(middleware.AdminMiddleware(dbPool))
	{
		// Dashboard
		admin.GET("/dashboard", adminHandler.GetDashboardStats)
		admin.GET("/growth", adminHandler.GetGrowthStats)

		// User Management
		admin.GET("/users", adminHandler.ListUsers)
		admin.GET("/users/:id", adminHandler.GetUser)
		admin.PATCH("/users/:id/status", adminHandler.UpdateUserStatus)
		admin.PATCH("/users/:id/role", adminHandler.UpdateUserRole)
		admin.PATCH("/users/:id/verification", adminHandler.UpdateUserVerification)
		admin.POST("/users/:id/reset-strikes", adminHandler.ResetUserStrikes)
		admin.PATCH("/users/:id/profile", adminHandler.AdminUpdateProfile)
		admin.POST("/users/:id/follows", adminHandler.AdminManageFollow)
		admin.GET("/users/:id/follows", adminHandler.AdminListFollows)

		// Post Management
		admin.GET("/posts", adminHandler.ListPosts)
		admin.GET("/posts/:id", adminHandler.GetPost)
		admin.PATCH("/posts/:id/status", adminHandler.UpdatePostStatus)
		admin.DELETE("/posts/:id", adminHandler.DeletePost)
		admin.POST("/posts/bulk", adminHandler.BulkUpdatePosts)

		// User Bulk
		admin.POST("/users/bulk", adminHandler.BulkUpdateUsers)

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

		// Algorithm / Feed Config
		admin.GET("/algorithm", adminHandler.GetAlgorithmConfig)
		admin.PUT("/algorithm", adminHandler.UpdateAlgorithmConfig)

		// Categories
		admin.GET("/categories", adminHandler.ListCategories)
		admin.POST("/categories", adminHandler.CreateCategory)
		admin.PATCH("/categories/:id", adminHandler.UpdateCategory)

		// Neighborhoods
		admin.GET("/neighborhoods", adminHandler.ListNeighborhoods)
		admin.POST("/neighborhoods/:id/admins", adminHandler.SetNeighborhoodAdmin)
		admin.GET("/neighborhoods/:id/admins", adminHandler.ListNeighborhoodAdmins)
		admin.GET("/neighborhoods/:id/board", adminHandler.ListNeighborhoodBoardEntries)
		admin.PATCH("/neighborhoods/:id/board/:entryId", adminHandler.UpdateNeighborhoodBoardEntry)

		// System
		admin.GET("/health", adminHandler.GetSystemHealth)
		admin.GET("/audit-log", adminHandler.GetAuditLog)

		// R2 Storage
		admin.GET("/storage/stats", adminHandler.GetStorageStats)
		admin.GET("/storage/objects", adminHandler.ListStorageObjects)
		admin.GET("/storage/object", adminHandler.GetStorageObject)
		admin.DELETE("/storage/object", adminHandler.DeleteStorageObject)

		// Reserved Usernames
		admin.GET("/usernames/reserved", adminHandler.ListReservedUsernames)
		admin.POST("/usernames/reserved", adminHandler.AddReservedUsername)
		admin.POST("/usernames/reserved/bulk", adminHandler.BulkAddReservedUsernames)
		admin.DELETE("/usernames/reserved/:id", adminHandler.RemoveReservedUsername)

		// Username Claim Requests
		admin.GET("/usernames/claims", adminHandler.ListClaimRequests)
		admin.PATCH("/usernames/claims/:id", adminHandler.ReviewClaimRequest)

		// AI Moderation Config
		admin.GET("/ai/models", adminHandler.ListOpenRouterModels)
		admin.GET("/ai/models/local", adminHandler.ListLocalModels)
		admin.GET("/ai/config", adminHandler.GetAIModerationConfigs)
		admin.PUT("/ai/config", adminHandler.SetAIModerationConfig)
		admin.POST("/ai/test", adminHandler.TestAIModeration)

		// AI Moderation Audit Log
		admin.GET("/ai/moderation-log", adminHandler.GetAIModerationLog)
		admin.POST("/ai/moderation-log/:id/feedback", adminHandler.SubmitAIModerationFeedback)
		admin.GET("/ai/training-data", adminHandler.ExportAITrainingData)

		// Admin Content Creation & Import
		admin.POST("/users/create", adminHandler.AdminCreateUser)
		admin.POST("/content/import", adminHandler.AdminImportContent)

		// Official Accounts Management
		admin.GET("/official-profiles", adminHandler.ListOfficialProfiles)
		admin.GET("/official-accounts", adminHandler.ListOfficialAccounts)
		admin.GET("/official-accounts/:id", adminHandler.GetOfficialAccount)
		admin.POST("/official-accounts", adminHandler.UpsertOfficialAccount)
		admin.DELETE("/official-accounts/:id", adminHandler.DeleteOfficialAccount)
		admin.PATCH("/official-accounts/:id/toggle", adminHandler.ToggleOfficialAccount)
		admin.POST("/official-accounts/:id/trigger", adminHandler.TriggerOfficialPost)
		admin.POST("/official-accounts/:id/preview", adminHandler.PreviewOfficialPost)
		admin.GET("/official-accounts/:id/articles", adminHandler.FetchNewsArticles)
		admin.GET("/official-accounts/:id/posted", adminHandler.GetPostedArticles)
		admin.POST("/official-accounts/:id/articles/cleanup", adminHandler.CleanupPendingArticles)
		admin.POST("/official-accounts/articles/:article_id/skip", adminHandler.SkipArticle)
		admin.POST("/official-accounts/articles/:article_id/post", adminHandler.PostSpecificArticle)
		admin.DELETE("/official-accounts/articles/:article_id", adminHandler.DeleteArticle)

		// AI Engines Status
		admin.GET("/ai-engines", adminHandler.GetAIEngines)

		// Safe Domains Management
		admin.GET("/safe-domains", adminHandler.ListSafeDomains)
		admin.POST("/safe-domains", adminHandler.UpsertSafeDomain)
		admin.DELETE("/safe-domains/:id", adminHandler.DeleteSafeDomain)
		admin.GET("/safe-domains/check", adminHandler.CheckURLSafety)

		// Email Templates
		admin.GET("/email-templates", adminHandler.ListEmailTemplates)
		admin.GET("/email-templates/:id", adminHandler.GetEmailTemplate)
		admin.PATCH("/email-templates/:id", adminHandler.UpdateEmailTemplate)
		admin.POST("/email-templates/test", adminHandler.SendTestEmail)
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
