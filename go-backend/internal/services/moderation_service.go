package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/oauth2/google"
)

type ModerationService struct {
	pool            *pgxpool.Pool
	httpClient      *http.Client
	openAIKey       string
	googleKey       string
	googleCredsFile string
	googleCreds     *google.Credentials
}

func NewModerationService(pool *pgxpool.Pool, openAIKey, googleKey, googleCredsFile string) *ModerationService {
	s := &ModerationService{
		pool: pool,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		openAIKey:       openAIKey,
		googleKey:       googleKey,
		googleCredsFile: googleCredsFile,
	}

	// Load Google service account credentials if provided
	if googleCredsFile != "" {
		data, err := os.ReadFile(googleCredsFile)
		if err != nil {
			fmt.Printf("Warning: failed to read Google credentials file %s: %v\n", googleCredsFile, err)
		} else {
			creds, err := google.CredentialsFromJSON(context.Background(), data, "https://www.googleapis.com/auth/cloud-vision")
			if err != nil {
				fmt.Printf("Warning: failed to parse Google credentials: %v\n", err)
			} else {
				s.googleCreds = creds
				fmt.Printf("Google Vision: loaded service account credentials (project: %s)\n", creds.ProjectID)
			}
		}
	}

	return s
}

// HasGoogleVision returns true if Google Vision is configured via API key or service account
func (s *ModerationService) HasGoogleVision() bool {
	return s.googleKey != "" || s.googleCreds != nil
}

type ThreePoisonsScore struct {
	Hate     float64 `json:"hate"`
	Greed    float64 `json:"greed"`
	Delusion float64 `json:"delusion"`
}

// OpenAIModerationResponse represents the response from OpenAI Moderation API
type OpenAIModerationResponse struct {
	Results []struct {
		Categories struct {
			Hate                  bool `json:"hate"`
			HateThreatening       bool `json:"hate/threatening"`
			Harassment            bool `json:"harassment"`
			HarassmentThreatening bool `json:"harassment/threatening"`
			SelfHarm              bool `json:"self-harm"`
			SelfHarmIntent        bool `json:"self-harm/intent"`
			SelfHarmInstructions  bool `json:"self-harm/instructions"`
			Sexual                bool `json:"sexual"`
			SexualMinors          bool `json:"sexual/minors"`
			Violence              bool `json:"violence"`
			ViolenceGraphic       bool `json:"violence/graphic"`
		} `json:"categories"`
		CategoryScores struct {
			Hate                  float64 `json:"hate"`
			HateThreatening       float64 `json:"hate/threatening"`
			Harassment            float64 `json:"harassment"`
			HarassmentThreatening float64 `json:"harassment/threatening"`
			SelfHarm              float64 `json:"self-harm"`
			SelfHarmIntent        float64 `json:"self-harm/intent"`
			SelfHarmInstructions  float64 `json:"self-harm/instructions"`
			Sexual                float64 `json:"sexual"`
			SexualMinors          float64 `json:"sexual/minors"`
			Violence              float64 `json:"violence"`
			ViolenceGraphic       float64 `json:"violence/graphic"`
		} `json:"category_scores"`
		Flagged bool `json:"flagged"`
	} `json:"results"`
}

// GoogleVisionSafeSearch represents SafeSearch detection results
type GoogleVisionSafeSearch struct {
	Adult    string `json:"adult"`
	Spoof    string `json:"spoof"`
	Medical  string `json:"medical"`
	Violence string `json:"violence"`
	Racy     string `json:"racy"`
}

// GoogleVisionResponse represents the response from Google Vision API
type GoogleVisionResponse struct {
	Responses []struct {
		SafeSearchAnnotation GoogleVisionSafeSearch `json:"safeSearchAnnotation"`
	} `json:"responses"`
}

func (s *ModerationService) AnalyzeContent(ctx context.Context, body string, mediaURLs []string) (*ThreePoisonsScore, string, error) {
	score := &ThreePoisonsScore{
		Hate:     0.0,
		Greed:    0.0,
		Delusion: 0.0,
	}

	// Analyze text with OpenAI Moderation API
	if s.openAIKey != "" && body != "" {
		openAIScore, err := s.analyzeWithOpenAI(ctx, body)
		if err != nil {
			// Log error but continue with fallback
			fmt.Printf("OpenAI moderation error: %v\n", err)
		} else {
			score = openAIScore
		}
	}

	// Analyze media with Google Vision API if provided
	if s.HasGoogleVision() && len(mediaURLs) > 0 {
		visionScore, err := s.AnalyzeMediaWithGoogleVision(ctx, mediaURLs)
		if err != nil {
			fmt.Printf("Google Vision analysis error: %v\n", err)
		} else {
			// Merge vision scores with existing scores
			if visionScore.Hate > score.Hate {
				score.Hate = visionScore.Hate
			}
			if visionScore.Delusion > score.Delusion {
				score.Delusion = visionScore.Delusion
			}
		}
	}

	// Fallback to keyword-based analysis for greed/spam detection
	if score.Greed == 0.0 {
		greedKeywords := []string{
			"buy", "crypto", "rich", "scam", "investment", "profit",
			"money", "cash", "bitcoin", "ethereum", "trading", "forex",
			"get rich", "quick money", "guaranteed returns", "multiplier",
		}
		if containsAny(body, greedKeywords) {
			score.Greed = 0.7
		}
	}

	// Determine primary flag reason
	flagReason := ""
	if score.Hate > 0.5 {
		flagReason = "hate"
	} else if score.Greed > 0.5 {
		flagReason = "greed"
	} else if score.Delusion > 0.5 {
		flagReason = "delusion"
	}

	return score, flagReason, nil
}

// analyzeWithOpenAI sends content to OpenAI Moderation API
func (s *ModerationService) analyzeWithOpenAI(ctx context.Context, content string) (*ThreePoisonsScore, error) {
	if s.openAIKey == "" {
		return nil, fmt.Errorf("OpenAI API key not configured")
	}

	requestBody := map[string]interface{}{
		"input": content,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/moderations", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openAIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("OpenAI API error: %d - %s", resp.StatusCode, string(body))
	}

	var moderationResp OpenAIModerationResponse
	if err := json.NewDecoder(resp.Body).Decode(&moderationResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if len(moderationResp.Results) == 0 {
		return &ThreePoisonsScore{Hate: 0, Greed: 0, Delusion: 0}, nil
	}

	result := moderationResp.Results[0]
	scores := result.CategoryScores
	score := &ThreePoisonsScore{
		// Map OpenAI category scores to Three Poisons
		Hate: max(
			scores.Hate,
			scores.HateThreatening,
			scores.Harassment,
			scores.HarassmentThreatening,
			scores.Violence,
			scores.ViolenceGraphic,
			scores.Sexual,
			scores.SexualMinors,
		),
		Greed: 0, // OpenAI doesn't detect greed/spam — handled by keyword fallback
		Delusion: max(
			scores.SelfHarm,
			scores.SelfHarmIntent,
			scores.SelfHarmInstructions,
		),
	}

	fmt.Printf("OpenAI moderation: flagged=%v hate=%.3f greed=%.3f delusion=%.3f\n", result.Flagged, score.Hate, score.Greed, score.Delusion)
	return score, nil
}

// AnalyzeMediaWithGoogleVision analyzes images for inappropriate content.
// Supports both API key auth and OAuth2 service account auth.
// Returns ThreePoisonsScore for integration with moderation flow.
func (s *ModerationService) AnalyzeMediaWithGoogleVision(ctx context.Context, mediaURLs []string) (*ThreePoisonsScore, error) {
	if s.googleKey == "" && s.googleCreds == nil {
		return nil, fmt.Errorf("Google Vision not configured (need API key or service account)")
	}

	score := &ThreePoisonsScore{
		Hate:     0.0,
		Greed:    0.0,
		Delusion: 0.0,
	}

	for _, mediaURL := range mediaURLs {
		// Only process image URLs
		if !isImageURL(mediaURL) {
			continue
		}

		requestBody := map[string]interface{}{
			"requests": []map[string]interface{}{
				{
					"image": map[string]interface{}{
						"source": map[string]interface{}{
							"imageUri": mediaURL,
						},
					},
					"features": []map[string]interface{}{
						{
							"type":       "SAFE_SEARCH_DETECTION",
							"maxResults": 1,
						},
					},
				},
			},
		}

		jsonBody, err := json.Marshal(requestBody)
		if err != nil {
			continue
		}

		req, err := http.NewRequestWithContext(ctx, "POST", "https://vision.googleapis.com/v1/images:annotate", bytes.NewBuffer(jsonBody))
		if err != nil {
			continue
		}
		req.Header.Set("Content-Type", "application/json")

		// Auth: prefer service account OAuth2, fall back to API key
		if s.googleCreds != nil {
			token, err := s.googleCreds.TokenSource.Token()
			if err != nil {
				fmt.Printf("Google Vision: failed to get OAuth2 token: %v\n", err)
				continue
			}
			req.Header.Set("Authorization", "Bearer "+token.AccessToken)
		} else {
			req.URL.RawQuery = "key=" + s.googleKey
		}

		resp, err := s.httpClient.Do(req)
		if err != nil {
			fmt.Printf("Google Vision: request failed: %v\n", err)
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			fmt.Printf("Google Vision: API error %d: %s\n", resp.StatusCode, string(body))
			continue
		}

		var visionResp GoogleVisionResponse
		if err := json.NewDecoder(resp.Body).Decode(&visionResp); err != nil {
			continue
		}

		if len(visionResp.Responses) > 0 {
			imageScore := s.convertVisionScore(visionResp.Responses[0].SafeSearchAnnotation)
			// Merge with overall score (take maximum)
			if imageScore.Hate > score.Hate {
				score.Hate = imageScore.Hate
			}
			if imageScore.Delusion > score.Delusion {
				score.Delusion = imageScore.Delusion
			}
		}
	}

	return score, nil
}

// AnalyzeImageWithGoogleVision is an exported method for testing Google Vision directly from the admin panel.
// Returns the raw SafeSearch annotations plus the mapped Three Poisons scores.
func (s *ModerationService) AnalyzeImageWithGoogleVision(ctx context.Context, imageURL string) (map[string]interface{}, error) {
	if s.googleKey == "" && s.googleCreds == nil {
		return nil, fmt.Errorf("Google Vision not configured (need API key or service account)")
	}

	requestBody := map[string]interface{}{
		"requests": []map[string]interface{}{
			{
				"image": map[string]interface{}{
					"source": map[string]interface{}{
						"imageUri": imageURL,
					},
				},
				"features": []map[string]interface{}{
					{
						"type":       "SAFE_SEARCH_DETECTION",
						"maxResults": 1,
					},
				},
			},
		},
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://vision.googleapis.com/v1/images:annotate", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	if s.googleCreds != nil {
		token, err := s.googleCreds.TokenSource.Token()
		if err != nil {
			return nil, fmt.Errorf("failed to get OAuth2 token: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+token.AccessToken)
	} else {
		req.URL.RawQuery = "key=" + s.googleKey
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Google Vision request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("Google Vision API error %d: %s", resp.StatusCode, string(body))
	}

	var visionResp GoogleVisionResponse
	if err := json.NewDecoder(resp.Body).Decode(&visionResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if len(visionResp.Responses) == 0 {
		return nil, fmt.Errorf("no response from Google Vision")
	}

	safeSearch := visionResp.Responses[0].SafeSearchAnnotation
	scores := s.convertVisionScore(safeSearch)

	action := "clean"
	flagged := false
	if scores.Hate > 0.5 || scores.Delusion > 0.5 {
		action = "flag"
		flagged = true
	} else if scores.Hate > 0.25 || scores.Delusion > 0.25 {
		action = "nsfw"
	}

	return map[string]interface{}{
		"action":          action,
		"flagged":         flagged,
		"hate":            scores.Hate,
		"greed":           scores.Greed,
		"delusion":        scores.Delusion,
		"hate_detail":     fmt.Sprintf("Adult=%s Violence=%s Racy=%s", safeSearch.Adult, safeSearch.Violence, safeSearch.Racy),
		"greed_detail":    fmt.Sprintf("Spoof=%s", safeSearch.Spoof),
		"delusion_detail": fmt.Sprintf("Medical=%s", safeSearch.Medical),
		"explanation":     fmt.Sprintf("Google Vision SafeSearch: Adult=%s, Violence=%s, Racy=%s, Spoof=%s, Medical=%s", safeSearch.Adult, safeSearch.Violence, safeSearch.Racy, safeSearch.Spoof, safeSearch.Medical),
		"raw_content":     fmt.Sprintf("Adult=%s Violence=%s Racy=%s Spoof=%s Medical=%s → Hate=%.2f Greed=%.2f Delusion=%.2f", safeSearch.Adult, safeSearch.Violence, safeSearch.Racy, safeSearch.Spoof, safeSearch.Medical, scores.Hate, scores.Greed, scores.Delusion),
	}, nil
}

// convertVisionScore converts Google Vision SafeSearch results to ThreePoisonsScore
func (s *ModerationService) convertVisionScore(safeSearch GoogleVisionSafeSearch) *ThreePoisonsScore {
	score := &ThreePoisonsScore{
		Hate:     0.0,
		Greed:    0.0,
		Delusion: 0.0,
	}

	// Convert string likelihoods to numeric scores
	likelihoodToScore := map[string]float64{
		"UNKNOWN":       0.0,
		"VERY_UNLIKELY": 0.1,
		"UNLIKELY":      0.3,
		"POSSIBLE":      0.5,
		"LIKELY":        0.7,
		"VERY_LIKELY":   0.9,
	}

	// Map Vision categories to Three Poisons
	if hateScore, ok := likelihoodToScore[safeSearch.Violence]; ok {
		score.Hate = hateScore
	}
	if adultScore, ok := likelihoodToScore[safeSearch.Adult]; ok && adultScore > score.Hate {
		score.Hate = adultScore
	}
	if racyScore, ok := likelihoodToScore[safeSearch.Racy]; ok && racyScore > score.Delusion {
		score.Delusion = racyScore
	}

	return score
}

// Helper function to get maximum of multiple floats
func max(values ...float64) float64 {
	maxVal := 0.0
	for _, v := range values {
		if v > maxVal {
			maxVal = v
		}
	}
	return maxVal
}

// Helper function to check if URL is an image
func isImageURL(url string) bool {
	imageExtensions := []string{".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}
	lowerURL := strings.ToLower(url)
	for _, ext := range imageExtensions {
		if strings.HasSuffix(lowerURL, ext) {
			return true
		}
	}
	return false
}

func (s *ModerationService) FlagPost(ctx context.Context, postID uuid.UUID, scores *ThreePoisonsScore, reason string) error {
	scoresJSON, err := json.Marshal(scores)
	if err != nil {
		return fmt.Errorf("failed to marshal scores: %w", err)
	}

	var flagID uuid.UUID
	err = s.pool.QueryRow(ctx, `
		INSERT INTO moderation_flags (post_id, flag_reason, scores, status)
		VALUES ($1, $2, $3, 'pending')
		RETURNING id
	`, postID, reason, scoresJSON).Scan(&flagID)
	if err != nil {
		return fmt.Errorf("failed to insert moderation flag: %w", err)
	}

	fmt.Printf("Moderation flag created: id=%s post=%s reason=%s\n", flagID, postID, reason)

	// Look up the post author and create a violation record
	var authorID uuid.UUID
	if err := s.pool.QueryRow(ctx, `SELECT author_id FROM posts WHERE id = $1`, postID).Scan(&authorID); err == nil && authorID != uuid.Nil {
		var violationID uuid.UUID
		if err := s.pool.QueryRow(ctx, `SELECT create_user_violation($1, $2, $3, $4)`, authorID, flagID, reason, scoresJSON).Scan(&violationID); err != nil {
			fmt.Printf("Failed to create user violation: %v\n", err)
		}
	}

	return nil
}

func (s *ModerationService) FlagComment(ctx context.Context, commentID uuid.UUID, scores *ThreePoisonsScore, reason string) error {
	scoresJSON, err := json.Marshal(scores)
	if err != nil {
		return fmt.Errorf("failed to marshal scores: %w", err)
	}

	var flagID uuid.UUID
	err = s.pool.QueryRow(ctx, `
		INSERT INTO moderation_flags (comment_id, flag_reason, scores, status)
		VALUES ($1, $2, $3, 'pending')
		RETURNING id
	`, commentID, reason, scoresJSON).Scan(&flagID)
	if err != nil {
		return fmt.Errorf("failed to insert comment moderation flag: %w", err)
	}

	fmt.Printf("Moderation flag created: id=%s comment=%s reason=%s\n", flagID, commentID, reason)

	// Look up the comment author and create a violation record
	var authorID uuid.UUID
	if err := s.pool.QueryRow(ctx, `SELECT author_id FROM comments WHERE id = $1`, commentID).Scan(&authorID); err == nil && authorID != uuid.Nil {
		var violationID uuid.UUID
		if err := s.pool.QueryRow(ctx, `SELECT create_user_violation($1, $2, $3, $4)`, authorID, flagID, reason, scoresJSON).Scan(&violationID); err != nil {
			fmt.Printf("Failed to create user violation: %v\n", err)
		}
	}

	return nil
}

// GetPendingFlags retrieves all pending moderation flags
func (s *ModerationService) GetPendingFlags(ctx context.Context, limit, offset int) ([]map[string]interface{}, error) {
	query := `
		SELECT 
			mf.id, mf.post_id, mf.comment_id, mf.flag_reason, mf.scores, 
			mf.status, mf.created_at,
			p.content as post_content,
			c.content as comment_content,
			u.handle as author_handle
		FROM moderation_flags mf
		LEFT JOIN posts p ON mf.post_id = p.id
		LEFT JOIN comments c ON mf.comment_id = c.id
		LEFT JOIN users u ON (p.user_id = u.id OR c.user_id = u.id)
		WHERE mf.status = 'pending'
		ORDER BY mf.created_at ASC
		LIMIT $1 OFFSET $2
	`

	rows, err := s.pool.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query pending flags: %w", err)
	}
	defer rows.Close()

	var flags []map[string]interface{}
	for rows.Next() {
		var id, postID, commentID uuid.UUID
		var flagReason, status string
		var scoresJSON []byte
		var createdAt time.Time
		var postContent, commentContent, authorHandle *string

		err := rows.Scan(&id, &postID, &commentID, &flagReason, &scoresJSON, &status, &createdAt, &postContent, &commentContent, &authorHandle)
		if err != nil {
			return nil, fmt.Errorf("failed to scan flag row: %w", err)
		}

		var scores map[string]float64
		if err := json.Unmarshal(scoresJSON, &scores); err != nil {
			return nil, fmt.Errorf("failed to unmarshal scores: %w", err)
		}

		flag := map[string]interface{}{
			"id":              id,
			"post_id":         postID,
			"comment_id":      commentID,
			"flag_reason":     flagReason,
			"scores":          scores,
			"status":          status,
			"created_at":      createdAt,
			"post_content":    postContent,
			"comment_content": commentContent,
			"author_handle":   authorHandle,
		}

		flags = append(flags, flag)
	}

	return flags, nil
}

// UpdateFlagStatus updates the status of a moderation flag
func (s *ModerationService) UpdateFlagStatus(ctx context.Context, flagID uuid.UUID, status string, reviewedBy uuid.UUID) error {
	query := `
		UPDATE moderation_flags 
		SET status = $1, reviewed_by = $2, reviewed_at = NOW()
		WHERE id = $3
	`

	_, err := s.pool.Exec(ctx, query, status, reviewedBy, flagID)
	if err != nil {
		return fmt.Errorf("failed to update flag status: %w", err)
	}

	return nil
}

// UpdateUserStatus updates a user's moderation status
func (s *ModerationService) UpdateUserStatus(ctx context.Context, userID uuid.UUID, status string, changedBy uuid.UUID, reason string) error {
	query := `
		UPDATE users 
		SET status = $1
		WHERE id = $2
	`

	_, err := s.pool.Exec(ctx, query, status, userID)
	if err != nil {
		return fmt.Errorf("failed to update user status: %w", err)
	}

	// Log the status change
	historyQuery := `
		INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by)
		SELECT $1, status, $2, $3, $4
		FROM users 
		WHERE id = $1
	`

	_, err = s.pool.Exec(ctx, historyQuery, userID, status, reason, changedBy)
	if err != nil {
		// Log error but don't fail the main operation
		fmt.Printf("Failed to log user status change: %v\n", err)
	}

	return nil
}

// ============================================================================
// AI Moderation Audit Log
// ============================================================================

// LogAIDecision records an AI moderation decision to the audit log
func (s *ModerationService) LogAIDecision(ctx context.Context, contentType string, contentID uuid.UUID, authorID uuid.UUID, contentSnippet string, scores *ThreePoisonsScore, rawScores json.RawMessage, decision string, flagReason string, orDecision string, orScores json.RawMessage) {
	snippet := contentSnippet
	if len(snippet) > 200 {
		snippet = snippet[:200]
	}

	_, err := s.pool.Exec(ctx, `
		INSERT INTO ai_moderation_log (content_type, content_id, author_id, content_snippet, decision, flag_reason, scores_hate, scores_greed, scores_delusion, raw_scores, or_decision, or_scores)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
	`, contentType, contentID, authorID, snippet, decision, flagReason, scores.Hate, scores.Greed, scores.Delusion, rawScores, orDecision, orScores)
	if err != nil {
		fmt.Printf("Failed to log AI moderation decision: %v\n", err)
	}
}

// GetAIModerationLog retrieves the AI moderation audit log with filters
func (s *ModerationService) GetAIModerationLog(ctx context.Context, limit, offset int, decision, contentType, search string, feedbackFilter string) ([]map[string]interface{}, int, error) {
	where := "WHERE 1=1"
	args := []interface{}{}
	argIdx := 1

	if decision != "" {
		where += fmt.Sprintf(" AND aml.decision = $%d", argIdx)
		args = append(args, decision)
		argIdx++
	}
	if contentType != "" {
		where += fmt.Sprintf(" AND aml.content_type = $%d", argIdx)
		args = append(args, contentType)
		argIdx++
	}
	if search != "" {
		where += fmt.Sprintf(" AND (aml.content_snippet ILIKE '%%' || $%d || '%%' OR pr.handle ILIKE '%%' || $%d || '%%')", argIdx, argIdx)
		args = append(args, search)
		argIdx++
	}
	if feedbackFilter == "reviewed" {
		where += " AND aml.feedback_correct IS NOT NULL"
	} else if feedbackFilter == "unreviewed" {
		where += " AND aml.feedback_correct IS NULL"
	}

	// Count total
	var total int
	countArgs := make([]interface{}, len(args))
	copy(countArgs, args)
	s.pool.QueryRow(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM ai_moderation_log aml LEFT JOIN profiles pr ON aml.author_id = pr.id %s`, where), countArgs...).Scan(&total)

	// Fetch rows
	query := fmt.Sprintf(`
		SELECT aml.id, aml.content_type, aml.content_id, aml.author_id, aml.content_snippet,
		       aml.ai_provider, aml.decision, aml.flag_reason,
		       aml.scores_hate, aml.scores_greed, aml.scores_delusion, aml.raw_scores,
		       aml.or_decision, aml.or_scores,
		       aml.feedback_correct, aml.feedback_reason, aml.feedback_by, aml.feedback_at,
		       aml.created_at,
		       COALESCE(pr.handle, '') as author_handle,
		       COALESCE(pr.display_name, '') as author_display_name
		FROM ai_moderation_log aml
		LEFT JOIN profiles pr ON aml.author_id = pr.id
		%s
		ORDER BY aml.created_at DESC
		LIMIT $%d OFFSET $%d
	`, where, argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query ai moderation log: %w", err)
	}
	defer rows.Close()

	var items []map[string]interface{}
	for rows.Next() {
		var id, contentID, authorID uuid.UUID
		var cType, snippet, aiProvider, dec string
		var flagReason, orDecision, feedbackReason *string
		var feedbackBy *uuid.UUID
		var feedbackCorrect *bool
		var feedbackAt *time.Time
		var scoresHate, scoresGreed, scoresDelusion float64
		var rawScores, orScores []byte
		var createdAt time.Time
		var authorHandle, authorDisplayName string

		if err := rows.Scan(&id, &cType, &contentID, &authorID, &snippet,
			&aiProvider, &dec, &flagReason,
			&scoresHate, &scoresGreed, &scoresDelusion, &rawScores,
			&orDecision, &orScores,
			&feedbackCorrect, &feedbackReason, &feedbackBy, &feedbackAt,
			&createdAt,
			&authorHandle, &authorDisplayName,
		); err != nil {
			fmt.Printf("Failed to scan ai moderation log row: %v\n", err)
			continue
		}

		item := map[string]interface{}{
			"id":                  id,
			"content_type":        cType,
			"content_id":          contentID,
			"author_id":           authorID,
			"content_snippet":     snippet,
			"ai_provider":         aiProvider,
			"decision":            dec,
			"flag_reason":         flagReason,
			"scores_hate":         scoresHate,
			"scores_greed":        scoresGreed,
			"scores_delusion":     scoresDelusion,
			"raw_scores":          json.RawMessage(rawScores),
			"or_decision":         orDecision,
			"or_scores":           json.RawMessage(orScores),
			"feedback_correct":    feedbackCorrect,
			"feedback_reason":     feedbackReason,
			"feedback_by":         feedbackBy,
			"feedback_at":         feedbackAt,
			"created_at":          createdAt,
			"author_handle":       authorHandle,
			"author_display_name": authorDisplayName,
		}
		items = append(items, item)
	}

	return items, total, nil
}

// SubmitAIFeedback records admin training feedback on an AI moderation decision
func (s *ModerationService) SubmitAIFeedback(ctx context.Context, logID uuid.UUID, correct bool, reason string, adminID uuid.UUID) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE ai_moderation_log 
		SET feedback_correct = $1, feedback_reason = $2, feedback_by = $3, feedback_at = NOW()
		WHERE id = $4
	`, correct, reason, adminID, logID)
	if err != nil {
		return fmt.Errorf("failed to submit AI feedback: %w", err)
	}
	return nil
}

// GetAITrainingData exports all reviewed feedback entries for fine-tuning
func (s *ModerationService) GetAITrainingData(ctx context.Context) ([]map[string]interface{}, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT content_snippet, decision, flag_reason, scores_hate, scores_greed, scores_delusion,
		       feedback_correct, feedback_reason
		FROM ai_moderation_log
		WHERE feedback_correct IS NOT NULL
		ORDER BY feedback_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []map[string]interface{}
	for rows.Next() {
		var snippet, decision string
		var flagReason, feedbackReason *string
		var hate, greed, delusion float64
		var correct bool

		if err := rows.Scan(&snippet, &decision, &flagReason, &hate, &greed, &delusion, &correct, &feedbackReason); err != nil {
			continue
		}
		items = append(items, map[string]interface{}{
			"content":         snippet,
			"ai_decision":     decision,
			"ai_flag_reason":  flagReason,
			"scores":          map[string]float64{"hate": hate, "greed": greed, "delusion": delusion},
			"correct":         correct,
			"feedback_reason": feedbackReason,
		})
	}
	return items, nil
}

func containsAny(body string, terms []string) bool {
	// Case insensitive check
	lower := bytes.ToLower([]byte(body))
	for _, term := range terms {
		if bytes.Contains(lower, []byte(term)) {
			return true
		}
	}
	return false
}
