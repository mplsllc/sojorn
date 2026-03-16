// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package neighborhoods

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
)

// Ext implements extension.Extension for the Neighborhoods feature.
type Ext struct {
	registry            *extension.Registry
	neighborhoodHandler *handlers.NeighborhoodHandler
	boardHandler        *handlers.BoardHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "neighborhoods" }
func (e *Ext) Name() string        { return "Neighborhoods" }
func (e *Ext) Description() string { return "Location-based neighborhood detection, community boards, and local moderation" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.neighborhoodHandler = handlers.NewNeighborhoodHandler(deps.DB)
	e.boardHandler = handlers.NewBoardHandler(
		deps.DB,
		deps.ContentFilter,
		deps.ModerationService,
		deps.ContentModerator,
		deps.NotificationService,
	)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	neighborhoods := authorized.Group("/neighborhoods")
	neighborhoods.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		neighborhoods.GET("/detect", e.neighborhoodHandler.Detect)
		neighborhoods.GET("/current", e.neighborhoodHandler.GetCurrent)
		neighborhoods.GET("/search", e.neighborhoodHandler.SearchByZip)
		neighborhoods.POST("/choose", e.neighborhoodHandler.Choose)
		neighborhoods.GET("/mine", e.neighborhoodHandler.GetMyNeighborhood)
		neighborhoods.GET("/:id/reports", e.neighborhoodHandler.GetNeighborhoodReports)
		neighborhoods.PATCH("/:id/reports/:reportId", e.neighborhoodHandler.UpdateNeighborhoodReport)
	}

	board := authorized.Group("/board")
	board.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		board.GET("/nearby", e.boardHandler.ListNearby)
		board.POST("", e.boardHandler.CreateEntry)
		board.GET("/:id", e.boardHandler.GetEntry)
		board.POST("/:id/replies", e.boardHandler.CreateReply)
		board.POST("/vote", e.boardHandler.ToggleVote)
		board.POST("/:id/remove", e.boardHandler.RemoveEntry)
		board.PATCH("/:id/tag", e.boardHandler.UpdateTag)
		board.POST("/:id/flag", e.boardHandler.FlagEntry)
	}
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for neighborhoods.
}
