// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
	"github.com/rs/zerolog/log"
)

type DiscoverHandler struct {
	userRepo     *repository.UserRepository
	postRepo     *repository.PostRepository
	tagRepo      *repository.TagRepository
	categoryRepo repository.CategoryRepository
	assetService *services.AssetService
}

func NewDiscoverHandler(
	userRepo *repository.UserRepository,
	postRepo *repository.PostRepository,
	tagRepo *repository.TagRepository,
	categoryRepo repository.CategoryRepository,
	assetService *services.AssetService,
) *DiscoverHandler {
	return &DiscoverHandler{
		userRepo:     userRepo,
		postRepo:     postRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
		assetService: assetService,
	}
}

// GetDiscover returns the discover page data
// GET /api/v1/discover
func (h *DiscoverHandler) GetDiscover(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	ctx := c.Request.Context()
	start := time.Now()

	var wg sync.WaitGroup
	var trending []models.Hashtag
	var popularPosts []models.Post

	wg.Add(2)

	// Get top 4 tags
	go func() {
		defer wg.Done()
		var err error
		trending, err = h.tagRepo.GetTrendingHashtags(ctx, 4)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to get trending hashtags")
		}
	}()

	// Get popular public posts
	go func() {
		defer wg.Done()
		var err error
		popularPosts, err = h.postRepo.GetPopularPublicPosts(ctx, userID, 20)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to get popular posts")
		}
	}()

	wg.Wait()

	// Sign URLs
	for i := range popularPosts {
		h.signPostURLs(&popularPosts[i])
	}

	// Ensure non-nil slices
	if trending == nil {
		trending = []models.Hashtag{}
	}
	if popularPosts == nil {
		popularPosts = []models.Post{}
	}

	response := gin.H{
		"top_tags":      trending,
		"popular_posts": popularPosts,
	}

	log.Debug().Dur("duration", time.Since(start)).Msg("Discover page generated")
	c.JSON(http.StatusOK, response)
}

// Search performs a combined search across users, hashtags, and posts
// GET /api/v1/search
func (h *DiscoverHandler) Search(c *gin.Context) {
	query := c.Query("q")
	searchType := c.Query("type") // "all", "users", "hashtags", "posts"

	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Query parameter 'q' is required"})
		return
	}

	if searchType == "" {
		searchType = "all"
	}

	ctx := c.Request.Context()
	start := time.Now()

	viewerID := ""
	if val, exists := c.Get("user_id"); exists {
		viewerID = val.(string)
	}

	var wg sync.WaitGroup
	var users []models.Profile
	var hashtags []models.Hashtag
	var posts []models.Post
	var tags []models.TagResult

	if searchType == "all" || searchType == "users" {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var err error
			users, err = h.userRepo.SearchUsers(ctx, query, viewerID, 10)
			if err != nil {
				log.Warn().Err(err).Msg("Failed to search users")
				users = []models.Profile{}
			}
		}()
	}

	if searchType == "all" || searchType == "hashtags" {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var err error
			hashtags, err = h.tagRepo.SearchHashtags(ctx, query, 10)
			if err != nil {
				log.Warn().Err(err).Msg("Failed to search hashtags")
				hashtags = []models.Hashtag{}
			}
			// Also get legacy tag results for backward compatibility
			tags, _ = h.postRepo.SearchTags(ctx, query, 5)
		}()
	}

	if searchType == "all" || searchType == "posts" {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var err error
			posts, err = h.postRepo.SearchPosts(ctx, query, viewerID, 20)
			if err != nil {
				log.Warn().Err(err).Msg("Failed to search posts")
				posts = []models.Post{}
			}
		}()
	}

	wg.Wait()

	// Sign URLs
	for i := range users {
		if users[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*users[i].AvatarURL)
			users[i].AvatarURL = &signed
		}
	}
	for i := range posts {
		h.signPostURLs(&posts[i])
	}

	// Ensure non-nil slices
	if users == nil {
		users = []models.Profile{}
	}
	if hashtags == nil {
		hashtags = []models.Hashtag{}
	}
	if tags == nil {
		tags = []models.TagResult{}
	}
	if posts == nil {
		posts = []models.Post{}
	}

	response := gin.H{
		"users":    users,
		"hashtags": hashtags,
		"tags":     tags, // Legacy format
		"posts":    posts,
		"query":    query,
	}

	log.Info().Str("query", query).Str("type", searchType).Dur("duration", time.Since(start)).Msg("Search completed")
	c.JSON(http.StatusOK, response)
}

// GetHashtagPage returns posts for a specific hashtag
// GET /api/v1/hashtags/:name
func (h *DiscoverHandler) GetHashtagPage(c *gin.Context) {
	hashtagName := c.Param("name")
	if hashtagName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Hashtag name required"})
		return
	}

	ctx := c.Request.Context()
	limit := utils.GetQueryInt(c, "limit", 20)
	offset := utils.GetQueryInt(c, "offset", 0)

	viewerID := ""
	if val, exists := c.Get("user_id"); exists {
		viewerID = val.(string)
	}

	// Get hashtag info
	hashtag, err := h.tagRepo.GetHashtagByName(ctx, hashtagName)
	if err != nil || hashtag == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Hashtag not found"})
		return
	}

	// Check if user follows this hashtag
	isFollowing := false
	if viewerID != "" {
		userUUID, err := uuid.Parse(viewerID)
		if err == nil {
			isFollowing, _ = h.tagRepo.IsFollowingHashtag(ctx, userUUID, hashtag.ID)
		}
	}

	// Get posts
	posts, err := h.tagRepo.GetPostsByHashtag(ctx, hashtagName, viewerID, limit, offset)
	if err != nil {
		log.Error().Err(err).Str("hashtag", hashtagName).Msg("Failed to get posts by hashtag")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
		return
	}

	// Sign URLs
	for i := range posts {
		h.signPostURLs(&posts[i])
	}

	if posts == nil {
		posts = []models.Post{}
	}

	response := models.HashtagPageResponse{
		Hashtag:     *hashtag,
		Posts:       posts,
		IsFollowing: isFollowing,
		TotalPosts:  hashtag.UseCount,
	}

	c.JSON(http.StatusOK, response)
}

// FollowHashtag follows a hashtag
// POST /api/v1/hashtags/:name/follow
func (h *DiscoverHandler) FollowHashtag(c *gin.Context) {
	hashtagName := c.Param("name")
	userIDStr, _ := c.Get("user_id")
	userUUID, _ := uuid.Parse(userIDStr.(string))

	ctx := c.Request.Context()

	// Get or create the hashtag
	hashtag, err := h.tagRepo.GetOrCreateHashtag(ctx, hashtagName)
	if err != nil || hashtag == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to process hashtag"})
		return
	}

	if err := h.tagRepo.FollowHashtag(ctx, userUUID, hashtag.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to follow hashtag"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Now following #" + hashtag.Name})
}

// UnfollowHashtag unfollows a hashtag
// DELETE /api/v1/hashtags/:name/follow
func (h *DiscoverHandler) UnfollowHashtag(c *gin.Context) {
	hashtagName := c.Param("name")
	userIDStr, _ := c.Get("user_id")
	userUUID, _ := uuid.Parse(userIDStr.(string))

	ctx := c.Request.Context()

	hashtag, err := h.tagRepo.GetHashtagByName(ctx, hashtagName)
	if err != nil || hashtag == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Hashtag not found"})
		return
	}

	if err := h.tagRepo.UnfollowHashtag(ctx, userUUID, hashtag.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unfollow hashtag"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Unfollowed #" + hashtag.Name})
}

// GetTrendingHashtags returns trending hashtags
// GET /api/v1/hashtags/trending
func (h *DiscoverHandler) GetTrendingHashtags(c *gin.Context) {
	limit := utils.GetQueryInt(c, "limit", 20)

	hashtags, err := h.tagRepo.GetTrendingHashtags(c.Request.Context(), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch trending hashtags"})
		return
	}

	if hashtags == nil {
		hashtags = []models.Hashtag{}
	}

	c.JSON(http.StatusOK, gin.H{"hashtags": hashtags})
}

// GetFollowedHashtags returns hashtags the user follows
// GET /api/v1/hashtags/following
func (h *DiscoverHandler) GetFollowedHashtags(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userUUID, _ := uuid.Parse(userIDStr.(string))

	hashtags, err := h.tagRepo.GetFollowedHashtags(c.Request.Context(), userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch followed hashtags"})
		return
	}

	if hashtags == nil {
		hashtags = []models.Hashtag{}
	}

	c.JSON(http.StatusOK, gin.H{"hashtags": hashtags})
}

// signPostURLs signs all URLs in a post
func (h *DiscoverHandler) signPostURLs(post *models.Post) {
	if post.ImageURL != nil {
		signed := h.assetService.SignImageURL(*post.ImageURL)
		post.ImageURL = &signed
	}
	if post.VideoURL != nil {
		signed := h.assetService.SignVideoURL(*post.VideoURL)
		post.VideoURL = &signed
	}
	if post.Author != nil && post.Author.AvatarURL != "" {
		post.Author.AvatarURL = h.assetService.SignImageURL(post.Author.AvatarURL)
	}
}
