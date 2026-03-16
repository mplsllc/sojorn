// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package reposts

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
)

// Ext implements extension.Extension for the Reposts feature.
type Ext struct {
	registry *extension.Registry
	handler  *handlers.RepostHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "reposts" }
func (e *Ext) Name() string        { return "Reposts" }
func (e *Ext) Description() string { return "Repost, boost, and amplification system with analytics and trending" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.handler = handlers.NewRepostHandler(deps.DB)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
	mw := extension.RequireEnabled(e.registry, e.ID())

	authorized.POST("/posts/repost", mw, e.handler.CreateRepost)
	authorized.POST("/posts/boost", mw, e.handler.BoostPost)
	authorized.GET("/posts/trending", mw, e.handler.GetTrendingPosts)
	authorized.GET("/posts/:id/reposts", mw, e.handler.GetRepostsForPost)
	authorized.GET("/posts/:id/amplification", mw, e.handler.GetAmplificationAnalytics)
	authorized.POST("/posts/:id/calculate-score", mw, e.handler.CalculateAmplificationScore)
	authorized.DELETE("/reposts/:id", mw, e.handler.DeleteRepost)
	authorized.POST("/reposts/:id/report", mw, e.handler.ReportRepost)
	authorized.GET("/amplification/rules", mw, e.handler.GetAmplificationRules)
	authorized.GET("/users/:id/reposts", mw, e.handler.GetUserReposts)
	authorized.GET("/users/:id/can-boost/:postId", mw, e.handler.CanBoostPost)
	authorized.GET("/users/:id/daily-boosts", mw, e.handler.GetDailyBoostCount)
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for reposts.
}
