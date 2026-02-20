package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// OpenRouterService handles interactions with the OpenRouter API
type OpenRouterService struct {
	pool       *pgxpool.Pool
	httpClient *http.Client
	apiKey     string

	// Cached model list
	modelCache     []OpenRouterModel
	modelCacheMu   sync.RWMutex
	modelCacheTime time.Time
}

// OpenRouterModel represents a model available on OpenRouter
type OpenRouterModel struct {
	ID               string            `json:"id"`
	Name             string            `json:"name"`
	Description      string            `json:"description,omitempty"`
	Pricing          OpenRouterPricing `json:"pricing"`
	ContextLength    int               `json:"context_length"`
	Architecture     map[string]any    `json:"architecture,omitempty"`
	TopProvider      map[string]any    `json:"top_provider,omitempty"`
	PerRequestLimits map[string]any    `json:"per_request_limits,omitempty"`
}

type OpenRouterPricing struct {
	Prompt     string `json:"prompt"`
	Completion string `json:"completion"`
	Image      string `json:"image,omitempty"`
	Request    string `json:"request,omitempty"`
}

// ModerationConfigEntry represents a row in ai_moderation_config
type ModerationConfigEntry struct {
	ID             string    `json:"id"`
	ModerationType string    `json:"moderation_type"`
	ModelID        string    `json:"model_id"`
	ModelName      string    `json:"model_name"`
	SystemPrompt   string    `json:"system_prompt"`
	Enabled        bool      `json:"enabled"`
	Engines        []string  `json:"engines"`
	UpdatedAt      time.Time `json:"updated_at"`
	UpdatedBy      *string   `json:"updated_by,omitempty"`
}

// HasEngine returns true if the given engine is in the config's engines list.
func (c *ModerationConfigEntry) HasEngine(engine string) bool {
	for _, e := range c.Engines {
		if e == engine {
			return true
		}
	}
	return false
}

// OpenRouterChatMessage represents a message in a chat completion request
type OpenRouterChatMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

// OpenRouterChatRequest represents a chat completion request
type OpenRouterChatRequest struct {
	Model       string                  `json:"model"`
	Messages    []OpenRouterChatMessage `json:"messages"`
	Temperature *float64                `json:"temperature,omitempty"`
	MaxTokens   *int                    `json:"max_tokens,omitempty"`
}

func floatPtr(f float64) *float64 { return &f }
func intPtr(i int) *int           { return &i }

// downloadImage downloads an image from URL and returns base64 encoded data
func (s *OpenRouterService) downloadImage(ctx context.Context, url string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create image request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to download image: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("image download failed: %d", resp.StatusCode)
	}

	// Limit image size to 5MB
	const maxImageSize = 5 * 1024 * 1024
	limitedReader := io.LimitReader(resp.Body, maxImageSize)

	imageData, err := io.ReadAll(limitedReader)
	if err != nil {
		return "", fmt.Errorf("failed to read image data: %w", err)
	}

	// Detect content type
	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = http.DetectContentType(imageData)
	}

	// Only allow image formats
	if !strings.HasPrefix(contentType, "image/") {
		return "", fmt.Errorf("unsupported content type: %s", contentType)
	}

	// Convert to base64
	base64Data := base64.StdEncoding.EncodeToString(imageData)
	return fmt.Sprintf("data:%s;base64,%s", contentType, base64Data), nil
}

// OpenRouterChatResponse represents a chat completion response
type OpenRouterChatResponse struct {
	ID      string `json:"id"`
	Choices []struct {
		Message struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
}

func NewOpenRouterService(pool *pgxpool.Pool, apiKey string) *OpenRouterService {
	return &OpenRouterService{
		pool:   pool,
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
	}
}

// ListModels fetches available models from OpenRouter, with 1-hour cache
func (s *OpenRouterService) ListModels(ctx context.Context) ([]OpenRouterModel, error) {
	s.modelCacheMu.RLock()
	if len(s.modelCache) > 0 && time.Since(s.modelCacheTime) < time.Hour {
		cached := s.modelCache
		s.modelCacheMu.RUnlock()
		return cached, nil
	}
	s.modelCacheMu.RUnlock()

	req, err := http.NewRequestWithContext(ctx, "GET", "https://openrouter.ai/api/v1/models", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	if s.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.apiKey)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch models: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("OpenRouter API error %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		Data []OpenRouterModel `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode models: %w", err)
	}

	s.modelCacheMu.Lock()
	s.modelCache = result.Data
	s.modelCacheTime = time.Now()
	s.modelCacheMu.Unlock()

	return result.Data, nil
}

// GetModerationConfigs returns all moderation type configurations
func (s *OpenRouterService) GetModerationConfigs(ctx context.Context) ([]ModerationConfigEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, moderation_type, model_id, model_name, system_prompt, enabled, engines, updated_at, updated_by
		FROM ai_moderation_config
		ORDER BY moderation_type
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to query configs: %w", err)
	}
	defer rows.Close()

	var configs []ModerationConfigEntry
	for rows.Next() {
		var c ModerationConfigEntry
		if err := rows.Scan(&c.ID, &c.ModerationType, &c.ModelID, &c.ModelName, &c.SystemPrompt, &c.Enabled, &c.Engines, &c.UpdatedAt, &c.UpdatedBy); err != nil {
			return nil, err
		}
		configs = append(configs, c)
	}
	return configs, nil
}

// GetModerationConfig returns config for a specific moderation type
func (s *OpenRouterService) GetModerationConfig(ctx context.Context, moderationType string) (*ModerationConfigEntry, error) {
	var c ModerationConfigEntry
	err := s.pool.QueryRow(ctx, `
		SELECT id, moderation_type, model_id, model_name, system_prompt, enabled, engines, updated_at, updated_by
		FROM ai_moderation_config WHERE moderation_type = $1
	`, moderationType).Scan(&c.ID, &c.ModerationType, &c.ModelID, &c.ModelName, &c.SystemPrompt, &c.Enabled, &c.Engines, &c.UpdatedAt, &c.UpdatedBy)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// SetModerationConfig upserts a moderation config
func (s *OpenRouterService) SetModerationConfig(ctx context.Context, moderationType, modelID, modelName, systemPrompt string, enabled bool, engines []string, updatedBy string) error {
	if len(engines) == 0 {
		engines = []string{"local_ai", "openrouter", "openai"}
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO ai_moderation_config (moderation_type, model_id, model_name, system_prompt, enabled, engines, updated_by, updated_at)
		VALUES ($1, $2, $3, $4, $5, $7, $6, NOW())
		ON CONFLICT (moderation_type)
		DO UPDATE SET model_id = $2, model_name = $3, system_prompt = $4, enabled = $5, engines = $7, updated_by = $6, updated_at = NOW()
	`, moderationType, modelID, modelName, systemPrompt, enabled, updatedBy, engines)
	return err
}

// ModerateText sends text content to the configured model for moderation
func (s *OpenRouterService) ModerateText(ctx context.Context, content string) (*ModerationResult, error) {
	config, err := s.GetModerationConfig(ctx, "text")
	if err != nil || !config.Enabled || config.ModelID == "" {
		return nil, fmt.Errorf("text moderation not configured")
	}
	return s.callModel(ctx, config.ModelID, config.SystemPrompt, content, nil)
}

// ModerateImage sends an image URL to a vision model for moderation
func (s *OpenRouterService) ModerateImage(ctx context.Context, imageURL string) (*ModerationResult, error) {
	config, err := s.GetModerationConfig(ctx, "image")
	if err != nil || !config.Enabled || config.ModelID == "" {
		return nil, fmt.Errorf("image moderation not configured")
	}
	return s.callModel(ctx, config.ModelID, config.SystemPrompt, "", []string{imageURL})
}

// ModerateWithType sends content to a specific moderation type config (e.g. "group_text", "beacon_image").
// Returns nil if the config doesn't exist or isn't enabled — caller should fall back to generic.
func (s *OpenRouterService) ModerateWithType(ctx context.Context, moderationType string, textContent string, imageURLs []string) (*ModerationResult, error) {
	config, err := s.GetModerationConfig(ctx, moderationType)
	if err != nil || !config.Enabled || config.ModelID == "" {
		return nil, fmt.Errorf("%s moderation not configured", moderationType)
	}
	return s.callModel(ctx, config.ModelID, config.SystemPrompt, textContent, imageURLs)
}

// ModerateVideo sends video frame URLs to a vision model for moderation
func (s *OpenRouterService) ModerateVideo(ctx context.Context, frameURLs []string) (*ModerationResult, error) {
	config, err := s.GetModerationConfig(ctx, "video")
	if err != nil || !config.Enabled || config.ModelID == "" {
		return nil, fmt.Errorf("video moderation not configured")
	}
	return s.callModel(ctx, config.ModelID, config.SystemPrompt, "These are 3 frames extracted from a short video. Analyze all frames for policy violations.", frameURLs)
}

// ModerationResult is the parsed response from OpenRouter moderation
type ModerationResult struct {
	Flagged        bool    `json:"flagged"`
	Action         string  `json:"action"`      // "clean", "nsfw", "flag"
	NSFWReason     string  `json:"nsfw_reason"` // e.g. "violence", "nudity", "18+ content"
	Reason         string  `json:"reason"`
	Explanation    string  `json:"explanation"`
	Hate           float64 `json:"hate"`
	HateDetail     string  `json:"hate_detail"`
	Greed          float64 `json:"greed"`
	GreedDetail    string  `json:"greed_detail"`
	Delusion       float64 `json:"delusion"`
	DelusionDetail string  `json:"delusion_detail"`
	RawContent     string  `json:"raw_content"`
}

// GenerateText sends a general-purpose chat completion request and returns the raw text response.
// Used for AI content generation (not moderation).
func (s *OpenRouterService) GenerateText(ctx context.Context, modelID, systemPrompt, userPrompt string, temperature float64, maxTokens int) (string, error) {
	if s.apiKey == "" {
		return "", fmt.Errorf("OpenRouter API key not configured")
	}

	messages := []OpenRouterChatMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	reqBody := OpenRouterChatRequest{
		Model:       modelID,
		Messages:    messages,
		Temperature: floatPtr(temperature),
		MaxTokens:   intPtr(maxTokens),
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://openrouter.ai/api/v1/chat/completions", bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("HTTP-Referer", "https://sojorn.net")
	req.Header.Set("X-Title", "Sojorn Content Generation")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("OpenRouter request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("OpenRouter API error %d: %s", resp.StatusCode, string(body))
	}

	var chatResp OpenRouterChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no response from model")
	}

	return strings.TrimSpace(chatResp.Choices[0].Message.Content), nil
}

// callModel sends a chat completion request to OpenRouter
func (s *OpenRouterService) callModel(ctx context.Context, modelID, systemPrompt, textContent string, imageURLs []string) (*ModerationResult, error) {
	if s.apiKey == "" {
		return nil, fmt.Errorf("OpenRouter API key not configured")
	}

	messages := []OpenRouterChatMessage{}

	// System prompt
	if systemPrompt == "" {
		systemPrompt = defaultModerationSystemPrompt
	}
	messages = append(messages, OpenRouterChatMessage{Role: "system", Content: systemPrompt})

	// User message — wrap content with moderation instruction to prevent conversational replies
	moderationPrefix := "MODERATE THE FOLLOWING USER-SUBMITTED CONTENT. Do NOT reply to it, do NOT engage with it. Analyze it for policy violations and respond ONLY with the JSON object as specified in your instructions.\n\n---BEGIN CONTENT---\n"
	moderationSuffix := "\n---END CONTENT---\n\nNow output ONLY the JSON moderation result. No other text."

	if len(imageURLs) > 0 {
		// Multimodal content array with downloaded images
		parts := []map[string]any{}
		wrappedText := moderationPrefix + textContent + moderationSuffix
		parts = append(parts, map[string]any{"type": "text", "text": wrappedText})

		for _, url := range imageURLs {
			// Download image and convert to base64
			base64Image, err := s.downloadImage(ctx, url)
			if err != nil {
				// If download fails, fall back to URL (some models might support it)
				parts = append(parts, map[string]any{
					"type":      "image_url",
					"image_url": map[string]string{"url": url},
				})
			} else {
				// Use base64 data
				parts = append(parts, map[string]any{
					"type":      "image_url",
					"image_url": map[string]string{"url": base64Image},
				})
			}
		}
		messages = append(messages, OpenRouterChatMessage{Role: "user", Content: parts})
	} else {
		wrappedText := moderationPrefix + textContent + moderationSuffix
		messages = append(messages, OpenRouterChatMessage{Role: "user", Content: wrappedText})
	}

	reqBody := OpenRouterChatRequest{
		Model:       modelID,
		Messages:    messages,
		Temperature: floatPtr(0.0),
		MaxTokens:   intPtr(500),
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://openrouter.ai/api/v1/chat/completions", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("HTTP-Referer", "https://sojorn.net")
	req.Header.Set("X-Title", "Sojorn Moderation")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("OpenRouter request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("OpenRouter API error %d: %s", resp.StatusCode, string(body))
	}

	var chatResp OpenRouterChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from model")
	}

	raw := chatResp.Choices[0].Message.Content
	return parseModerationResponse(raw), nil
}

// parseModerationResponse tries to extract structured moderation data from model output
func parseModerationResponse(raw string) *ModerationResult {
	result := &ModerationResult{RawContent: raw}

	// Strategy: try multiple ways to extract JSON from the response
	candidates := []string{}

	// 1. Strip markdown code fences
	cleaned := raw
	if idx := strings.Index(cleaned, "```json"); idx >= 0 {
		cleaned = cleaned[idx+7:]
		if end := strings.Index(cleaned, "```"); end >= 0 {
			cleaned = cleaned[:end]
		}
		candidates = append(candidates, strings.TrimSpace(cleaned))
	} else if idx := strings.Index(cleaned, "```"); idx >= 0 {
		cleaned = cleaned[idx+3:]
		if end := strings.Index(cleaned, "```"); end >= 0 {
			cleaned = cleaned[:end]
		}
		candidates = append(candidates, strings.TrimSpace(cleaned))
	}

	// 2. Find first '{' and last '}' in raw text (greedy JSON extraction)
	if start := strings.Index(raw, "{"); start >= 0 {
		if end := strings.LastIndex(raw, "}"); end > start {
			candidates = append(candidates, raw[start:end+1])
		}
	}

	// 3. Try the raw text as-is
	candidates = append(candidates, strings.TrimSpace(raw))

	var parsed struct {
		Flagged        bool    `json:"flagged"`
		Action         string  `json:"action"`
		NSFWReason     string  `json:"nsfw_reason"`
		Reason         string  `json:"reason"`
		Explanation    string  `json:"explanation"`
		Hate           float64 `json:"hate"`
		HateDetail     string  `json:"hate_detail"`
		Greed          float64 `json:"greed"`
		GreedDetail    string  `json:"greed_detail"`
		Delusion       float64 `json:"delusion"`
		DelusionDetail string  `json:"delusion_detail"`
	}

	for _, candidate := range candidates {
		if err := json.Unmarshal([]byte(candidate), &parsed); err == nil {
			result.Reason = parsed.Reason
			result.Explanation = parsed.Explanation
			result.Hate = parsed.Hate
			result.HateDetail = parsed.HateDetail
			result.Greed = parsed.Greed
			result.GreedDetail = parsed.GreedDetail
			result.Delusion = parsed.Delusion
			result.DelusionDetail = parsed.DelusionDetail
			result.NSFWReason = parsed.NSFWReason

			// Use the action field if present, otherwise derive from scores
			action := strings.ToLower(strings.TrimSpace(parsed.Action))
			if action == "nsfw" || action == "flag" || action == "clean" {
				result.Action = action
			} else {
				// Fallback: derive from scores
				maxScore := max(parsed.Hate, max(parsed.Greed, parsed.Delusion))
				if maxScore > 0.5 {
					result.Action = "flag"
				} else if maxScore > 0.25 {
					result.Action = "nsfw"
				} else {
					result.Action = "clean"
				}
			}

			result.Flagged = result.Action == "flag"

			// Safety override: if any score > 0.7, always flag regardless of what model said
			if parsed.Hate > 0.7 || parsed.Greed > 0.7 || parsed.Delusion > 0.7 {
				result.Action = "flag"
				result.Flagged = true
				if result.Reason == "" {
					result.Reason = "Flagged: score exceeded 0.7 threshold"
				}
			}

			return result
		}
	}

	// All parsing failed — mark as error so admin can see the raw output
	result.Explanation = "Failed to parse model response as JSON. Check raw response below."
	return result
}

const defaultModerationSystemPrompt = `You are a content moderation AI for Sojorn, a social media platform.
Analyze the provided content and decide one of three actions:

1. "clean" — Content is appropriate for all users. No issues.
2. "nsfw" — Content is sensitive but ALLOWED on the platform. It will be blurred behind a warning label. Think "Instagram sensitivity screen" — suggestive or mature themes, but NO real nudity or graphic violence.
3. "flag" — Content is NOT ALLOWED and will be removed. The user will receive an appeal notice.

═══════════════════════════════════════════
IMAGE ANALYSIS INSTRUCTIONS — CRITICAL
═══════════════════════════════════════════
FOR EVERY IMAGE, you MUST perform these steps IN ORDER:

STEP 1: TEXT EXTRACTION (MANDATORY)
- Read and extract ALL visible text in the image (captions, memes, overlays, signs, infographics, screenshots)
- If the image contains ANY text, proceed to STEP 2
- If no text is visible, analyze visual content only

STEP 2: MISINFORMATION CHECK (HIGHEST PRIORITY)
Before checking anything else, analyze the text for:
- Medical/health claims (treatments, cures, vaccines, diseases, supplements, medications)
- Political claims (election fraud, voting manipulation, government conspiracies)
- Public safety misinformation (disasters, emergencies, false warnings)
- Scientific misinformation (climate denial, pseudoscience, false statistics)
- Disingenuous political content (misleading framing, out-of-context quotes, manipulated imagery, selective editing to misrepresent events or people)

STEP 3: MISINFORMATION BLOCKING RULE
If the image contains verifiably FALSE medical or political claims OR disingenuous political framing → ALWAYS FLAG
Examples that MUST be flagged:
- "Ivermectin cures COVID/cancer" → FLAG
- "Vaccines contain microchips/tracking devices" → FLAG
- "5G causes COVID/cancer/health problems" → FLAG
- "Election was stolen" with false evidence → FLAG
- "Doctors are hiding this cure" → FLAG
- "This natural remedy cures [serious disease]" without evidence → FLAG
- Out-of-context photos/quotes to misrepresent a politician or event → FLAG
- Selectively edited images that change the meaning of what happened → FLAG
- Misleading captions on real photos that imply false narratives → FLAG
- Images designed to deceive viewers about political events, policies, or statements → FLAG

STEP 4: Visual Content Analysis
After checking text for misinformation, analyze visual content for nudity, violence, etc.

═══════════════════════════════════════════
NUDITY & SEXUAL CONTENT RULES (Instagram Standard)
═══════════════════════════════════════════
CLEAN (no blur):
- Fully clothed people in any context
- Swimwear, athletic wear, crop tops in non-sexual contexts

NSFW (allowed, blurred):
- Suggestive or sensual poses, lingerie, implied nudity (covered but provocative)
- Revealing clothing clearly intended to be sexual or provocative
- Classical/fine art nudity (Renaissance paintings, Greek sculptures, museum pieces)
- Breastfeeding
- Medical or educational anatomy content
- Shirtless people in non-sexual contexts (beach, gym, sports)

NOT ALLOWED (flag):
- Real-person nudity: visible genitalia, bare female breasts in sexual context, fully nude photos
- Nude or semi-nude photography with sexual intent (boudoir, OnlyFans-style, erotic photography)
- Any sexual acts depicted (explicit or implied intercourse, oral sex)
- Pornography of any kind
- Any sexual content involving minors (ZERO TOLERANCE — always flag)
- Non-consensual sexual content, revenge porn, deepfake pornography
- Bestiality

The test: "Would Instagram allow this with a sensitivity screen?" If Instagram would remove it outright, FLAG it. If Instagram would show it with a warning, mark NSFW. Artistic paintings and sculptures of nude figures are NSFW, not flagged. Real-person nude photos are FLAGGED.

═══════════════════════════════════════════
VIOLENCE RULES (1-10 Scale)
═══════════════════════════════════════════
Rate the violence level on a 1-10 scale in your explanation:
  1-3: Mild (arguments, shoving, cartoon violence, sports contact) → "clean"
  4-5: Moderate (blood from injuries, protest footage, boxing/MMA, hunting, news photography) → "nsfw"
  6-7: Graphic (open wounds, significant bloodshed, war footage, graphic injury) → "flag"
  8-10: Extreme (torture, dismemberment, gore, execution) → "flag"

Only violence rated 5 or below is allowed. 6+ is always flagged and removed.
Protest/news footage showing blood or injuries = NSFW (4-5), NOT flagged.
Glorification of real-world violence = always "flag" regardless of graphic level.

═══════════════════════════════════════════
OTHER CONTENT RULES
═══════════════════════════════════════════
NSFW (allowed, blurred):
- Dark humor, edgy memes, intense themes
- Horror content, fictional violence in movies/games (≤5 on violence scale, no real gore)
- Drug/alcohol references, smoking imagery
- Heated political speech, strong profanity
- Depictions of self-harm recovery (educational/supportive context)

NOT ALLOWED (flag):
- Credible threats of violence against real people
- Doxxing (sharing private info to harass)
- Illegal activity instructions (bomb-making, drug synthesis)
- Extreme hate speech targeting protected groups
- Spam/scam content designed to defraud users
- Dangerous medical misinformation that could cause harm (unproven cures, anti-vaccine misinfo, fake cancer treatments, COVID conspiracy theories)
- Deepfakes designed to deceive or defame
- Images with text making false health/medical claims (e.g., "Ivermectin cures COVID/cancer", "5G causes disease", "Vaccines contain microchips")
- Memes or infographics spreading verifiably false information about elections, disasters, or public safety

When unsure between clean and nsfw, prefer "nsfw" (better safe, user sees it blurred).
When unsure between nsfw and flag, prefer "nsfw" — only flag content that clearly crosses the lines above.

Respond ONLY with a JSON object in this exact format:
{
  "action": "clean" or "nsfw" or "flag",
  "nsfw_reason": "If action is nsfw, a short label: e.g. 'Nudity', 'Violence', 'Suggestive Content', '18+ Themes', 'Gore', 'Drug References'. Empty string if clean or flag.",
  "flagged": true/false,
  "reason": "one-line summary if flagged or nsfw, empty string if clean",
  "explanation": "Detailed paragraph explaining your analysis. For images, ALWAYS start by stating what text you found (or 'No text visible'). If text is present, quote it and analyze for misinformation FIRST before discussing visual content. For violence, include your 1-10 rating. For nudity, explain what is shown.",
  "hate": 0.0-1.0,
  "hate_detail": "What you found or didn't find related to hate/violence/sexual content.",
  "greed": 0.0-1.0,
  "greed_detail": "What you found or didn't find related to spam/scams/manipulation.",
  "delusion": 0.0-1.0,
  "delusion_detail": "What you found or didn't find related to misinformation/self-harm. For images with text, analyze any medical/health claims, conspiracy theories, or false information."
}

Scoring guide (Three Poisons framework):
- hate: harassment, threats, violence, sexual content, nudity, hate speech, discrimination, graphic imagery
- greed: spam, scams, crypto schemes, misleading promotions, get-rich-quick, MLM recruitment
- delusion: misinformation, self-harm content, conspiracy theories, dangerous medical advice, deepfakes

Score 0.0 = no concern, 1.0 = extreme violation.
ALWAYS provide detailed explanations even when content is clean — explain what you checked and why it passed.
Only respond with the JSON, no other text.`
