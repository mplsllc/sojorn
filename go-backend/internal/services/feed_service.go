// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"

	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

type FeedService struct {
	postRepo     *repository.PostRepository
	assetService *AssetService
	feedAlgo     *FeedAlgorithmService
}

func NewFeedService(postRepo *repository.PostRepository, assetService *AssetService, feedAlgo *FeedAlgorithmService) *FeedService {
	return &FeedService{
		postRepo:     postRepo,
		assetService: assetService,
		feedAlgo:     feedAlgo,
	}
}

func (s *FeedService) GetFeed(ctx context.Context, userID string, categorySlug string, hasVideo bool, limit int, offset int, showNSFW bool) ([]models.Post, error) {
	posts, err := s.postRepo.GetFeed(ctx, userID, categorySlug, hasVideo, limit, offset, showNSFW)
	if err != nil {
		return nil, err
	}

	s.signPostURLs(posts)
	posts = s.injectAd(ctx, posts, userID)

	return posts, nil
}

// GetSojornFeed returns an algorithmically-ranked feed.
// Falls back to chronological if algorithmic returns fewer than limit results.
func (s *FeedService) GetSojornFeed(ctx context.Context, userID string, limit int, offset int, category string) ([]models.Post, error) {
	postIDs, err := s.feedAlgo.GetAlgorithmicFeed(ctx, userID, limit, offset, category)
	if err != nil {
		log.Warn().Err(err).Msg("[SojornFeed] Algorithmic feed failed, falling back to chronological")
		return s.GetFeed(ctx, userID, category, false, limit, offset, false)
	}

	// Cold-start: only fall back if algorithm returned nothing at all.
	// Partial results are fine — serve what the algorithm scored.
	if len(postIDs) == 0 {
		log.Debug().Msg("[SojornFeed] No scored posts — falling back to chronological")
		return s.GetFeed(ctx, userID, category, false, limit, offset, false)
	}
	log.Debug().Int("algo_count", len(postIDs)).Int("limit", limit).Msg("[SojornFeed] Serving algorithmic feed")

	posts, err := s.postRepo.GetPostsByIDs(ctx, postIDs, userID)
	if err != nil {
		log.Warn().Err(err).Msg("[SojornFeed] GetPostsByIDs failed, falling back to chronological")
		return s.GetFeed(ctx, userID, category, false, limit, offset, false)
	}

	s.signPostURLs(posts)
	posts = s.injectAd(ctx, posts, userID)

	return posts, nil
}

// signPostURLs signs image/video/thumbnail URLs for all posts in the slice.
func (s *FeedService) signPostURLs(posts []models.Post) {
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
}

// injectAd inserts a sponsored post at index 4 if available.
func (s *FeedService) injectAd(ctx context.Context, posts []models.Post, userID string) []models.Post {
	if len(posts) >= 4 {
		ad, err := s.postRepo.GetRandomSponsoredPost(ctx, userID)
		if err == nil && ad != nil {
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

			newPosts := make([]models.Post, 0, len(posts)+1)
			newPosts = append(newPosts, posts[:4]...)
			newPosts = append(newPosts, *ad)
			newPosts = append(newPosts, posts[4:]...)
			posts = newPosts
		}
	}
	return posts
}

// GetPostScore returns the score breakdown for a post (author-facing transparency).
func (s *FeedService) GetPostScore(ctx context.Context, postID string) (*PostScoreDetail, error) {
	return s.feedAlgo.GetPostScore(ctx, postID)
}
