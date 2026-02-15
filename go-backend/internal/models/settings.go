package models

import (
	"time"

	"github.com/google/uuid"
)

type PrivacySettings struct {
	UserID                uuid.UUID `json:"user_id" db:"user_id"`
	ShowLocation          *bool     `json:"show_location" db:"show_location"`
	ShowInterests         *bool     `json:"show_interests" db:"show_interests"`
	ProfileVisibility     *string   `json:"profile_visibility" db:"profile_visibility"`
	PostsVisibility       *string   `json:"posts_visibility" db:"posts_visibility"`
	SavedVisibility       *string   `json:"saved_visibility" db:"saved_visibility"`
	FollowRequestPolicy   *string   `json:"follow_request_policy" db:"follow_request_policy"`
	DefaultPostVisibility *string   `json:"default_post_visibility" db:"default_post_visibility"`
	IsPrivateProfile      *bool     `json:"is_private_profile" db:"is_private_profile"`
	UpdatedAt             time.Time `json:"updated_at" db:"updated_at"`
}

type UserSettings struct {
	UserID               uuid.UUID `json:"user_id" db:"user_id"`
	Theme                *string   `json:"theme" db:"theme"`
	Language             *string   `json:"language" db:"language"`
	NotificationsEnabled *bool     `json:"notifications_enabled" db:"notifications_enabled"`
	EmailNotifications   *bool     `json:"email_notifications" db:"email_notifications"`
	PushNotifications    *bool     `json:"push_notifications" db:"push_notifications"`
	ContentFilterLevel   *string   `json:"content_filter_level" db:"content_filter_level"`
	AutoPlayVideos       *bool     `json:"auto_play_videos" db:"auto_play_videos"`
	DataSaverMode        *bool     `json:"data_saver_mode" db:"data_saver_mode"`
	DefaultPostTtl       *int      `json:"default_post_ttl" db:"default_post_ttl"`
	NSFWEnabled          *bool     `json:"nsfw_enabled" db:"nsfw_enabled"`
	NSFWBlurEnabled      *bool     `json:"nsfw_blur_enabled" db:"nsfw_blur_enabled"`
	UpdatedAt            time.Time `json:"updated_at" db:"updated_at"`
}
