// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package moderation

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// Ext implements extension.Extension for the Content Moderation feature.
type Ext struct {
	registry           *extension.Registry
	moderationHandler  *handlers.ModerationHandler
	analysisHandler    *handlers.AnalysisHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "moderation" }
func (e *Ext) Name() string        { return "Content Moderation" }
func (e *Ext) Description() string { return "AI-powered content moderation with local Ollama, SightEngine, and automated content filtering" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	sightEngineService := deps.SightEngineService
	if sightEngineService == nil {
		sightEngineService = services.NewSightEngineService(deps.Config.SightEngineUser, deps.Config.SightEngineSecret)
	}

	e.moderationHandler = handlers.NewModerationHandler(deps.ModerationService, sightEngineService, deps.LocalAIService)
	e.analysisHandler = handlers.NewAnalysisHandler()
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	mw := extension.RequireEnabled(e.registry, e.ID())
	authorized.POST("/moderate", mw, e.moderationHandler.CheckContent)
	authorized.POST("/analysis/tone", mw, e.analysisHandler.CheckTone)
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for content moderation.
}
