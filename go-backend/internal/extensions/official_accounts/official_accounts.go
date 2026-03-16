// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package official_accounts

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// Ext implements extension.Extension for the Official Accounts feature.
type Ext struct {
	registry *extension.Registry
	service  *services.OfficialAccountsService
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "official_accounts" }
func (e *Ext) Name() string        { return "Official Accounts" }
func (e *Ext) Description() string {
	return "Automated official accounts that post curated content from RSS feeds and news sources"
}
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.service = services.NewOfficialAccountsService(
		deps.DB,
		deps.LocalAIService,
		deps.LinkPreviewService,
		deps.Config.SearxngURL,
		deps.Config.OllamaURL,
	)
	return nil
}

func (e *Ext) RegisterRoutes(_ *gin.RouterGroup, _ *gin.RouterGroup) {
	// Admin-only routes are registered directly in main.go via adminHandler.
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	e.service.StartScheduler()
}
