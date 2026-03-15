// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"context"

	"github.com/rs/zerolog/log"
)

// ContentModerator provides unified text moderation for all content types.
// It reads the admin-configured engine list from ai_moderation_config and tries
// engines in priority order. The FIRST engine to respond wins — subsequent engines
// only run if the previous one is unavailable (error/circuit breaker).
// Priority: local_ai (free/fast) → sightengine (API).
type ContentModerator struct {
	localAI     *LocalAIService
	sightEngine *SightEngineService
	moderation  *ModerationService // for reading engine config from DB
}

// ContentModerationResult holds the result from moderation.
type ContentModerationResult struct {
	Action     string             // "clean", "nsfw", "flag"
	Reason     string             // human-readable reason if flagged/nsfw
	NSFWReason string             // short label for NSFW blur screen
	Engine     string             // which engine produced the decision
	Scores     *ThreePoisonsScore // scores (may be nil)
}

func NewContentModerator(localAI *LocalAIService, sightEngine *SightEngineService, moderation *ModerationService) *ContentModerator {
	return &ContentModerator{
		localAI:     localAI,
		sightEngine: sightEngine,
		moderation:  moderation,
	}
}

// ModerateText runs moderation on text content using the first available engine.
// contentType should match an ai_moderation_config type: "text", "beacon_text", etc.
// Falls back to "text" config if the specific type isn't configured.
//
// Engine priority (fallback on failure only, NOT a full cascade):
//  1. local_ai     — free, fast, on-server (llama-guard). If it returns a result, we're done.
//  2. sightengine  — SightEngine API (text ML mode). Only runs if local_ai is unavailable.
func (cm *ContentModerator) ModerateText(ctx context.Context, contentType string, text string) *ContentModerationResult {
	if text == "" {
		return &ContentModerationResult{Action: "clean"}
	}

	useLocalAI, useSightEngine := true, true
	cm.resolveEngines(ctx, contentType, &useLocalAI, &useSightEngine)

	// Try local AI first (free, fast, on-server)
	if useLocalAI && cm.localAI != nil {
		localResult, err := cm.localAI.ModerateText(ctx, text)
		if err != nil {
			log.Debug().Err(err).Str("type", contentType).Msg("Local AI unavailable, trying next engine")
		} else if localResult != nil {
			result := &ContentModerationResult{Engine: "local_ai"}
			if localResult.Allowed {
				result.Action = "clean"
			} else {
				result.Action = "flag"
				result.Reason = localResult.Reason
				log.Info().Str("type", contentType).Str("reason", localResult.Reason).Msg("Content flagged by local AI")
			}
			return result
		}
	}

	// Fallback: SightEngine API
	if useSightEngine && cm.sightEngine != nil {
		seResult, err := cm.sightEngine.ModerateText(ctx, text)
		if err != nil {
			log.Debug().Err(err).Str("type", contentType).Msg("SightEngine text moderation failed")
		} else if seResult != nil {
			if seResult.Action == "flag" {
				log.Info().Str("type", contentType).Str("reason", seResult.Reason).Msg("Content flagged by SightEngine")
			}
			return seResult
		}
	}

	// All engines unavailable — fail open (allow content through)
	log.Warn().Str("type", contentType).Msg("All moderation engines unavailable — content allowed through")
	return &ContentModerationResult{Action: "clean"}
}

// ModerateImage runs moderation on an image URL using SightEngine.
func (cm *ContentModerator) ModerateImage(ctx context.Context, contentType string, imageURL string) *ContentModerationResult {
	if imageURL == "" {
		return &ContentModerationResult{Action: "clean"}
	}

	_, useSightEngine := true, true
	cm.resolveEngines(ctx, contentType, &useSightEngine, &useSightEngine)

	if useSightEngine && cm.sightEngine != nil {
		// Load SightEngine config for this content type
		var seCfg *SightEngineConfig
		if cm.moderation != nil {
			if modCfg, err := cm.moderation.GetModerationConfig(ctx, contentType); err == nil && modCfg != nil {
				seCfg = modCfg.ParseSightEngineConfig()
			}
		}
		seResult, err := cm.sightEngine.ModerateImageWithConfig(ctx, imageURL, seCfg)
		if err != nil {
			log.Debug().Err(err).Str("type", contentType).Msg("SightEngine image moderation failed")
		} else if seResult != nil {
			if seResult.Action == "flag" {
				log.Info().Str("type", contentType).Str("reason", seResult.Reason).Msg("Image flagged by SightEngine")
			}
			return seResult
		}
	}

	log.Warn().Str("type", contentType).Msg("Image moderation unavailable — content allowed through")
	return &ContentModerationResult{Action: "clean"}
}

// resolveEngines reads the admin config to determine which engines are enabled.
func (cm *ContentModerator) resolveEngines(ctx context.Context, contentType string, useLocalAI, useSightEngine *bool) {
	if cm.moderation == nil {
		return
	}

	cfg, err := cm.moderation.GetModerationConfig(ctx, contentType)
	if err != nil || cfg == nil || !cfg.Enabled {
		cfg, err = cm.moderation.GetModerationConfig(ctx, "text")
	}
	if err != nil || cfg == nil || !cfg.Enabled {
		return // defaults: all engines enabled
	}

	if len(cfg.Engines) > 0 {
		*useLocalAI = cfg.HasEngine("local_ai")
		*useSightEngine = cfg.HasEngine("sightengine")
	}
}
