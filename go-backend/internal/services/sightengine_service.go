// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// SightEngineService handles content moderation via the SightEngine API.
// Supports both text and image moderation with Three Poisons score mapping.
type SightEngineService struct {
	apiUser   string
	apiSecret string
	client    *http.Client
}

func NewSightEngineService(apiUser, apiSecret string) *SightEngineService {
	if apiUser == "" || apiSecret == "" {
		return nil
	}
	return &SightEngineService{
		apiUser:   apiUser,
		apiSecret: apiSecret,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// --- Text Moderation ---

type sightEngineTextResponse struct {
	Status           string `json:"status"`
	ModerationClasses struct {
		Sexual         float64 `json:"sexual"`
		Discriminatory float64 `json:"discriminatory"`
		Insulting      float64 `json:"insulting"`
		Violent        float64 `json:"violent"`
		Toxic          float64 `json:"toxic"`
	} `json:"moderation_classes"`
	Profanity struct {
		Matches []struct {
			Type      string `json:"type"`
			Intensity string `json:"intensity"`
			Match     string `json:"match"`
		} `json:"matches"`
	} `json:"profanity"`
	Link struct {
		Matches []struct {
			Type  string `json:"type"`
			Match string `json:"match"`
		} `json:"matches"`
	} `json:"link"`
}

// ModerateText sends text to SightEngine for moderation using ML mode.
func (s *SightEngineService) ModerateText(ctx context.Context, text string) (*ContentModerationResult, error) {
	if text == "" {
		return &ContentModerationResult{Action: "clean", Engine: "sightengine"}, nil
	}

	form := url.Values{}
	form.Set("text", text)
	form.Set("lang", "en")
	form.Set("mode", "ml")
	form.Set("api_user", s.apiUser)
	form.Set("api_secret", s.apiSecret)

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.sightengine.com/1.0/text/check.json", strings.NewReader(form.Encode()))
	if err != nil {
		return nil, fmt.Errorf("sightengine request error: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("sightengine unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("sightengine error %d: %s", resp.StatusCode, string(body))
	}

	var textResp sightEngineTextResponse
	if err := json.NewDecoder(resp.Body).Decode(&textResp); err != nil {
		return nil, fmt.Errorf("sightengine decode error: %w", err)
	}

	if textResp.Status != "success" {
		return nil, fmt.Errorf("sightengine returned status: %s", textResp.Status)
	}

	return s.mapTextResult(&textResp), nil
}

func (s *SightEngineService) mapTextResult(resp *sightEngineTextResponse) *ContentModerationResult {
	result := &ContentModerationResult{
		Action: "clean",
		Engine: "sightengine",
		Scores: &ThreePoisonsScore{},
	}

	mc := resp.ModerationClasses

	// Map to Three Poisons
	// hate ← violent + discriminatory + sexual + toxic
	result.Scores.Hate = mc.Violent
	if mc.Discriminatory > result.Scores.Hate {
		result.Scores.Hate = mc.Discriminatory
	}
	if mc.Sexual > result.Scores.Hate {
		result.Scores.Hate = mc.Sexual
	}

	// greed ← link spam
	if len(resp.Link.Matches) > 2 {
		result.Scores.Greed = 0.5
	}

	// delusion ← toxic + insulting (manipulative/abusive language)
	result.Scores.Delusion = mc.Toxic
	if mc.Insulting > result.Scores.Delusion {
		result.Scores.Delusion = mc.Insulting
	}

	// High-intensity profanity boosts hate
	for _, m := range resp.Profanity.Matches {
		if m.Type == "discriminatory" || m.Type == "sexual" {
			if m.Intensity == "high" && result.Scores.Hate < 0.7 {
				result.Scores.Hate = 0.7
			} else if m.Intensity == "medium" && result.Scores.Hate < 0.4 {
				result.Scores.Hate = 0.4
			}
		}
	}

	// Determine action from scores
	maxScore := result.Scores.Hate
	if result.Scores.Greed > maxScore {
		maxScore = result.Scores.Greed
	}
	if result.Scores.Delusion > maxScore {
		maxScore = result.Scores.Delusion
	}

	if maxScore > 0.7 {
		result.Action = "flag"
		result.Reason = s.buildTextReason(resp)
		log.Info().Str("reason", result.Reason).Float64("max_score", maxScore).Msg("SightEngine text: flagged")
	} else if maxScore > 0.4 {
		result.Action = "nsfw"
		result.Reason = s.buildTextReason(resp)
	}

	return result
}

func (s *SightEngineService) buildTextReason(resp *sightEngineTextResponse) string {
	mc := resp.ModerationClasses
	parts := []string{}
	if mc.Violent > 0.3 {
		parts = append(parts, fmt.Sprintf("violent=%.2f", mc.Violent))
	}
	if mc.Sexual > 0.3 {
		parts = append(parts, fmt.Sprintf("sexual=%.2f", mc.Sexual))
	}
	if mc.Discriminatory > 0.3 {
		parts = append(parts, fmt.Sprintf("discriminatory=%.2f", mc.Discriminatory))
	}
	if mc.Insulting > 0.3 {
		parts = append(parts, fmt.Sprintf("insulting=%.2f", mc.Insulting))
	}
	if mc.Toxic > 0.3 {
		parts = append(parts, fmt.Sprintf("toxic=%.2f", mc.Toxic))
	}
	if len(resp.Profanity.Matches) > 0 {
		parts = append(parts, fmt.Sprintf("profanity=%d matches", len(resp.Profanity.Matches)))
	}
	if len(parts) == 0 {
		return "content flagged by SightEngine"
	}
	return strings.Join(parts, ", ")
}

// --- Image Moderation ---

type sightEngineImageResponse struct {
	Status   string `json:"status"`
	Nudity   *struct {
		SexualActivity  float64 `json:"sexual_activity"`
		SexualDisplay   float64 `json:"sexual_display"`
		Erotica         float64 `json:"erotica"`
		VerySuggestive  float64 `json:"very_suggestive"`
		Suggestive      float64 `json:"suggestive"`
		None            float64 `json:"none"`
	} `json:"nudity"`
	Gore     *struct {
		Prob float64 `json:"prob"`
	} `json:"gore"`
	Violence *struct {
		Prob float64 `json:"prob"`
	} `json:"violence"`
	Weapon   *struct {
		Classes struct {
			Firearm float64 `json:"firearm"`
			Knife   float64 `json:"knife"`
		} `json:"classes"`
	} `json:"weapon"`
	RecreationalDrug *struct {
		Prob float64 `json:"prob"`
	} `json:"recreational_drug"`
	Medical *struct {
		Prob float64 `json:"prob"`
	} `json:"medical"`
	Offensive *struct {
		Prob float64 `json:"prob"`
	} `json:"offensive"`
	Tobacco *struct {
		Prob float64 `json:"prob"`
	} `json:"tobacco"`
	Alcohol *struct {
		Prob float64 `json:"prob"`
	} `json:"alcohol"`
	SelfHarm *struct {
		Prob float64 `json:"prob"`
	} `json:"self-harm"`
	Gambling *struct {
		Prob float64 `json:"prob"`
	} `json:"gambling"`
}

// ModerateImage sends an image URL to SightEngine for moderation.
func (s *SightEngineService) ModerateImage(ctx context.Context, imageURL string) (*ContentModerationResult, error) {
	if imageURL == "" {
		return &ContentModerationResult{Action: "clean", Engine: "sightengine"}, nil
	}

	endpoint := fmt.Sprintf(
		"https://api.sightengine.com/1.0/check.json?url=%s&models=nudity-2.1,gore-2.0,violence,weapon,recreational_drug,medical,offensive-2.0,alcohol,tobacco,self-harm,gambling&api_user=%s&api_secret=%s",
		url.QueryEscape(imageURL), s.apiUser, s.apiSecret,
	)

	req, err := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("sightengine request error: %w", err)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("sightengine unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("sightengine error %d: %s", resp.StatusCode, string(body))
	}

	var imgResp sightEngineImageResponse
	if err := json.NewDecoder(resp.Body).Decode(&imgResp); err != nil {
		return nil, fmt.Errorf("sightengine decode error: %w", err)
	}

	if imgResp.Status != "success" {
		return nil, fmt.Errorf("sightengine returned status: %s", imgResp.Status)
	}

	return s.mapImageResult(&imgResp), nil
}

func (s *SightEngineService) mapImageResult(resp *sightEngineImageResponse) *ContentModerationResult {
	result := &ContentModerationResult{
		Action: "clean",
		Engine: "sightengine",
		Scores: &ThreePoisonsScore{},
	}

	// hate ← nudity (sexual_activity, sexual_display) + gore + violence + weapon + offensive
	if resp.Nudity != nil {
		nudityMax := resp.Nudity.SexualActivity
		if resp.Nudity.SexualDisplay > nudityMax {
			nudityMax = resp.Nudity.SexualDisplay
		}
		if nudityMax > result.Scores.Hate {
			result.Scores.Hate = nudityMax
		}
		// Suggestive/erotica → lower hate (NSFW territory)
		suggestiveMax := resp.Nudity.Erotica
		if resp.Nudity.VerySuggestive > suggestiveMax {
			suggestiveMax = resp.Nudity.VerySuggestive
		}
		if suggestiveMax > 0.5 && result.Scores.Hate < suggestiveMax*0.6 {
			result.Scores.Hate = suggestiveMax * 0.6
		}
	}
	if resp.Gore != nil && resp.Gore.Prob > result.Scores.Hate {
		result.Scores.Hate = resp.Gore.Prob
	}
	if resp.Violence != nil && resp.Violence.Prob > result.Scores.Hate {
		result.Scores.Hate = resp.Violence.Prob
	}
	if resp.Weapon != nil {
		weaponMax := resp.Weapon.Classes.Firearm
		if resp.Weapon.Classes.Knife > weaponMax {
			weaponMax = resp.Weapon.Classes.Knife
		}
		if weaponMax > result.Scores.Hate {
			result.Scores.Hate = weaponMax
		}
	}
	if resp.Offensive != nil && resp.Offensive.Prob > result.Scores.Hate {
		result.Scores.Hate = resp.Offensive.Prob
	}

	// greed ← drugs + alcohol + gambling
	if resp.RecreationalDrug != nil && resp.RecreationalDrug.Prob > result.Scores.Greed {
		result.Scores.Greed = resp.RecreationalDrug.Prob
	}
	if resp.Medical != nil && resp.Medical.Prob > result.Scores.Greed {
		result.Scores.Greed = resp.Medical.Prob
	}
	if resp.Alcohol != nil && resp.Alcohol.Prob > result.Scores.Greed {
		result.Scores.Greed = resp.Alcohol.Prob
	}
	if resp.Gambling != nil && resp.Gambling.Prob > result.Scores.Greed {
		result.Scores.Greed = resp.Gambling.Prob
	}

	// delusion ← self-harm
	if resp.SelfHarm != nil && resp.SelfHarm.Prob > result.Scores.Delusion {
		result.Scores.Delusion = resp.SelfHarm.Prob
	}

	// Determine action
	maxScore := result.Scores.Hate
	if result.Scores.Greed > maxScore {
		maxScore = result.Scores.Greed
	}
	if result.Scores.Delusion > maxScore {
		maxScore = result.Scores.Delusion
	}

	// NSFW detection: suggestive nudity that isn't explicit
	isNSFW := false
	if resp.Nudity != nil {
		if resp.Nudity.Suggestive > 0.5 || resp.Nudity.VerySuggestive > 0.5 || resp.Nudity.Erotica > 0.5 {
			isNSFW = true
		}
	}

	if maxScore > 0.7 {
		result.Action = "flag"
		result.Reason = s.buildImageReason(resp)
		log.Info().Str("reason", result.Reason).Float64("max_score", maxScore).Msg("SightEngine image: flagged")
	} else if isNSFW || maxScore > 0.4 {
		result.Action = "nsfw"
		result.NSFWReason = s.buildNSFWLabel(resp)
		result.Reason = s.buildImageReason(resp)
	}

	return result
}

func (s *SightEngineService) buildImageReason(resp *sightEngineImageResponse) string {
	parts := []string{}
	if resp.Nudity != nil {
		max := resp.Nudity.SexualActivity
		if resp.Nudity.SexualDisplay > max {
			max = resp.Nudity.SexualDisplay
		}
		if max > 0.3 {
			parts = append(parts, fmt.Sprintf("nudity=%.2f", max))
		}
	}
	if resp.Gore != nil && resp.Gore.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("gore=%.2f", resp.Gore.Prob))
	}
	if resp.Violence != nil && resp.Violence.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("violence=%.2f", resp.Violence.Prob))
	}
	if resp.RecreationalDrug != nil && resp.RecreationalDrug.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("drugs=%.2f", resp.RecreationalDrug.Prob))
	}
	if resp.SelfHarm != nil && resp.SelfHarm.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("self-harm=%.2f", resp.SelfHarm.Prob))
	}
	if len(parts) == 0 {
		return "image flagged by SightEngine"
	}
	return strings.Join(parts, ", ")
}

func (s *SightEngineService) buildNSFWLabel(resp *sightEngineImageResponse) string {
	if resp.Nudity != nil && (resp.Nudity.Suggestive > 0.5 || resp.Nudity.VerySuggestive > 0.5 || resp.Nudity.Erotica > 0.5) {
		return "Suggestive Content"
	}
	if resp.Violence != nil && resp.Violence.Prob > 0.4 {
		return "Violence"
	}
	if resp.Gore != nil && resp.Gore.Prob > 0.4 {
		return "Gore"
	}
	return "Sensitive Content"
}

// Healthz performs a basic connectivity check by making a minimal API call.
func (s *SightEngineService) Healthz(ctx context.Context) (string, error) {
	if s == nil {
		return "not_configured", fmt.Errorf("SightEngine not configured")
	}

	// Use a simple text check as a health probe
	form := url.Values{}
	form.Set("text", "health check")
	form.Set("lang", "en")
	form.Set("mode", "ml")
	form.Set("api_user", s.apiUser)
	form.Set("api_secret", s.apiSecret)

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.sightengine.com/1.0/text/check.json", strings.NewReader(form.Encode()))
	if err != nil {
		return "error", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.client.Do(req)
	if err != nil {
		return "down", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "error", fmt.Errorf("status %d", resp.StatusCode)
	}

	return "ready", nil
}
