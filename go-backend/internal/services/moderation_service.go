// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ModerationService provides DB operations for content moderation:
// flagging, audit logging, feedback, and AI engine configuration.
type ModerationService struct {
	pool       *pgxpool.Pool
}

func NewModerationService(pool *pgxpool.Pool) *ModerationService {
	return &ModerationService{pool: pool}
}

// ============================================================================
// Three Poisons Score
// ============================================================================

type ThreePoisonsScore struct {
	Hate     float64 `json:"hate"`
	Greed    float64 `json:"greed"`
	Delusion float64 `json:"delusion"`
}

// ============================================================================
// AI Moderation Config (from ai_moderation_config table)
// ============================================================================

// ModerationConfigEntry represents a row in ai_moderation_config.
type ModerationConfigEntry struct {
	ID               string            `json:"id"`
	ModerationType   string            `json:"moderation_type"`
	ModelID          string            `json:"model_id"`
	ModelName        string            `json:"model_name"`
	SystemPrompt     string            `json:"system_prompt"`
	Enabled          bool              `json:"enabled"`
	Engines          []string          `json:"engines"`
	SightEngineConfig json.RawMessage  `json:"sightengine_config"`
	UpdatedAt        time.Time         `json:"updated_at"`
	UpdatedBy        *string           `json:"updated_by,omitempty"`
}

// SightEngineModelConfig controls per-model enablement and thresholds.
type SightEngineModelConfig struct {
	Enabled   bool    `json:"enabled"`
	Threshold float64 `json:"threshold"`
}

// SightEngineConfig is the parsed form of the sightengine_config JSONB.
type SightEngineConfig struct {
	ImageModels    map[string]SightEngineModelConfig `json:"image_models"`
	TextModels     map[string]SightEngineModelConfig `json:"text_models"`
	TextCategories map[string]bool                   `json:"text_categories"`
	NSFWThreshold  float64                           `json:"nsfw_threshold"`
	FlagThreshold  float64                           `json:"flag_threshold"`
}

// ParseSightEngineConfig parses the raw JSON config into a typed struct.
func (c *ModerationConfigEntry) ParseSightEngineConfig() *SightEngineConfig {
	if len(c.SightEngineConfig) == 0 {
		return &SightEngineConfig{
			NSFWThreshold: 0.4,
			FlagThreshold: 0.7,
		}
	}
	var cfg SightEngineConfig
	if err := json.Unmarshal(c.SightEngineConfig, &cfg); err != nil {
		return &SightEngineConfig{
			NSFWThreshold: 0.4,
			FlagThreshold: 0.7,
		}
	}
	if cfg.NSFWThreshold == 0 {
		cfg.NSFWThreshold = 0.4
	}
	if cfg.FlagThreshold == 0 {
		cfg.FlagThreshold = 0.7
	}
	return &cfg
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

// GetModerationConfigs returns all moderation type configurations.
func (s *ModerationService) GetModerationConfigs(ctx context.Context) ([]ModerationConfigEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, moderation_type, model_id, model_name, system_prompt, enabled, engines, sightengine_config, updated_at, updated_by
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
		if err := rows.Scan(&c.ID, &c.ModerationType, &c.ModelID, &c.ModelName, &c.SystemPrompt, &c.Enabled, &c.Engines, &c.SightEngineConfig, &c.UpdatedAt, &c.UpdatedBy); err != nil {
			return nil, err
		}
		configs = append(configs, c)
	}
	return configs, nil
}

// GetModerationConfig returns config for a specific moderation type.
func (s *ModerationService) GetModerationConfig(ctx context.Context, moderationType string) (*ModerationConfigEntry, error) {
	var c ModerationConfigEntry
	err := s.pool.QueryRow(ctx, `
		SELECT id, moderation_type, model_id, model_name, system_prompt, enabled, engines, sightengine_config, updated_at, updated_by
		FROM ai_moderation_config WHERE moderation_type = $1
	`, moderationType).Scan(&c.ID, &c.ModerationType, &c.ModelID, &c.ModelName, &c.SystemPrompt, &c.Enabled, &c.Engines, &c.SightEngineConfig, &c.UpdatedAt, &c.UpdatedBy)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// SetModerationConfig upserts a moderation config.
func (s *ModerationService) SetModerationConfig(ctx context.Context, moderationType, modelID, modelName, systemPrompt string, enabled bool, engines []string, updatedBy string, sightengineConfig json.RawMessage) error {
	if len(engines) == 0 {
		engines = []string{"local_ai", "sightengine"}
	}
	if len(sightengineConfig) == 0 {
		sightengineConfig = json.RawMessage(`{}`)
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO ai_moderation_config (moderation_type, model_id, model_name, system_prompt, enabled, engines, updated_by, sightengine_config, updated_at)
		VALUES ($1, $2, $3, $4, $5, $7, $6, $8, NOW())
		ON CONFLICT (moderation_type)
		DO UPDATE SET model_id = $2, model_name = $3, system_prompt = $4, enabled = $5, engines = $7, updated_by = $6, sightengine_config = $8, updated_at = NOW()
	`, moderationType, modelID, modelName, systemPrompt, enabled, updatedBy, engines, sightengineConfig)
	return err
}

// ============================================================================
// Flagging
// ============================================================================

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
	_, err := s.pool.Exec(ctx, `
		UPDATE moderation_flags
		SET status = $1, reviewed_by = $2, reviewed_at = NOW()
		WHERE id = $3
	`, status, reviewedBy, flagID)
	if err != nil {
		return fmt.Errorf("failed to update flag status: %w", err)
	}
	return nil
}

// UpdateUserStatus updates a user's moderation status
func (s *ModerationService) UpdateUserStatus(ctx context.Context, userID uuid.UUID, status string, changedBy uuid.UUID, reason string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE users
		SET status = $1
		WHERE id = $2
	`, status, userID)
	if err != nil {
		return fmt.Errorf("failed to update user status: %w", err)
	}

	_, err = s.pool.Exec(ctx, `
		INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by)
		SELECT $1, status, $2, $3, $4
		FROM users
		WHERE id = $1
	`, userID, status, reason, changedBy)
	if err != nil {
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

	var total int
	countArgs := make([]interface{}, len(args))
	copy(countArgs, args)
	s.pool.QueryRow(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM ai_moderation_log aml LEFT JOIN profiles pr ON aml.author_id = pr.id %s`, where), countArgs...).Scan(&total)

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
	lower := bytes.ToLower([]byte(body))
	for _, term := range terms {
		if bytes.Contains(lower, []byte(term)) {
			return true
		}
	}
	return false
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
