// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package audio

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
)

// Ext implements extension.Extension for the Audio/Soundbank feature.
type Ext struct {
	registry *extension.Registry
	handler  *handlers.SoundsHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "audio" }
func (e *Ext) Name() string        { return "Soundbank" }
func (e *Ext) Description() string { return "In-house audio library for sound overlays on posts and quips" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.handler = handlers.NewSoundsHandler(
		deps.DB,
		deps.Config.R2Endpoint,
		deps.Config.R2AccessKey,
		deps.Config.R2SecretKey,
		deps.Config.R2MediaBucket,
		deps.Config.R2ImgDomain,
	)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
	sounds := authorized.Group("/sounds")
	sounds.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		sounds.GET("", e.handler.List)
		sounds.POST("/register", e.handler.Register)
		sounds.POST("/:id/use", e.handler.RecordUse)
	}

	adminSounds := admin.Group("/sounds")
	adminSounds.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		adminSounds.GET("", e.handler.AdminList)
		adminSounds.POST("", e.handler.AdminCreate)
		adminSounds.PATCH("/:id", e.handler.AdminUpdate)
	}
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for audio/soundbank.
}
