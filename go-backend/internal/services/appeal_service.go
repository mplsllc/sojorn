// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

type AppealService struct {
	pool *pgxpool.Pool
}

func NewAppealService(pool *pgxpool.Pool) *AppealService {
	return &AppealService{pool: pool}
}

// CreateUserViolation creates a violation record when content is flagged
func (s *AppealService) CreateUserViolation(ctx context.Context, userID uuid.UUID, moderationFlagID uuid.UUID, flagReason string, scores map[string]float64) (*models.UserViolation, error) {
	scoresJSON, err := json.Marshal(scores)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal scores: %w", err)
	}

	var violation models.UserViolation
	query := `
		SELECT * FROM create_user_violation($1, $2, $3, $4)
	`

	err = s.pool.QueryRow(ctx, query, userID, moderationFlagID, flagReason, scoresJSON).Scan(
		&violation.ID,
		&violation.UserID,
		&violation.ModerationFlagID,
		&violation.ViolationType,
		&violation.ViolationReason,
		&violation.SeverityScore,
		&violation.IsAppealable,
		&violation.AppealDeadline,
		&violation.Status,
		&violation.CreatedAt,
		&violation.UpdatedAt,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to create user violation: %w", err)
	}

	return &violation, nil
}

// GetUserViolations returns all violations for a user
func (s *AppealService) GetUserViolations(ctx context.Context, userID uuid.UUID, limit, offset int) ([]models.UserViolationResponse, error) {
	query := `
		SELECT 
			uv.*,
			mf.flag_reason,
			COALESCE(p.body, '') as post_content,
			COALESCE(c.body, '') as comment_content,
			CASE 
				WHEN uv.is_appealable = true AND uv.appeal_deadline > NOW() AND uv.status = 'active' THEN true
				ELSE false
			END as can_appeal
		FROM user_violations uv
		LEFT JOIN moderation_flags mf ON uv.moderation_flag_id = mf.id
		LEFT JOIN posts p ON mf.post_id = p.id
		LEFT JOIN comments c ON mf.comment_id = c.id
		WHERE uv.user_id = $1
		ORDER BY uv.created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := s.pool.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query user violations: %w", err)
	}
	defer rows.Close()

	var violations []models.UserViolationResponse
	for rows.Next() {
		var violation models.UserViolationResponse
		var postContent, commentContent sql.NullString
		var canAppeal bool

		err := rows.Scan(
			&violation.ID,
			&violation.UserID,
			&violation.ModerationFlagID,
			&violation.ViolationType,
			&violation.ViolationReason,
			&violation.SeverityScore,
			&violation.IsAppealable,
			&violation.AppealDeadline,
			&violation.Status,
			&violation.CreatedAt,
			&violation.UpdatedAt,
			&violation.FlagReason,
			&postContent,
			&commentContent,
			&canAppeal,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan violation: %w", err)
		}

		if postContent.Valid {
			violation.PostContent = postContent.String
		}
		if commentContent.Valid {
			violation.CommentContent = commentContent.String
		}
		violation.CanAppeal = canAppeal

		// Get appeal if exists
		if violation.Status == models.ViolationStatusAppealed {
			appeal, err := s.GetAppealForViolation(ctx, violation.ID)
			if err == nil {
				violation.Appeal = appeal
			}
		}

		violations = append(violations, violation)
	}

	return violations, nil
}

// CreateAppeal creates an appeal for a violation
func (s *AppealService) CreateAppeal(ctx context.Context, userID uuid.UUID, req *models.UserAppealRequest) (*models.UserAppeal, error) {
	// First check if violation exists and is appealable
	var violation models.UserViolation
	checkQuery := `
		SELECT uv.*, ag.appeal_window_hours
		FROM user_violations uv
		LEFT JOIN appeal_guidelines ag ON uv.violation_type = ag.violation_type AND ag.is_active = true
		WHERE uv.id = $1 AND uv.user_id = $2
	`

	var appealWindowHours sql.NullInt32
	err := s.pool.QueryRow(ctx, checkQuery, req.UserViolationID, userID).Scan(
		&violation.ID,
		&violation.UserID,
		&violation.ModerationFlagID,
		&violation.ViolationType,
		&violation.ViolationReason,
		&violation.SeverityScore,
		&violation.IsAppealable,
		&violation.AppealDeadline,
		&violation.Status,
		&violation.CreatedAt,
		&violation.UpdatedAt,
		&appealWindowHours,
	)

	if err != nil {
		return nil, fmt.Errorf("violation not found or not accessible: %w", err)
	}

	// Check if appeal is allowed
	if !violation.IsAppealable {
		return nil, fmt.Errorf("this violation type is not appealable")
	}

	if violation.Status != models.ViolationStatusActive {
		return nil, fmt.Errorf("violation has already been appealed or resolved")
	}

	if violation.AppealDeadline != nil && time.Now().After(*violation.AppealDeadline) {
		return nil, fmt.Errorf("appeal deadline has passed")
	}

	// Check monthly appeal limit
	if appealWindowHours.Valid {
		limitQuery := `
			SELECT COUNT(*) 
			FROM user_appeals ua
			JOIN user_violations uv ON ua.user_violation_id = uv.id
			WHERE ua.user_id = $1 
			AND ua.created_at >= NOW() - INTERVAL '1 month'
			AND uv.violation_type = $2
		`
		var appealCount int
		err = s.pool.QueryRow(ctx, limitQuery, userID, violation.ViolationType).Scan(&appealCount)
		if err != nil {
			return nil, fmt.Errorf("failed to check appeal limit: %w", err)
		}

		// Get max appeals per month from guidelines
		var maxAppeals int
		guidelineQuery := `SELECT max_appeals_per_month FROM appeal_guidelines WHERE violation_type = $1 AND is_active = true`
		err = s.pool.QueryRow(ctx, guidelineQuery, violation.ViolationType).Scan(&maxAppeals)
		if err != nil {
			return nil, fmt.Errorf("failed to get appeal guidelines: %w", err)
		}

		if appealCount >= maxAppeals {
			return nil, fmt.Errorf("monthly appeal limit exceeded")
		}
	}

	// Create the appeal
	evidenceJSON, _ := json.Marshal(req.EvidenceURLs)
	query := `
		INSERT INTO user_appeals (user_violation_id, user_id, appeal_reason, appeal_context, evidence_urls)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at, updated_at
	`

	var appeal models.UserAppeal
	err = s.pool.QueryRow(ctx, query, req.UserViolationID, userID, req.AppealReason, req.AppealContext, evidenceJSON).Scan(
		&appeal.ID,
		&appeal.CreatedAt,
		&appeal.UpdatedAt,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to create appeal: %w", err)
	}

	// Update violation status
	updateQuery := `UPDATE user_violations SET status = 'appealed', updated_at = NOW() WHERE id = $1`
	_, err = s.pool.Exec(ctx, updateQuery, req.UserViolationID)
	if err != nil {
		return nil, fmt.Errorf("failed to update violation status: %w", err)
	}

	// Populate appeal details
	appeal.UserViolationID = req.UserViolationID
	appeal.UserID = userID
	appeal.AppealReason = req.AppealReason
	appeal.AppealContext = req.AppealContext
	appeal.EvidenceURLs = req.EvidenceURLs
	appeal.Status = models.AppealStatusPending

	return &appeal, nil
}

// GetAppealForViolation returns the appeal for a specific violation
func (s *AppealService) GetAppealForViolation(ctx context.Context, violationID uuid.UUID) (*models.UserAppeal, error) {
	query := `
		SELECT id, user_violation_id, user_id, appeal_reason, appeal_context, evidence_urls, 
			   status, reviewed_by, review_decision, reviewed_at, created_at, updated_at
		FROM user_appeals 
		WHERE user_violation_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`

	var appeal models.UserAppeal
	var evidenceJSON []byte

	err := s.pool.QueryRow(ctx, query, violationID).Scan(
		&appeal.ID,
		&appeal.UserViolationID,
		&appeal.UserID,
		&appeal.AppealReason,
		&appeal.AppealContext,
		&evidenceJSON,
		&appeal.Status,
		&appeal.ReviewedBy,
		&appeal.ReviewDecision,
		&appeal.ReviewedAt,
		&appeal.CreatedAt,
		&appeal.UpdatedAt,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to get appeal: %w", err)
	}

	if len(evidenceJSON) > 0 {
		json.Unmarshal(evidenceJSON, &appeal.EvidenceURLs)
	}

	return &appeal, nil
}

// GetUserViolationSummary returns a summary of user's violation history
func (s *AppealService) GetUserViolationSummary(ctx context.Context, userID uuid.UUID) (*models.UserViolationSummary, error) {
	query := `
		SELECT 
			COUNT(*) as total_violations,
			COUNT(CASE WHEN violation_type = 'hard_violation' THEN 1 END) as hard_violations,
			COUNT(CASE WHEN violation_type = 'soft_violation' THEN 1 END) as soft_violations,
			COUNT(CASE WHEN status = 'appealed' THEN 1 END) as active_appeals,
			u.current_status,
			u.ban_expiry
		FROM user_violations uv
		LEFT JOIN user_violation_history u ON uv.user_id = u.user_id AND u.violation_date = CURRENT_DATE
		WHERE uv.user_id = $1
	`

	var summary models.UserViolationSummary
	var banExpiry sql.NullTime

	err := s.pool.QueryRow(ctx, query, userID).Scan(
		&summary.TotalViolations,
		&summary.HardViolations,
		&summary.SoftViolations,
		&summary.ActiveAppeals,
		&summary.CurrentStatus,
		&banExpiry,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to get violation summary: %w", err)
	}

	if banExpiry.Valid {
		summary.BanExpiry = &banExpiry.Time
	}

	// Get recent violations
	recentViolations, err := s.GetUserViolations(ctx, userID, 5, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to get recent violations: %w", err)
	}
	summary.RecentViolations = recentViolations

	return &summary, nil
}

// ReviewAppeal allows an admin to review and decide on an appeal
func (s *AppealService) ReviewAppeal(ctx context.Context, appealID uuid.UUID, adminID uuid.UUID, decision string, reviewDecision string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Update appeal
	appealQuery := `
		UPDATE user_appeals 
		SET status = CASE WHEN $1 = 'approved' THEN 'approved' ELSE 'rejected' END,
			reviewed_by = $2,
			review_decision = $3,
			reviewed_at = NOW(),
			updated_at = NOW()
		WHERE id = $4
	`

	_, err = tx.Exec(ctx, appealQuery, decision, adminID, reviewDecision, appealID)
	if err != nil {
		return fmt.Errorf("failed to update appeal: %w", err)
	}

	// Get violation ID for this appeal
	var violationID uuid.UUID
	violationQuery := `SELECT user_violation_id FROM user_appeals WHERE id = $1`
	err = tx.QueryRow(ctx, violationQuery, appealID).Scan(&violationID)
	if err != nil {
		return fmt.Errorf("failed to get violation ID: %w", err)
	}

	// Update violation status
	violationStatus := "upheld"
	if decision == "approved" {
		violationStatus = "overturned"
	}

	violationUpdateQuery := `
		UPDATE user_violations 
		SET status = $1, updated_at = NOW()
		WHERE id = $2
	`

	_, err = tx.Exec(ctx, violationUpdateQuery, violationStatus, violationID)
	if err != nil {
		return fmt.Errorf("failed to update violation status: %w", err)
	}

	// Update violation history
	historyQuery := `
		UPDATE user_violation_history 
		SET appeals_filed = appeals_filed + 1,
			appeals_upheld = appeals_upheld + CASE WHEN $1 = 'rejected' THEN 1 ELSE 0 END,
			appeals_overturned = appeals_overturned + CASE WHEN $1 = 'approved' THEN 1 ELSE 0 END,
			updated_at = NOW()
		WHERE user_id = (SELECT user_id FROM user_violations WHERE id = $2) 
		AND violation_date = CURRENT_DATE
	`

	_, err = tx.Exec(ctx, historyQuery, decision, violationID)
	if err != nil {
		return fmt.Errorf("failed to update violation history: %w", err)
	}

	return tx.Commit(ctx)
}
