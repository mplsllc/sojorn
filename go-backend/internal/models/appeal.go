// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package models

import (
	"time"

	"github.com/google/uuid"
)

type ViolationType string

const (
	ViolationTypeHard ViolationType = "hard_violation"
	ViolationTypeSoft ViolationType = "soft_violation"
)

type ViolationStatus string

const (
	ViolationStatusActive     ViolationStatus = "active"
	ViolationStatusAppealed   ViolationStatus = "appealed"
	ViolationStatusUpheld     ViolationStatus = "upheld"
	ViolationStatusOverturned ViolationStatus = "overturned"
	ViolationStatusExpired    ViolationStatus = "expired"
)

type AccountStatus string

const (
	AccountStatusActive      AccountStatus = "active"
	AccountStatusWarning     AccountStatus = "warning"
	AccountStatusSuspended   AccountStatus = "suspended"
	AccountStatusBanned      AccountStatus = "banned"
	AccountStatusUnderReview AccountStatus = "under_review"
)

type AppealStatus string

const (
	AppealStatusPending   AppealStatus = "pending"
	AppealStatusReviewing AppealStatus = "reviewing"
	AppealStatusApproved  AppealStatus = "approved"
	AppealStatusRejected  AppealStatus = "rejected"
	AppealStatusWithdrawn AppealStatus = "withdrawn"
)

type UserViolation struct {
	ID                    uuid.UUID       `json:"id" db:"id"`
	UserID                uuid.UUID       `json:"user_id" db:"user_id"`
	ModerationFlagID      uuid.UUID       `json:"moderation_flag_id" db:"moderation_flag_id"`
	ViolationType         ViolationType   `json:"violation_type" db:"violation_type"`
	ViolationReason       string          `json:"violation_reason" db:"violation_reason"`
	SeverityScore         float64         `json:"severity_score" db:"severity_score"`
	IsAppealable          bool            `json:"is_appealable" db:"is_appealable"`
	AppealDeadline        *time.Time      `json:"appeal_deadline" db:"appeal_deadline"`
	Status                ViolationStatus `json:"status" db:"status"`
	ContentDeleted        bool            `json:"content_deleted" db:"content_deleted"`
	ContentDeletionReason string          `json:"content_deletion_reason" db:"content_deletion_reason"`
	AccountStatusChange   string          `json:"account_status_change" db:"account_status_change"`
	CreatedAt             time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt             time.Time       `json:"updated_at" db:"updated_at"`
}

type UserAppeal struct {
	ID              uuid.UUID    `json:"id" db:"id"`
	UserViolationID uuid.UUID    `json:"user_violation_id" db:"user_violation_id"`
	UserID          uuid.UUID    `json:"user_id" db:"user_id"`
	AppealReason    string       `json:"appeal_reason" db:"appeal_reason"`
	AppealContext   string       `json:"appeal_context" db:"appeal_context"`
	EvidenceURLs    []string     `json:"evidence_urls" db:"evidence_urls"`
	Status          AppealStatus `json:"status" db:"status"`
	ReviewedBy      *uuid.UUID   `json:"reviewed_by" db:"reviewed_by"`
	ReviewDecision  string       `json:"review_decision" db:"review_decision"`
	ReviewedAt      *time.Time   `json:"reviewed_at" db:"reviewed_at"`
	CreatedAt       time.Time    `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time    `json:"updated_at" db:"updated_at"`
}

type UserViolationHistory struct {
	ID                 uuid.UUID  `json:"id" db:"id"`
	UserID             uuid.UUID  `json:"user_id" db:"user_id"`
	ViolationDate      time.Time  `json:"violation_date" db:"violation_date"`
	TotalViolations    int        `json:"total_violations" db:"total_violations"`
	HardViolations     int        `json:"hard_violations" db:"hard_violations"`
	SoftViolations     int        `json:"soft_violations" db:"soft_violations"`
	AppealsFiled       int        `json:"appeals_filed" db:"appeals_filed"`
	AppealsUpheld      int        `json:"appeals_upheld" db:"appeals_upheld"`
	AppealsOverturned  int        `json:"appeals_overturned" db:"appeals_overturned"`
	ContentDeletions   int        `json:"content_deletions" db:"content_deletions"`
	AccountWarnings    int        `json:"account_warnings" db:"account_warnings"`
	AccountSuspensions int        `json:"account_suspensions" db:"account_suspensions"`
	CurrentStatus      string     `json:"current_status" db:"current_status"`
	BanExpiry          *time.Time `json:"ban_expiry" db:"ban_expiry"`
	CreatedAt          time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at" db:"updated_at"`
}

type AppealGuideline struct {
	ID                        uuid.UUID `json:"id" db:"id"`
	ViolationType             string    `json:"violation_type" db:"violation_type"`
	MaxAppealsPerMonth        int       `json:"max_appeals_per_month" db:"max_appeals_per_month"`
	AppealWindowHours         int       `json:"appeal_window_hours" db:"appeal_window_hours"`
	AutoBanThreshold          int       `json:"auto_ban_threshold" db:"auto_ban_threshold"`
	HardViolationBanThreshold int       `json:"hard_violation_ban_threshold" db:"hard_violation_ban_threshold"`
	IsActive                  bool      `json:"is_active" db:"is_active"`
	CreatedAt                 time.Time `json:"created_at" db:"created_at"`
	UpdatedAt                 time.Time `json:"updated_at" db:"updated_at"`
}

// DTOs for API responses
type UserViolationResponse struct {
	UserViolation
	FlagReason     string      `json:"flag_reason"`
	PostContent    string      `json:"post_content,omitempty"`
	CommentContent string      `json:"comment_content,omitempty"`
	CanAppeal      bool        `json:"can_appeal"`
	AppealDeadline *time.Time  `json:"appeal_deadline,omitempty"`
	Appeal         *UserAppeal `json:"appeal,omitempty"`
}

type UserAppealRequest struct {
	UserViolationID uuid.UUID `json:"user_violation_id" binding:"required"`
	AppealReason    string    `json:"appeal_reason" binding:"required,min=10,max=1000"`
	AppealContext   string    `json:"appeal_context,omitempty" binding:"max=2000"`
	EvidenceURLs    []string  `json:"evidence_urls,omitempty"`
}

type UserAppealResponse struct {
	UserAppeal
	Violation UserViolation `json:"violation"`
}

type UserViolationSummary struct {
	TotalViolations  int                     `json:"total_violations"`
	HardViolations   int                     `json:"hard_violations"`
	SoftViolations   int                     `json:"soft_violations"`
	ActiveAppeals    int                     `json:"active_appeals"`
	CurrentStatus    string                  `json:"current_status"`
	BanExpiry        *time.Time              `json:"ban_expiry,omitempty"`
	RecentViolations []UserViolationResponse `json:"recent_violations"`
}
