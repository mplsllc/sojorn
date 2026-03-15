// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
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
		MildlySuggestive float64 `json:"mildly_suggestive"`
		None            float64 `json:"none"`
	} `json:"nudity"`
	Gore     *struct {
		Prob    float64 `json:"prob"`
		Classes *struct {
			VeryBloody       float64 `json:"very_bloody"`
			SlightlyBloody   float64 `json:"slightly_bloody"`
			BodyOrgan        float64 `json:"body_organ"`
			SeriousInjury    float64 `json:"serious_injury"`
			SuperficialInjury float64 `json:"superficial_injury"`
			Corpse           float64 `json:"corpse"`
			Skull            float64 `json:"skull"`
			Unconscious      float64 `json:"unconscious"`
			BodyWaste        float64 `json:"body_waste"`
		} `json:"classes"`
	} `json:"gore"`
	Violence *struct {
		Prob    float64 `json:"prob"`
		Classes *struct {
			PhysicalViolence float64 `json:"physical_violence"`
			FirearmThreat    float64 `json:"firearm_threat"`
			CombatSport      float64 `json:"combat_sport"`
		} `json:"classes"`
	} `json:"violence"`
	Weapon   *struct {
		Classes struct {
			Firearm        float64 `json:"firearm"`
			FirearmGesture float64 `json:"firearm_gesture"`
			FirearmToy     float64 `json:"firearm_toy"`
			Knife          float64 `json:"knife"`
		} `json:"classes"`
	} `json:"weapon"`
	RecreationalDrug *struct {
		Prob float64 `json:"prob"`
	} `json:"recreational_drug"`
	Medical *struct {
		Prob float64 `json:"prob"`
	} `json:"medical"`
	Offensive *struct {
		Nazi          float64 `json:"nazi"`
		Confederate   float64 `json:"confederate"`
		Supremacist   float64 `json:"supremacist"`
		Terrorist     float64 `json:"terrorist"`
		MiddleFinger  float64 `json:"middle_finger"`
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
	Money *struct {
		Prob float64 `json:"prob"`
	} `json:"money"`
	Destruction *struct {
		Prob float64 `json:"prob"`
	} `json:"destruction"`
	Military *struct {
		Prob float64 `json:"prob"`
	} `json:"military"`
	AIGenerated *struct {
		AIGenerated float64 `json:"ai_generated"`
	} `json:"type"`
	Text *struct {
		HasArtificial float64 `json:"has_artificial"`
		HasNatural    float64 `json:"has_natural"`
	} `json:"text"`
	QR *struct {
		Profanity []struct {
			Match string `json:"match"`
		} `json:"profanity"`
		Link []struct {
			Match    string `json:"match"`
			Category string `json:"category"`
		} `json:"link"`
	} `json:"qr"`
}

// modelParamMap maps config keys to SightEngine API model parameter strings.
var modelParamMap = map[string]string{
	"nudity":           "nudity-2.1",
	"gore":             "gore-2.0",
	"weapon":           "weapon",
	"violence":         "violence",
	"offensive":        "offensive-2.0",
	"recreational_drug": "recreational_drug",
	"medical":          "medical",
	"alcohol":          "alcohol",
	"tobacco":          "tobacco",
	"self-harm":        "self-harm",
	"gambling":         "gambling",
	"money":            "money",
	"destruction":      "destruction",
	"military":         "military",
	"genai":            "genai",
	"text-content":     "text-content",
	"qr-content":       "qr-content",
}

// buildModelString builds the comma-separated models param from config.
func (s *SightEngineService) buildModelString(cfg *SightEngineConfig) string {
	if cfg == nil || len(cfg.ImageModels) == 0 {
		// Default: all core models
		return "nudity-2.1,gore-2.0,violence,weapon,recreational_drug,medical,offensive-2.0,alcohol,tobacco,self-harm,gambling"
	}
	var models []string
	for key, mc := range cfg.ImageModels {
		if mc.Enabled {
			if param, ok := modelParamMap[key]; ok {
				models = append(models, param)
			}
		}
	}
	if len(models) == 0 {
		return "nudity-2.1"
	}
	return strings.Join(models, ",")
}

// ModerateImage sends an image URL to SightEngine for moderation.
func (s *SightEngineService) ModerateImage(ctx context.Context, imageURL string) (*ContentModerationResult, error) {
	return s.ModerateImageWithConfig(ctx, imageURL, nil)
}

// ModerateImageWithConfig sends an image URL to SightEngine using the given config.
func (s *SightEngineService) ModerateImageWithConfig(ctx context.Context, imageURL string, cfg *SightEngineConfig) (*ContentModerationResult, error) {
	if imageURL == "" {
		return &ContentModerationResult{Action: "clean", Engine: "sightengine"}, nil
	}

	modelString := s.buildModelString(cfg)
	endpoint := fmt.Sprintf(
		"https://api.sightengine.com/1.0/check.json?url=%s&models=%s&api_user=%s&api_secret=%s",
		url.QueryEscape(imageURL), modelString, s.apiUser, s.apiSecret,
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

	return s.mapImageResult(&imgResp, cfg), nil
}

func (s *SightEngineService) mapImageResult(resp *sightEngineImageResponse, cfg *SightEngineConfig) *ContentModerationResult {
	// Use config thresholds or defaults
	flagThreshold := 0.7
	nsfwThreshold := 0.4
	if cfg != nil {
		if cfg.FlagThreshold > 0 {
			flagThreshold = cfg.FlagThreshold
		}
		if cfg.NSFWThreshold > 0 {
			nsfwThreshold = cfg.NSFWThreshold
		}
	}
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
	if resp.Offensive != nil {
		offMax := resp.Offensive.Nazi
		for _, v := range []float64{resp.Offensive.Confederate, resp.Offensive.Supremacist, resp.Offensive.Terrorist, resp.Offensive.MiddleFinger} {
			if v > offMax {
				offMax = v
			}
		}
		if offMax > result.Scores.Hate {
			result.Scores.Hate = offMax
		}
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

	// delusion ← self-harm + destruction
	if resp.SelfHarm != nil && resp.SelfHarm.Prob > result.Scores.Delusion {
		result.Scores.Delusion = resp.SelfHarm.Prob
	}
	if resp.Destruction != nil && resp.Destruction.Prob > result.Scores.Delusion {
		result.Scores.Delusion = resp.Destruction.Prob
	}

	// Additional signals: money, military → greed/hate
	if resp.Money != nil && resp.Money.Prob > result.Scores.Greed {
		result.Scores.Greed = resp.Money.Prob
	}
	if resp.Military != nil && resp.Military.Prob > result.Scores.Hate {
		result.Scores.Hate = resp.Military.Prob
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
		if resp.Nudity.Suggestive > nsfwThreshold || resp.Nudity.VerySuggestive > nsfwThreshold || resp.Nudity.Erotica > nsfwThreshold {
			isNSFW = true
		}
	}

	if maxScore > flagThreshold {
		result.Action = "flag"
		result.Reason = s.buildImageReason(resp)
		log.Info().Str("reason", result.Reason).Float64("max_score", maxScore).Msg("SightEngine image: flagged")
	} else if isNSFW || maxScore > nsfwThreshold {
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
	if resp.Weapon != nil {
		wMax := resp.Weapon.Classes.Firearm
		if resp.Weapon.Classes.Knife > wMax {
			wMax = resp.Weapon.Classes.Knife
		}
		if wMax > 0.3 {
			parts = append(parts, fmt.Sprintf("weapon=%.2f", wMax))
		}
	}
	if resp.Offensive != nil {
		oMax := resp.Offensive.Nazi
		for _, v := range []float64{resp.Offensive.Confederate, resp.Offensive.Supremacist, resp.Offensive.Terrorist, resp.Offensive.MiddleFinger} {
			if v > oMax {
				oMax = v
			}
		}
		if oMax > 0.3 {
			parts = append(parts, fmt.Sprintf("offensive=%.2f", oMax))
		}
	}
	if resp.RecreationalDrug != nil && resp.RecreationalDrug.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("drugs=%.2f", resp.RecreationalDrug.Prob))
	}
	if resp.Alcohol != nil && resp.Alcohol.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("alcohol=%.2f", resp.Alcohol.Prob))
	}
	if resp.Tobacco != nil && resp.Tobacco.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("tobacco=%.2f", resp.Tobacco.Prob))
	}
	if resp.SelfHarm != nil && resp.SelfHarm.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("self-harm=%.2f", resp.SelfHarm.Prob))
	}
	if resp.Gambling != nil && resp.Gambling.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("gambling=%.2f", resp.Gambling.Prob))
	}
	if resp.Money != nil && resp.Money.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("money=%.2f", resp.Money.Prob))
	}
	if resp.Destruction != nil && resp.Destruction.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("destruction=%.2f", resp.Destruction.Prob))
	}
	if resp.Military != nil && resp.Military.Prob > 0.3 {
		parts = append(parts, fmt.Sprintf("military=%.2f", resp.Military.Prob))
	}
	if resp.AIGenerated != nil && resp.AIGenerated.AIGenerated > 0.5 {
		parts = append(parts, fmt.Sprintf("ai-generated=%.2f", resp.AIGenerated.AIGenerated))
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
