package services

import (
	"context"

	"github.com/rs/zerolog/log"
)

// ContentModerator provides unified text moderation for all content types.
// It reads the admin-configured engine list from ai_moderation_config and tries
// engines in priority order. The FIRST engine to respond wins — subsequent engines
// only run if the previous one is unavailable (error/circuit breaker).
// Priority: local_ai (free/fast) → openai → openrouter.
type ContentModerator struct {
	localAI    *LocalAIService
	moderation *ModerationService
	openRouter *OpenRouterService
}

// ContentModerationResult holds the result from moderation.
type ContentModerationResult struct {
	Action     string             // "clean", "nsfw", "flag"
	Reason     string             // human-readable reason if flagged/nsfw
	NSFWReason string             // short label for NSFW blur screen
	Engine     string             // which engine produced the decision
	Scores     *ThreePoisonsScore // scores (may be nil)
}

func NewContentModerator(localAI *LocalAIService, moderation *ModerationService, openRouter *OpenRouterService) *ContentModerator {
	return &ContentModerator{
		localAI:    localAI,
		moderation: moderation,
		openRouter: openRouter,
	}
}

// ModerateText runs moderation on text content using the first available engine.
// contentType should match an ai_moderation_config type: "text", "beacon_text", etc.
// Falls back to "text" config if the specific type isn't configured.
//
// Engine priority (fallback on failure only, NOT a full cascade):
//  1. local_ai  — free, fast, on-server (llama-guard). If it returns a result, we're done.
//  2. openai    — OpenAI Moderation API. Only runs if local_ai is unavailable.
//  3. openrouter — configurable LLM. Only runs if both above are unavailable.
func (cm *ContentModerator) ModerateText(ctx context.Context, contentType string, text string) *ContentModerationResult {
	if text == "" {
		return &ContentModerationResult{Action: "clean"}
	}

	useLocalAI, useOpenAI, useOpenRouter := true, true, true
	cm.resolveEngines(ctx, contentType, &useLocalAI, &useOpenAI, &useOpenRouter)

	// Try local AI first (free, fast, on-server)
	if useLocalAI && cm.localAI != nil {
		localResult, err := cm.localAI.ModerateText(ctx, text)
		if err != nil {
			log.Debug().Err(err).Str("type", contentType).Msg("Local AI unavailable, trying next engine")
		} else if localResult != nil {
			// Local AI responded — use its decision, done.
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

	// Fallback: OpenAI Moderation API
	if useOpenAI && cm.moderation != nil {
		scores, reason, err := cm.moderation.AnalyzeContent(ctx, text, nil)
		if err != nil {
			log.Debug().Err(err).Str("type", contentType).Msg("OpenAI moderation failed, trying next engine")
		} else {
			result := &ContentModerationResult{Engine: "openai", Scores: scores}
			if reason != "" {
				result.Action = "flag"
				result.Reason = reason
				log.Info().Str("type", contentType).Str("reason", reason).Msg("Content flagged by OpenAI")
			} else {
				result.Action = "clean"
			}
			return result
		}
	}

	// Fallback: OpenRouter LLM
	if useOpenRouter && cm.openRouter != nil {
		var textResult *ModerationResult
		var textErr error

		textResult, textErr = cm.openRouter.ModerateWithType(ctx, contentType, text, nil)
		if textResult == nil || textErr != nil {
			textResult, textErr = cm.openRouter.ModerateText(ctx, text)
		}

		if textErr == nil && textResult != nil {
			result := &ContentModerationResult{
				Action: textResult.Action,
				Reason: textResult.Reason,
				Engine: "openrouter",
			}
			if textResult.Hate > 0 || textResult.Greed > 0 || textResult.Delusion > 0 {
				result.Scores = &ThreePoisonsScore{
					Hate:     textResult.Hate,
					Greed:    textResult.Greed,
					Delusion: textResult.Delusion,
				}
			}
			if textResult.Action == "nsfw" {
				result.NSFWReason = textResult.NSFWReason
			}
			if textResult.Action == "flag" {
				log.Info().Str("type", contentType).Str("reason", textResult.Reason).Msg("Content flagged by OpenRouter")
			}
			return result
		}
	}

	// All engines unavailable — fail open (allow content through)
	log.Warn().Str("type", contentType).Msg("All moderation engines unavailable — content allowed through")
	return &ContentModerationResult{Action: "clean"}
}

// resolveEngines reads the admin config to determine which engines are enabled.
func (cm *ContentModerator) resolveEngines(ctx context.Context, contentType string, useLocalAI, useOpenAI, useOpenRouter *bool) {
	if cm.openRouter == nil {
		return
	}

	cfg, err := cm.openRouter.GetModerationConfig(ctx, contentType)
	if err != nil || cfg == nil || !cfg.Enabled {
		cfg, err = cm.openRouter.GetModerationConfig(ctx, "text")
	}
	if err != nil || cfg == nil || !cfg.Enabled {
		return // defaults: all engines enabled
	}

	if len(cfg.Engines) > 0 {
		*useLocalAI = cfg.HasEngine("local_ai")
		*useOpenAI = cfg.HasEngine("openai")
		*useOpenRouter = cfg.HasEngine("openrouter")
	}
}
