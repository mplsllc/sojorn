package models

import (
	"time"

	"github.com/google/uuid"
)

type Report struct {
	ID            uuid.UUID  `json:"id"`
	ReporterID    uuid.UUID  `json:"reporter_id"`
	TargetUserID  uuid.UUID  `json:"target_user_id"`
	PostID        *uuid.UUID `json:"post_id,omitempty"`
	CommentID     *uuid.UUID `json:"comment_id,omitempty"`
	ViolationType string     `json:"violation_type"`
	Description   string     `json:"description"`
	Status        string     `json:"status"`
	CreatedAt     time.Time  `json:"created_at"`
}

type AbuseLog struct {
	ID            uuid.UUID  `json:"id"`
	ActorID       *uuid.UUID `json:"actor_id,omitempty"`
	BlockedID     uuid.UUID  `json:"blocked_id"`
	BlockedHandle string     `json:"blocked_handle"`
	ActorIP       string     `json:"actor_ip"`
	CreatedAt     time.Time  `json:"created_at"`
}

type ModerationFlag struct {
	ID         uuid.UUID          `json:"id"`
	PostID     *uuid.UUID         `json:"post_id,omitempty"`
	CommentID  *uuid.UUID         `json:"comment_id,omitempty"`
	FlagReason string             `json:"flag_reason"`
	Scores     map[string]float64 `json:"scores"`
	Status     string             `json:"status"`
	ReviewedBy *uuid.UUID         `json:"reviewed_by,omitempty"`
	ReviewedAt *time.Time         `json:"reviewed_at,omitempty"`
	CreatedAt  time.Time          `json:"created_at"`
	UpdatedAt  time.Time          `json:"updated_at"`
}

type UserStatusHistory struct {
	ID        uuid.UUID `json:"id"`
	UserID    uuid.UUID `json:"user_id"`
	OldStatus *string   `json:"old_status,omitempty"`
	NewStatus string    `json:"new_status"`
	Reason    string    `json:"reason"`
	ChangedBy uuid.UUID `json:"changed_by"`
	CreatedAt time.Time `json:"created_at"`
}

// ModerationQueueItem represents a simplified view for Directus moderation interface
type ModerationQueueItem struct {
	ID             uuid.UUID          `json:"id"`
	PostID         *uuid.UUID         `json:"post_id,omitempty"`
	CommentID      *uuid.UUID         `json:"comment_id,omitempty"`
	FlagReason     string             `json:"flag_reason"`
	Scores         map[string]float64 `json:"scores"`
	Status         string             `json:"status"`
	CreatedAt      time.Time          `json:"created_at"`
	PostContent    *string            `json:"post_content,omitempty"`
	CommentContent *string            `json:"comment_content,omitempty"`
	AuthorHandle   *string            `json:"author_handle,omitempty"`
}

// UserModeration represents user status for management
type UserModeration struct {
	ID        uuid.UUID `json:"id"`
	Handle    string    `json:"handle"`
	Email     string    `json:"email"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}
