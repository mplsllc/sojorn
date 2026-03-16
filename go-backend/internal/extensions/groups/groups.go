// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package groups

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
)

// Ext implements extension.Extension for the Groups feature.
type Ext struct {
	registry     *extension.Registry
	groupsHandler *handlers.GroupsHandler
	eventHandler  *handlers.EventHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "groups" }
func (e *Ext) Name() string        { return "Groups" }
func (e *Ext) Description() string { return "Public community groups with discovery, membership, feeds, and group events" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.groupsHandler = handlers.NewGroupsHandler(deps.DB)
	e.eventHandler = handlers.NewEventHandler(deps.DB)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
	groups := authorized.Group("/groups")
	groups.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		groups.GET("", e.groupsHandler.ListGroups)
		groups.GET("/mine", e.groupsHandler.GetMyGroups)
		groups.GET("/suggested", e.groupsHandler.GetSuggestedGroups)
		groups.POST("", e.groupsHandler.CreateGroup)
		groups.GET("/:id", e.groupsHandler.GetGroup)
		groups.POST("/:id/join", e.groupsHandler.JoinGroup)
		groups.POST("/:id/leave", e.groupsHandler.LeaveGroup)
		groups.GET("/:id/members", e.groupsHandler.GetGroupMembers)
		groups.GET("/:id/requests", e.groupsHandler.GetPendingRequests)
		groups.POST("/:id/requests/:requestId/approve", e.groupsHandler.ApproveJoinRequest)
		groups.POST("/:id/requests/:requestId/reject", e.groupsHandler.RejectJoinRequest)
		groups.GET("/:id/feed", e.groupsHandler.GetGroupFeed)
		groups.GET("/:id/key-status", e.groupsHandler.GetGroupKeyStatus)
		groups.POST("/:id/keys", e.groupsHandler.DistributeGroupKeys)
		groups.GET("/:id/members/public-keys", e.groupsHandler.GetGroupMemberPublicKeys)
		groups.POST("/:id/invite-member", e.groupsHandler.InviteMember)
		groups.DELETE("/:id/members/:userId", e.groupsHandler.RemoveMember)
		groups.PATCH("/:id/settings", e.groupsHandler.UpdateGroupSettings)

		// Group events
		groups.POST("/:id/events", e.eventHandler.CreateEvent)
		groups.GET("/:id/events", e.eventHandler.ListGroupEvents)
		groups.GET("/:id/events/:eventId", e.eventHandler.GetEvent)
		groups.PATCH("/:id/events/:eventId", e.eventHandler.UpdateEvent)
		groups.DELETE("/:id/events/:eventId", e.eventHandler.DeleteEvent)
		groups.POST("/:id/events/:eventId/rsvp", e.eventHandler.RSVPEvent)
		groups.DELETE("/:id/events/:eventId/rsvp", e.eventHandler.RemoveRSVP)
		groups.POST("/:id/events/:eventId/approve", e.eventHandler.ApproveEvent)
		groups.POST("/:id/events/:eventId/reject", e.eventHandler.RejectEvent)
	}
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for groups.
}
