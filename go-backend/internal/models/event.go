// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package models

import (
	"time"

	"github.com/google/uuid"
)

// RSVPStatus represents a user's attendance intent for an event.
type RSVPStatus string

const (
	RSVPGoing       RSVPStatus = "going"
	RSVPInterested  RSVPStatus = "interested"
	RSVPNotGoing    RSVPStatus = "not_going"
)

// EventCategory maps to the category values in the events table.
type EventCategory string

const (
	EventCategoryGeneral     EventCategory = "general"
	EventCategorySocial      EventCategory = "social"
	EventCategorySports      EventCategory = "sports"
	EventCategoryEducation   EventCategory = "education"
	EventCategoryArts        EventCategory = "arts"
	EventCategoryFundraiser  EventCategory = "fundraiser"
	EventCategoryGovernment  EventCategory = "government"
	EventCategoryReligious   EventCategory = "religious"
	EventCategoryCommunity   EventCategory = "community"
	EventCategoryMarketplace EventCategory = "marketplace"
)

// Event represents a community event. Schema is inspired (clean-room) by
// Hi.Events open-source event management platform (AGPL-3.0).
type Event struct {
	ID             uuid.UUID      `json:"id"              db:"id"`
	OrganizerID    uuid.UUID      `json:"organizer_id"    db:"organizer_id"`
	GroupID        *uuid.UUID     `json:"group_id"        db:"group_id"`
	Title          string         `json:"title"           db:"title"`
	Description    *string        `json:"description"     db:"description"`
	StartTime      time.Time      `json:"start_time"      db:"start_time"`
	EndTime        *time.Time     `json:"end_time"        db:"end_time"`
	LocationName   *string        `json:"location_name"   db:"location_name"`
	LocationLat    *float64       `json:"location_lat"    db:"location_lat"`
	LocationLong   *float64       `json:"location_long"   db:"location_long"`
	CoverImageURL  *string        `json:"cover_image_url" db:"cover_image_url"`
	Category       EventCategory  `json:"category"        db:"category"`
	Status         string         `json:"status"          db:"status"`
	Capacity       *int           `json:"capacity"        db:"capacity"`
	RSVPCount      int            `json:"rsvp_count"      db:"rsvp_count"`
	IsOnline       bool           `json:"is_online"       db:"is_online"`
	OnlineURL      *string        `json:"online_url"      db:"online_url"`
	CreatedAt      time.Time      `json:"created_at"      db:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"      db:"updated_at"`

	// Joined fields
	OrganizerHandle      string `json:"organizer_handle"       db:"organizer_handle"`
	OrganizerDisplayName string `json:"organizer_display_name" db:"organizer_display_name"`
	OrganizerAvatarURL   string `json:"organizer_avatar_url"   db:"organizer_avatar_url"`

	// Viewer-specific fields
	MyRSVP *string `json:"my_rsvp,omitempty" db:"my_rsvp"`
}

// EventRSVP records a user's attendance intent.
type EventRSVP struct {
	ID        uuid.UUID  `json:"id"         db:"id"`
	EventID   uuid.UUID  `json:"event_id"   db:"event_id"`
	UserID    uuid.UUID  `json:"user_id"    db:"user_id"`
	Status    RSVPStatus `json:"status"     db:"status"`
	CreatedAt time.Time  `json:"created_at" db:"created_at"`
}
