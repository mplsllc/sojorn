// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// ModerationHandler provides a stateless content moderation endpoint.
// It checks text and/or images for policy violations and returns pass/fail.
// NO content is stored — designed for pre-send checks (e.g. E2EE group messages).
type ModerationHandler struct {
	moderationService  *services.ModerationService
	sightEngineService *services.SightEngineService
	localAIService     *services.LocalAIService
}

func NewModerationHandler(moderationService *services.ModerationService, sightEngineService *services.SightEngineService, localAIService *services.LocalAIService) *ModerationHandler {
	return &ModerationHandler{
		moderationService:  moderationService,
		sightEngineService: sightEngineService,
		localAIService:     localAIService,
	}
}

// CheckContent is a stateless moderation endpoint.
// POST /moderate
// Request:  { "text": "...", "image_url": "..." }
// Response: { "allowed": true/false, "reason": "...", "action": "pass|nsfw|flag" }
// Nothing is logged or stored — pure pass/fail gate for privacy.
func (h *ModerationHandler) CheckContent(c *gin.Context) {
	var req struct {
		Text     string `json:"text"`
		ImageURL string `json:"image_url"`
		Context  string `json:"context"` // "group", "beacon", or empty for generic
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	if req.Text == "" && req.ImageURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "text or image_url required"})
		return
	}

	// Resolve which engines are enabled for this moderation context.
	useLocalAI, useSightEngine := true, true
	if h.moderationService != nil {
		configType := "text"
		if req.Text != "" && req.Context != "" {
			configType = req.Context + "_text"
		} else if req.ImageURL != "" && req.Context != "" {
			configType = req.Context + "_image"
		} else if req.ImageURL != "" {
			configType = "image"
		}
		cfg, err := h.moderationService.GetModerationConfig(c.Request.Context(), configType)
		if err != nil && req.Context != "" {
			fallbackType := "text"
			if req.ImageURL != "" && req.Text == "" {
				fallbackType = "image"
			}
			cfg, _ = h.moderationService.GetModerationConfig(c.Request.Context(), fallbackType)
		}
		if cfg != nil && len(cfg.Engines) > 0 {
			useLocalAI = cfg.HasEngine("local_ai")
			useSightEngine = cfg.HasEngine("sightengine")
		}
	}

	action := "pass"
	reason := ""
	engine := ""

	// Stage 0: Local AI moderation (llama-guard, on-server, free, fast)
	if useLocalAI && h.localAIService != nil && req.Text != "" {
		localResult, err := h.localAIService.ModerateText(c.Request.Context(), req.Text)
		if err != nil {
			log.Debug().Err(err).Msg("Local AI moderation unavailable, falling through")
		} else if localResult != nil && !localResult.Allowed {
			action = "flag"
			reason = localResult.Reason
			engine = "local_ai"
		}
	}

	// Stage 1: SightEngine moderation (text + image)
	if useSightEngine && h.sightEngineService != nil {
		if req.Text != "" && action != "flag" {
			textResult, err := h.sightEngineService.ModerateText(c.Request.Context(), req.Text)
			if err != nil {
				log.Debug().Err(err).Msg("SightEngine text moderation failed")
			} else if textResult != nil {
				if textResult.Action == "flag" {
					action = "flag"
					reason = textResult.Reason
					if engine == "" {
						engine = "sightengine"
					}
				} else if textResult.Action == "nsfw" && action != "flag" {
					action = "nsfw"
					reason = textResult.Reason
					if engine == "" {
						engine = "sightengine"
					}
				}
			}
		}
		if req.ImageURL != "" && action != "flag" {
			imgResult, err := h.sightEngineService.ModerateImage(c.Request.Context(), req.ImageURL)
			if err != nil {
				log.Debug().Err(err).Msg("SightEngine image moderation failed")
			} else if imgResult != nil {
				if imgResult.Action == "flag" {
					action = "flag"
					reason = imgResult.Reason
					if engine == "" {
						engine = "sightengine"
					}
				} else if imgResult.Action == "nsfw" && action != "flag" {
					action = "nsfw"
					reason = imgResult.NSFWReason
					if engine == "" {
						engine = "sightengine"
					}
				}
			}
		}
	}

	allowed := action != "flag"

	if action == "flag" {
		log.Info().Str("action", action).Str("reason", reason).Str("engine", engine).Msg("Stateless moderation: content blocked")
	}

	c.JSON(http.StatusOK, gin.H{
		"allowed": allowed,
		"action":  action,
		"reason":  reason,
		"engine":  engine,
	})
}
