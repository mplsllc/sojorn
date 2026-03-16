// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package events

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// Ext implements extension.Extension for public event discovery.
type Ext struct {
	registry     *extension.Registry
	eventHandler *handlers.EventHandler
	ingestion    *services.EventIngestionService
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "events" }
func (e *Ext) Name() string        { return "Events" }
func (e *Ext) Description() string { return "Public event discovery, RSVP, and automatic ingestion from Eventbrite and Ticketmaster" }
func (e *Ext) Dependencies() []string { return []string{"groups"} }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.eventHandler = handlers.NewEventHandler(deps.DB)

	if deps.Config.EventbriteAPIKey != "" || deps.Config.TicketmasterAPIKey != "" {
		e.ingestion = services.NewEventIngestionService(
			deps.DB,
			deps.Config.EventbriteAPIKey,
			deps.Config.TicketmasterAPIKey,
		)
	}
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	events := authorized.Group("/events")
	events.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		events.GET("/upcoming", e.eventHandler.GetUpcomingPublicEvents)
		events.GET("/mine", e.eventHandler.GetMyEvents)
	}
}

func (e *Ext) BackgroundJobs(ctx context.Context) {
	if e.ingestion != nil {
		go func() {
			log.Info().Msg("Event ingestion service started")

			time.Sleep(30 * time.Second)
			e.ingestion.SyncAll(ctx)

			ticker := time.NewTicker(2 * time.Hour)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					e.ingestion.SyncAll(ctx)
				}
			}
		}()
	}
}
