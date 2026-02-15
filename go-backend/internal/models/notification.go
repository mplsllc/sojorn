package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// NotificationType constants for type safety
const (
	NotificationTypeLike           = "like"
	NotificationTypeComment        = "comment"
	NotificationTypeReply          = "reply"
	NotificationTypeMention        = "mention"
	NotificationTypeFollow         = "follow"
	NotificationTypeFollowRequest  = "follow_request"
	NotificationTypeFollowAccept   = "follow_accepted"
	NotificationTypeMessage        = "message"
	NotificationTypeSave           = "save"
	NotificationTypeBeaconVouch    = "beacon_vouch"
	NotificationTypeBeaconReport   = "beacon_report"
	NotificationTypeShare          = "share"
	NotificationTypeQuipReaction   = "quip_reaction"
	NotificationTypeNSFWWarning    = "nsfw_warning"
	NotificationTypeContentRemoved = "content_removed"
)

// NotificationPriority constants
const (
	PriorityLow    = "low"
	PriorityNormal = "normal"
	PriorityHigh   = "high"
	PriorityUrgent = "urgent"
)

type Notification struct {
	ID         uuid.UUID       `json:"id" db:"id"`
	UserID     uuid.UUID       `json:"user_id" db:"user_id"`
	Type       string          `json:"type" db:"type"`
	ActorID    uuid.UUID       `json:"actor_id" db:"actor_id"`
	PostID     *uuid.UUID      `json:"post_id,omitempty" db:"post_id"`
	CommentID  *uuid.UUID      `json:"comment_id,omitempty" db:"comment_id"`
	IsRead     bool            `json:"is_read" db:"is_read"`
	CreatedAt  time.Time       `json:"created_at" db:"created_at"`
	ArchivedAt *time.Time      `json:"archived_at,omitempty" db:"archived_at"`
	Metadata   json.RawMessage `json:"metadata" db:"metadata"`
	GroupKey   *string         `json:"group_key,omitempty" db:"group_key"`
	Priority   string          `json:"priority" db:"priority"`

	// Joined fields for display
	ActorHandle      string  `json:"actor_handle" db:"actor_handle"`
	ActorDisplayName string  `json:"actor_display_name" db:"actor_display_name"`
	ActorAvatarURL   string  `json:"actor_avatar_url" db:"actor_avatar_url"`
	PostImageURL     *string `json:"post_image_url,omitempty" db:"post_image_url"`
	PostBody         *string `json:"post_body,omitempty" db:"post_body"`

	// For grouped notifications
	GroupCount int `json:"group_count,omitempty" db:"group_count"`
}

type UserFCMToken struct {
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	FCMToken  string    `json:"fcm_token" db:"fcm_token"`
	Platform  string    `json:"platform" db:"platform"` // android, ios, web
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

type NotificationPreferences struct {
	UserID uuid.UUID `json:"user_id" db:"user_id"`

	// Push toggles
	PushEnabled        bool `json:"push_enabled" db:"push_enabled"`
	PushLikes          bool `json:"push_likes" db:"push_likes"`
	PushComments       bool `json:"push_comments" db:"push_comments"`
	PushReplies        bool `json:"push_replies" db:"push_replies"`
	PushMentions       bool `json:"push_mentions" db:"push_mentions"`
	PushFollows        bool `json:"push_follows" db:"push_follows"`
	PushFollowRequests bool `json:"push_follow_requests" db:"push_follow_requests"`
	PushMessages       bool `json:"push_messages" db:"push_messages"`
	PushSaves          bool `json:"push_saves" db:"push_saves"`
	PushBeacons        bool `json:"push_beacons" db:"push_beacons"`

	// Email toggles
	EmailEnabled         bool   `json:"email_enabled" db:"email_enabled"`
	EmailDigestFrequency string `json:"email_digest_frequency" db:"email_digest_frequency"`

	// Quiet hours
	QuietHoursEnabled bool    `json:"quiet_hours_enabled" db:"quiet_hours_enabled"`
	QuietHoursStart   *string `json:"quiet_hours_start,omitempty" db:"quiet_hours_start"` // "22:00:00"
	QuietHoursEnd     *string `json:"quiet_hours_end,omitempty" db:"quiet_hours_end"`     // "08:00:00"

	// Badge
	ShowBadgeCount bool `json:"show_badge_count" db:"show_badge_count"`

	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

// NotificationPayload is the structure sent to FCM
type NotificationPayload struct {
	Title    string            `json:"title"`
	Body     string            `json:"body"`
	ImageURL string            `json:"image_url,omitempty"`
	Data     map[string]string `json:"data"`
	Priority string            `json:"priority"`
	Badge    int               `json:"badge,omitempty"`
}

// PushNotificationRequest for internal use
type PushNotificationRequest struct {
	UserID       uuid.UUID
	Type         string
	ActorID      uuid.UUID
	ActorName    string
	ActorAvatar  string
	ActorHandle  string
	PostID       *uuid.UUID
	CommentID    *uuid.UUID
	PostType     string // "standard", "quip", "beacon"
	PostPreview  string // First ~50 chars of post body
	PostImageURL string
	GroupKey     string
	Priority     string
	Metadata     map[string]interface{}
}

// UnreadBadge for badge count responses
type UnreadBadge struct {
	NotificationCount int `json:"notification_count"`
	MessageCount      int `json:"message_count"`
	TotalCount        int `json:"total_count"`
}
