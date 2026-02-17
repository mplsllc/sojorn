package handlers

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"github.com/rs/zerolog/log"
)

type SearchHandler struct {
	userRepo     *repository.UserRepository
	postRepo     *repository.PostRepository
	assetService *services.AssetService
}

func NewSearchHandler(userRepo *repository.UserRepository, postRepo *repository.PostRepository, assetService *services.AssetService) *SearchHandler {
	return &SearchHandler{
		userRepo:     userRepo,
		postRepo:     postRepo,
		assetService: assetService,
	}
}

type SearchResults struct {
	Users []models.Profile   `json:"users"`
	Tags  []models.TagResult `json:"tags"`
	Posts []models.Post      `json:"posts"`
}

func (h *SearchHandler) Search(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Query parameter 'q' is required"})
		return
	}

	ctx := c.Request.Context()

	// Perform searches in parallel
	var wg sync.WaitGroup
	var users []models.Profile
	var tags []models.TagResult
	var posts []models.Post
	var userErr, tagErr, postErr error

	start := time.Now()

	viewerID := ""
	if val, exists := c.Get("user_id"); exists {
		viewerID = val.(string)
	}

	wg.Add(3)

	go func() {
		defer wg.Done()
		users, userErr = h.userRepo.SearchUsers(ctx, query, viewerID, 5)
	}()

	go func() {
		defer wg.Done()
		tags, tagErr = h.postRepo.SearchTags(ctx, query, 5)
	}()

	go func() {
		defer wg.Done()
		posts, postErr = h.postRepo.SearchPosts(ctx, query, viewerID, 20)
	}()

	wg.Wait()

	if userErr != nil {
		log.Error().Err(userErr).Msg("Failed to search users")
	}
	if tagErr != nil {
		log.Error().Err(tagErr).Msg("Failed to search tags")
	}
	if postErr != nil {
		log.Error().Err(postErr).Msg("Failed to search posts")
	}

	// Sign URLs for results
	for i := range users {
		if users[i].AvatarURL != nil {
			signed := h.assetService.SignImageURL(*users[i].AvatarURL)
			users[i].AvatarURL = &signed
		}
	}
	for i := range posts {
		if posts[i].ImageURL != nil {
			signed := h.assetService.SignImageURL(*posts[i].ImageURL)
			posts[i].ImageURL = &signed
		}
		if posts[i].VideoURL != nil {
			signed := h.assetService.SignVideoURL(*posts[i].VideoURL)
			posts[i].VideoURL = &signed
		}
		if posts[i].Author != nil && posts[i].Author.AvatarURL != "" {
			posts[i].Author.AvatarURL = h.assetService.SignImageURL(posts[i].Author.AvatarURL)
		}
	}

	// Initialize empty slices if nil to return strict JSON arrays [] instead of null
	if users == nil {
		users = []models.Profile{}
	}
	if tags == nil {
		tags = []models.TagResult{}
	}
	if posts == nil {
		posts = []models.Post{}
	}

	results := SearchResults{
		Users: users,
		Tags:  tags,
		Posts: posts,
	}

	log.Info().Str("query", query).Dur("duration", time.Since(start)).Msg("Search completed")
	c.JSON(http.StatusOK, results)
}
