package services

import (
	"context"

	"github.com/patbritton/sojorn-backend/internal/models"
	"github.com/patbritton/sojorn-backend/internal/repository"
)

type FeedService struct {
	postRepo     *repository.PostRepository
	assetService *AssetService
}

func NewFeedService(postRepo *repository.PostRepository, assetService *AssetService) *FeedService {
	return &FeedService{
		postRepo:     postRepo,
		assetService: assetService,
	}
}

func (s *FeedService) GetFeed(ctx context.Context, userID string, categorySlug string, hasVideo bool, limit int, offset int, showNSFW bool) ([]models.Post, error) {
	posts, err := s.postRepo.GetFeed(ctx, userID, categorySlug, hasVideo, limit, offset, showNSFW)
	if err != nil {
		return nil, err
	}

	// Sign URLs for initial posts
	for i := range posts {
		if posts[i].ImageURL != nil {
			signed := s.assetService.SignImageURL(*posts[i].ImageURL)
			posts[i].ImageURL = &signed
		}
		if posts[i].VideoURL != nil {
			signed := s.assetService.SignVideoURL(*posts[i].VideoURL)
			posts[i].VideoURL = &signed
		}
		if posts[i].ThumbnailURL != nil {
			signed := s.assetService.SignImageURL(*posts[i].ThumbnailURL)
			posts[i].ThumbnailURL = &signed
		}
	}

	// Ads Injection at index 4 matching legacy Deno implementation
	if len(posts) >= 4 {
		ad, err := s.postRepo.GetRandomSponsoredPost(ctx, userID)
		if err == nil && ad != nil {
			// Sign Ad URL
			if ad.ImageURL != nil {
				signed := s.assetService.SignImageURL(*ad.ImageURL)
				ad.ImageURL = &signed
			}
			if ad.VideoURL != nil {
				signed := s.assetService.SignVideoURL(*ad.VideoURL)
				ad.VideoURL = &signed
			}
			if ad.ThumbnailURL != nil {
				signed := s.assetService.SignImageURL(*ad.ThumbnailURL)
				ad.ThumbnailURL = &signed
			}

			// Insert at index 4
			newPosts := make([]models.Post, 0, len(posts)+1)
			newPosts = append(newPosts, posts[:4]...)
			newPosts = append(newPosts, *ad)
			newPosts = append(newPosts, posts[4:]...)
			posts = newPosts
		}
	}

	return posts, nil
}
