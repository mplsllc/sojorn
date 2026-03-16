// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package extension

import (
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/realtime"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// Deps holds shared dependencies available to all extensions.
// This replaces passing 15+ constructor parameters to each handler.
type Deps struct {
	DB                  *pgxpool.Pool
	Config              *config.Config
	Hub                 *realtime.Hub
	S3Client            *s3.Client
	AssetService        *services.AssetService
	NotificationService *services.NotificationService
	ModerationService   *services.ModerationService
	ContentFilter       *services.ContentFilter
	ContentModerator    *services.ContentModerator
	FeedService         *services.FeedService
	PushService         *services.PushService
	EmailService        *services.EmailService
	LocalAIService      *services.LocalAIService
	LinkPreviewService  *services.LinkPreviewService
	SightEngineService  *services.SightEngineService
}
