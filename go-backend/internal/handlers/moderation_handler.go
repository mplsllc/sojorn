package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"github.com/rs/zerolog/log"
)

// ModerationHandler provides a stateless content moderation endpoint.
// It checks text and/or images for policy violations and returns pass/fail.
// NO content is stored — designed for pre-send checks (e.g. E2EE group messages).
type ModerationHandler struct {
	moderationService *services.ModerationService
	openRouterService *services.OpenRouterService
	localAIService    *services.LocalAIService
}

func NewModerationHandler(moderationService *services.ModerationService, openRouterService *services.OpenRouterService, localAIService *services.LocalAIService) *ModerationHandler {
	return &ModerationHandler{
		moderationService: moderationService,
		openRouterService: openRouterService,
		localAIService:    localAIService,
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
	// Try context-specific config first (e.g. group_text), fall back to generic (text).
	useLocalAI, useOpenAI, useOpenRouter := true, true, true // defaults: all engines
	if h.openRouterService != nil {
		configType := "text"
		if req.Text != "" && req.Context != "" {
			configType = req.Context + "_text"
		} else if req.ImageURL != "" && req.Context != "" {
			configType = req.Context + "_image"
		} else if req.ImageURL != "" {
			configType = "image"
		}
		cfg, err := h.openRouterService.GetModerationConfig(c.Request.Context(), configType)
		if err != nil && req.Context != "" {
			// Fall back to generic text/image config
			fallbackType := "text"
			if req.ImageURL != "" && req.Text == "" {
				fallbackType = "image"
			}
			cfg, _ = h.openRouterService.GetModerationConfig(c.Request.Context(), fallbackType)
		}
		if cfg != nil && len(cfg.Engines) > 0 {
			useLocalAI = cfg.HasEngine("local_ai")
			useOpenAI = cfg.HasEngine("openai")
			useOpenRouter = cfg.HasEngine("openrouter")
		}
	}

	action := "pass"
	reason := ""
	engine := "" // tracks which engine flagged

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

	// Stage 1: Three Poisons moderation (OpenAI + Google Vision)
	if useOpenAI && h.moderationService != nil {
		mediaURLs := []string{}
		if req.ImageURL != "" {
			mediaURLs = append(mediaURLs, req.ImageURL)
		}
		_, flagReason, err := h.moderationService.AnalyzeContent(c.Request.Context(), req.Text, mediaURLs)
		if err == nil && flagReason != "" {
			action = "flag"
			reason = flagReason
			if engine == "" {
				engine = "openai"
			}
		}
	}

	// Stage 2: OpenRouter moderation (text + image)
	if useOpenRouter && h.openRouterService != nil {
		if req.Text != "" {
			var textResult *services.ModerationResult
			var textErr error
			if req.Context != "" {
				textResult, textErr = h.openRouterService.ModerateWithType(c.Request.Context(), req.Context+"_text", req.Text, nil)
			}
			if textResult == nil || textErr != nil {
				textResult, textErr = h.openRouterService.ModerateText(c.Request.Context(), req.Text)
			}
			if textErr == nil && textResult != nil {
				if textResult.Action == "flag" {
					action = "flag"
					reason = textResult.Reason
					if engine == "" {
						engine = "openrouter"
					}
				} else if textResult.Action == "nsfw" && action != "flag" {
					action = "nsfw"
					reason = textResult.NSFWReason
					if engine == "" {
						engine = "openrouter"
					}
				}
			}
		}
		if req.ImageURL != "" && action != "flag" {
			var imgResult *services.ModerationResult
			var imgErr error
			if req.Context != "" {
				imgResult, imgErr = h.openRouterService.ModerateWithType(c.Request.Context(), req.Context+"_image", "", []string{req.ImageURL})
			}
			if imgResult == nil || imgErr != nil {
				imgResult, imgErr = h.openRouterService.ModerateImage(c.Request.Context(), req.ImageURL)
			}
			if imgErr == nil && imgResult != nil {
				if imgResult.Action == "flag" {
					action = "flag"
					reason = imgResult.Reason
					if engine == "" {
						engine = "openrouter"
					}
				} else if imgResult.Action == "nsfw" && action != "flag" {
					action = "nsfw"
					reason = imgResult.NSFWReason
					if engine == "" {
						engine = "openrouter"
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
