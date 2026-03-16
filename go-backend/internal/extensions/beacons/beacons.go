// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package beacons

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// Ext implements extension.Extension for the Beacons feature.
type Ext struct {
	registry             *extension.Registry
	beaconUnifiedHandler *handlers.BeaconUnifiedHandler
	beaconSearchHandler  *handlers.BeaconSearchHandler
	icedHandler          *handlers.IcedHandler
	ingestion            *services.BeaconIngestionService
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "beacons" }
func (e *Ext) Name() string        { return "Beacons" }
func (e *Ext) Description() string { return "Community safety beacons, official alerts, cameras, and crowd-verified incident reports" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	beaconAlertRepo := repository.NewBeaconAlertRepository(deps.DB)

	e.beaconUnifiedHandler = handlers.NewBeaconUnifiedHandler(beaconAlertRepo)
	e.beaconSearchHandler = handlers.NewBeaconSearchHandler(deps.DB)
	e.icedHandler = handlers.NewIcedHandler(deps.Config.IcedAPIBase)
	e.ingestion = services.NewBeaconIngestionService(
		beaconAlertRepo,
		"http://127.0.0.1:8787",
		deps.Config.IcedAPIBase,
		deps.S3Client,
		deps.Config.R2MediaBucket,
		deps.Config.R2ImgDomain,
	)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
	beacons := authorized.Group("")
	beacons.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		beacons.GET("/beacons/unified", e.beaconUnifiedHandler.GetUnifiedBeacons)
		beacons.GET("/beacons/cameras", e.beaconUnifiedHandler.GetAllCameras)
		beacons.GET("/beacons/iced", e.icedHandler.GetIcedAlerts)
		beacons.GET("/beacon/search", e.beaconSearchHandler.Search)
	}
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	e.ingestion.Start()
}
