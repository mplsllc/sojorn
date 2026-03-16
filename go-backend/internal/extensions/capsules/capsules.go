// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package capsules

import (
	"context"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/handlers"
)

// Ext implements extension.Extension for the Capsules feature.
type Ext struct {
	registry             *extension.Registry
	capsuleHandler       *handlers.CapsuleHandler
	capsuleEscrowHandler *handlers.CapsuleEscrowHandler
	groupHandler         *handlers.GroupHandler
}

func New(registry *extension.Registry) *Ext {
	return &Ext{registry: registry}
}

func (e *Ext) ID() string          { return "capsules" }
func (e *Ext) Name() string        { return "Capsules" }
func (e *Ext) Description() string { return "End-to-end encrypted private groups with posts, chat, forum threads, and key escrow" }
func (e *Ext) Dependencies() []string { return nil }

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
	e.capsuleHandler = handlers.NewCapsuleHandler(deps.DB)
	e.capsuleEscrowHandler = handlers.NewCapsuleEscrowHandler(deps.DB)
	e.groupHandler = handlers.NewGroupHandler(deps.DB, deps.NotificationService)
	return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, _ *gin.RouterGroup) {
	capsules := authorized.Group("/capsules")
	capsules.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		capsules.GET("/mine", e.capsuleHandler.ListMyGroups)
		capsules.GET("/discover", e.capsuleHandler.DiscoverGroups)
		capsules.POST("", e.capsuleHandler.CreateCapsule)
		capsules.GET("/:id", e.capsuleHandler.GetCapsule)
		capsules.POST("/:id/rotate-keys", e.capsuleHandler.RotateKeys)
		capsules.GET("/:id/posts", e.groupHandler.ListGroupPosts)
		capsules.POST("/:id/posts", e.groupHandler.CreateGroupPost)
		capsules.POST("/:id/posts/:postId/like", e.groupHandler.ToggleGroupPostLike)
		capsules.GET("/:id/posts/:postId/comments", e.groupHandler.ListGroupPostComments)
		capsules.POST("/:id/posts/:postId/comments", e.groupHandler.CreateGroupPostComment)
		capsules.GET("/:id/messages", e.groupHandler.ListGroupMessages)
		capsules.POST("/:id/messages", e.groupHandler.SendGroupMessage)
		capsules.GET("/:id/threads", e.groupHandler.ListGroupThreads)
		capsules.POST("/:id/threads", e.groupHandler.CreateGroupThread)
		capsules.GET("/:id/threads/:threadId", e.groupHandler.GetGroupThread)
		capsules.POST("/:id/threads/:threadId/replies", e.groupHandler.CreateGroupThreadReply)
		capsules.GET("/:id/members", e.groupHandler.ListGroupMembers)
		capsules.DELETE("/:id/members/:memberId", e.groupHandler.RemoveGroupMember)
		capsules.PATCH("/:id/members/:memberId", e.groupHandler.UpdateMemberRole)
		capsules.POST("/:id/leave", e.groupHandler.LeaveGroup)
		capsules.PATCH("/:id", e.groupHandler.UpdateGroup)
		capsules.DELETE("/:id", e.groupHandler.DeleteGroup)
		capsules.POST("/:id/invite-member", e.groupHandler.InviteToGroup)
		capsules.GET("/:id/search-users", e.groupHandler.SearchUsersForInvite)
		// Reporting
		capsules.POST("/:id/entries/:entryId/report", e.groupHandler.ReportCapsuleEntry)
		capsules.POST("/:id/messages/:messageId/report", e.groupHandler.ReportGroupMessage)
		capsules.POST("/:id/posts/:postId/report", e.groupHandler.ReportGroupPost)
		capsules.GET("/:id/reports", e.groupHandler.GetGroupReports)
		capsules.PATCH("/:id/reports/:reportId", e.groupHandler.UpdateGroupReport)
		capsules.DELETE("/:id/messages/:messageId", e.groupHandler.DeleteGroupMessage)
	}

	capsuleKeys := authorized.Group("/capsule-keys")
	capsuleKeys.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		capsuleKeys.GET("", e.capsuleEscrowHandler.GetMyKeys)
		capsuleKeys.POST("", e.capsuleEscrowHandler.StoreKey)
		capsuleKeys.GET("/:id", e.capsuleEscrowHandler.GetMyKeyForGroup)
		capsuleKeys.DELETE("/:id", e.capsuleEscrowHandler.DeleteKey)
	}

	capsuleEscrow := authorized.Group("/capsule/escrow")
	capsuleEscrow.Use(extension.RequireEnabled(e.registry, e.ID()))
	{
		capsuleEscrow.GET("/status", e.capsuleEscrowHandler.GetBackupStatus)
		capsuleEscrow.POST("/backup", e.capsuleEscrowHandler.UploadBackup)
		capsuleEscrow.GET("/backup", e.capsuleEscrowHandler.GetBackup)
		capsuleEscrow.DELETE("/backup", e.capsuleEscrowHandler.DeleteBackup)
	}
}

func (e *Ext) BackgroundJobs(_ context.Context) {
	// No background jobs for capsules.
}
