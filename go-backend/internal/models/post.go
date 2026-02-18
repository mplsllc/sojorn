package models

import (
	"time"

	"github.com/google/uuid"
)

type Post struct {
	ID             uuid.UUID  `json:"id" db:"id"`
	AuthorID       uuid.UUID  `json:"author_id" db:"author_id"`
	CategoryID     *uuid.UUID `json:"category_id" db:"category_id"`
	Body           string     `json:"body" db:"body"`
	Status         string     `json:"status" db:"status"` // active, flagged, removed
	ToneLabel      *string    `json:"tone_label" db:"tone_label"`
	CISScore       *float64   `json:"cis_score" db:"cis_score"`
	ImageURL       *string    `json:"image_url" db:"image_url"`
	VideoURL       *string    `json:"video_url" db:"video_url"`
	ThumbnailURL   *string    `json:"thumbnail_url" db:"thumbnail_url"`
	DurationMS     int        `json:"duration_ms" db:"duration_ms"`
	BodyFormat     string     `json:"body_format" db:"body_format"` // plain, markdown
	BackgroundID   *string    `json:"background_id" db:"background_id"`
	Tags           []string   `json:"tags" db:"tags"`
	IsBeacon       bool       `json:"is_beacon" db:"is_beacon"`
	BeaconType     *string    `json:"beacon_type" db:"beacon_type"`
	Location       any        `json:"location,omitempty" db:"location"` // geography(POINT)
	Lat            *float64   `json:"lat,omitempty"`
	Long           *float64   `json:"long,omitempty"`
	Confidence     float64    `json:"confidence_score" db:"confidence_score"`
	IsActiveBeacon bool       `json:"is_active_beacon" db:"is_active_beacon"`
	Severity       string     `json:"severity" db:"severity"`
	IncidentStatus string     `json:"incident_status" db:"incident_status"`
	Radius         int        `json:"radius" db:"radius"`
	GroupID        *uuid.UUID `json:"group_id,omitempty" db:"group_id"`
	AllowChain     bool       `json:"allow_chain" db:"allow_chain"`
	ChainParentID  *uuid.UUID `json:"chain_parent_id" db:"chain_parent_id"`
	Visibility     string     `json:"visibility" db:"visibility"`
	IsNSFW         bool       `json:"is_nsfw" db:"is_nsfw"`
	NSFWReason     string     `json:"nsfw_reason" db:"nsfw_reason"`
	ExpiresAt      *time.Time `json:"expires_at" db:"expires_at"`

	// Quip overlay JSON — stores text/sticker decorations as client-rendered widgets
	OverlayJSON *string `json:"overlay_json,omitempty" db:"overlay_json"`

	// Link preview (populated via enrichment, not in every query)
	LinkPreviewURL         *string    `json:"link_preview_url,omitempty" db:"link_preview_url"`
	LinkPreviewTitle       *string    `json:"link_preview_title,omitempty" db:"link_preview_title"`
	LinkPreviewDescription *string    `json:"link_preview_description,omitempty" db:"link_preview_description"`
	LinkPreviewImageURL    *string    `json:"link_preview_image_url,omitempty" db:"link_preview_image_url"`
	LinkPreviewSiteName    *string    `json:"link_preview_site_name,omitempty" db:"link_preview_site_name"`
	CreatedAt              time.Time  `json:"created_at" db:"created_at"`
	EditedAt               *time.Time `json:"edited_at,omitempty" db:"edited_at"`
	DeletedAt              *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`

	// Joined fields (Scan targets)
	AuthorHandle      string `json:"-" db:"author_handle"`
	AuthorDisplayName string `json:"-" db:"author_display_name"`
	AuthorAvatarURL   string `json:"-" db:"author_avatar_url"`
	LikeCount         int    `json:"like_count" db:"like_count"`
	CommentCount      int    `json:"comment_count" db:"comment_count"`
	IsLiked           bool   `json:"is_liked" db:"is_liked"`

	// Nested objects for JSON API
	Author      *AuthorProfile `json:"author,omitempty"`
	IsSponsored bool           `json:"is_sponsored,omitempty"`

	// Reaction data
	Reactions     map[string]int      `json:"reactions"`
	MyReactions   []string            `json:"my_reactions"`
	ReactionUsers map[string][]string `json:"reaction_users"`
}

type AuthorProfile struct {
	ID          uuid.UUID `json:"id"`
	Handle      string    `json:"handle"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
}

type PostMetrics struct {
	PostID       uuid.UUID `json:"post_id" db:"post_id"`
	LikeCount    int       `json:"like_count" db:"like_count"`
	SaveCount    int       `json:"save_count" db:"save_count"`
	ViewCount    int       `json:"view_count" db:"view_count"`
	CommentCount int       `json:"comment_count" db:"comment_count"`
	UpdatedAt    time.Time `json:"updated_at" db:"updated_at"`
}

type Category struct {
	ID          uuid.UUID `json:"id" db:"id"`
	Slug        string    `json:"slug" db:"slug"`
	Name        string    `json:"name" db:"name"`
	Description *string   `json:"description" db:"description"`
	IsSensitive bool      `json:"is_sensitive" db:"is_sensitive"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}

type Comment struct {
	ID        uuid.UUID  `json:"id" db:"id"`
	PostID    string     `json:"post_id" db:"post_id"`
	AuthorID  uuid.UUID  `json:"author_id" db:"author_id"`
	Body      string     `json:"body" db:"body"`
	Status    string     `json:"status" db:"status"`
	CreatedAt time.Time  `json:"created_at" db:"created_at"`
	DeletedAt *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`
}

type TagResult struct {
	Tag   string `json:"tag"`
	Count int    `json:"count"`
}

// FocusContext represents the minimal data needed for the Focus-Context view
type FocusContext struct {
	TargetPost     *Post  `json:"target_post"`
	ParentPost     *Post  `json:"parent_post,omitempty"`
	Children       []Post `json:"children"`
	ParentChildren []Post `json:"parent_children,omitempty"`
}
