// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package discover

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

// Ext implements extension.Extension for the Discover feature.
type Ext struct {
	registry        *extension.Registry
	discoverHandler *handlers.DiscoverHandler
	followHandler   *handlers.FollowHandler
	tagRepo         *repository.TagRepository
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "discover" }
func (e *Ext) Name() string        { return "Discover" }
func (e *Ext) Description() string { return "Search, discovery feed, trending hashtags, and content exploration" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	userRepo := repository.NewUserRepository(deps.DB)
	postRepo := repository.NewPostRepository(deps.DB)
	tagRepo := repository.NewTagRepository(deps.DB)
	categoryRepo := repository.NewCategoryRepository(deps.DB)

	e.tagRepo = tagRepo
	e.discoverHandler = handlers.NewDiscoverHandler(userRepo, postRepo, tagRepo, categoryRepo, deps.AssetService)
	e.followHandler = handlers.NewFollowHandler(deps.DB)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	mw := extension.RequireEnabled(e.registry, e.ID())

	authorized.GET("/search", mw, e.discoverHandler.Search)
	authorized.GET("/discover", mw, e.discoverHandler.GetDiscover)
	authorized.GET("/hashtags/trending", mw, e.discoverHandler.GetTrendingHashtags)
	authorized.GET("/hashtags/following", mw, e.discoverHandler.GetFollowedHashtags)
	authorized.GET("/hashtags/:name", mw, e.discoverHandler.GetHashtagPage)
	authorized.POST("/hashtags/:name/follow", mw, e.discoverHandler.FollowHashtag)
	authorized.DELETE("/hashtags/:name/follow", mw, e.discoverHandler.UnfollowHashtag)
	authorized.GET("/users/:id/is-following", mw, e.followHandler.IsFollowing)
	authorized.GET("/users/:id/mutual-followers", mw, e.followHandler.GetMutualFollowers)
	authorized.GET("/users/suggested", mw, e.followHandler.GetSuggestedUsers)
}

func (e *Ext) BackgroundJobs(ctx context.Context) {
	go func() {
		if err := e.tagRepo.RefreshTrendingScores(ctx); err != nil {
			log.Warn().Err(err).Msg("Initial trending score refresh failed")
		}
		ticker := time.NewTicker(15 * time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := e.tagRepo.RefreshTrendingScores(ctx); err != nil {
					log.Warn().Err(err).Msg("Trending score refresh failed")
				}
			}
		}
	}()
}
