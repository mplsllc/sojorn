// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package chat

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

// Ext implements extension.Extension for the Chat feature.
type Ext struct {
	registry *extension.Registry
	handler  *handlers.ChatHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "chat" }
func (e *Ext) Name() string        { return "Chat" }
func (e *Ext) Description() string { return "Direct messaging with conversations, reactions, and mutual-follow discovery" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	chatRepo := repository.NewChatRepository(deps.DB)
	e.handler = handlers.NewChatHandler(chatRepo, deps.NotificationService, deps.Hub)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	mw := extension.RequireEnabled(e.registry, e.ID())

	authorized.GET("/conversations", mw, e.handler.GetConversations)
	authorized.GET("/conversation", mw, e.handler.GetOrCreateConversation)
	authorized.POST("/messages", mw, e.handler.SendMessage)
	authorized.GET("/conversations/:id/messages", mw, e.handler.GetMessages)
	authorized.DELETE("/conversations/:id", mw, e.handler.DeleteConversation)
	authorized.DELETE("/messages/:id", mw, e.handler.DeleteMessage)
	authorized.POST("/messages/:id/reactions", mw, e.handler.AddReaction)
	authorized.DELETE("/messages/:id/reactions", mw, e.handler.RemoveReaction)
	authorized.GET("/mutual-follows", mw, e.handler.GetMutualFollows)
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for chat.
}
