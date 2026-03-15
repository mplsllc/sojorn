// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package models

import (
	"time"

	"github.com/google/uuid"
)

// Hashtag represents a hashtag in the system
type Hashtag struct {
	ID            uuid.UUID `json:"id" db:"id"`
	Name          string    `json:"name" db:"name"`                 // lowercase, without #
	DisplayName   string    `json:"display_name" db:"display_name"` // original casing
	UseCount      int       `json:"use_count" db:"use_count"`
	TrendingScore float64   `json:"trending_score" db:"trending_score"`
	IsTrending    bool      `json:"is_trending" db:"is_trending"`
	IsFeatured    bool      `json:"is_featured" db:"is_featured"`
	Category      *string   `json:"category,omitempty" db:"category"`
	CreatedAt     time.Time `json:"created_at" db:"created_at"`

	// Computed fields
	RecentCount int  `json:"recent_count,omitempty" db:"-"`
	IsFollowing bool `json:"is_following,omitempty" db:"-"`
}

// NOTE: TagResult is defined in post.go

// PostMention represents an @mention in a post
type PostMention struct {
	ID              uuid.UUID `json:"id" db:"id"`
	PostID          uuid.UUID `json:"post_id" db:"post_id"`
	MentionedUserID uuid.UUID `json:"mentioned_user_id" db:"mentioned_user_id"`
	CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

// HashtagFollow represents a user following a hashtag
type HashtagFollow struct {
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	HashtagID uuid.UUID `json:"hashtag_id" db:"hashtag_id"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

// SuggestedUser for discover page
type SuggestedUser struct {
	ID            uuid.UUID `json:"id"`
	Handle        string    `json:"handle"`
	DisplayName   *string   `json:"display_name,omitempty"`
	AvatarURL     *string   `json:"avatar_url,omitempty"`
	Bio           *string   `json:"bio,omitempty"`
	IsVerified    bool      `json:"is_verified"`
	IsOfficial    bool      `json:"is_official"`
	Reason        string    `json:"reason"` // e.g., "popular", "similar", "category"
	Category      *string   `json:"category,omitempty"`
	Score         float64   `json:"score"`
	FollowerCount int       `json:"follower_count"`
}

// TrendingHashtag for trending display
type TrendingHashtag struct {
	Hashtag
	Rank              int `json:"rank" db:"rank"`
	PostCountInPeriod int `json:"post_count_in_period" db:"post_count_in_period"`
}

// DiscoverSection represents a section in the discover page
type DiscoverSection struct {
	Title     string      `json:"title"`
	Type      string      `json:"type"` // "hashtags", "users", "posts", "categories"
	Items     interface{} `json:"items"`
	ViewAllID string      `json:"view_all_id,omitempty"` // ID or slug for "View All" link
}

// DiscoverResponse is the full discover page response
type DiscoverResponse struct {
	TrendingHashtags []Hashtag       `json:"trending_hashtags"`
	FeaturedHashtags []Hashtag       `json:"featured_hashtags,omitempty"`
	SuggestedUsers   []SuggestedUser `json:"suggested_users"`
	PopularCreators  []Profile       `json:"popular_creators,omitempty"`
	TrendingPosts    []Post          `json:"trending_posts,omitempty"`
	FollowedHashtags []Hashtag       `json:"followed_hashtags,omitempty"`
	Categories       []Category      `json:"categories,omitempty"`
}

// HashtagPageResponse for viewing a specific hashtag
type HashtagPageResponse struct {
	Hashtag     Hashtag `json:"hashtag"`
	Posts       []Post  `json:"posts"`
	IsFollowing bool    `json:"is_following"`
	TotalPosts  int     `json:"total_posts"`
}
