// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type UserStatus string

const (
	UserStatusPending         UserStatus = "pending"
	UserStatusActive          UserStatus = "active"
	UserStatusDeactivated     UserStatus = "deactivated"
	UserStatusPendingDeletion UserStatus = "pending_deletion"
	UserStatusBanned          UserStatus = "banned"
	UserStatusSuspended       UserStatus = "suspended"
)

type User struct {
	ID              uuid.UUID  `json:"id" db:"id"`
	Email           string     `json:"email" db:"email"`
	PasswordHash    string     `json:"-" db:"encrypted_password"`
	Status          UserStatus `json:"status" db:"status"`
	MFAEnabled      bool       `json:"mfa_enabled" db:"mfa_enabled"`
	LastLogin       *time.Time `json:"last_login" db:"last_login"`
	EmailNewsletter bool       `json:"email_newsletter" db:"email_newsletter"`
	EmailContact    bool       `json:"email_contact" db:"email_contact"`
	CreatedAt       time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at" db:"updated_at"`
	DeletedAt       *time.Time `json:"deleted_at,omitempty" db:"deleted_at"`
}

type Profile struct {
	ID                     uuid.UUID `json:"id" db:"id"`
	Handle                 *string   `json:"handle" db:"handle"`
	DisplayName            *string   `json:"display_name" db:"display_name"`
	Bio                    *string   `json:"bio" db:"bio"`
	AvatarURL              *string   `json:"avatar_url" db:"avatar_url"`
	CoverURL               *string   `json:"cover_url" db:"cover_url"`
	IsOfficial             *bool     `json:"is_official" db:"is_official"`
	IsPrivate              *bool     `json:"is_private" db:"is_private"`
	IsVerified             *bool     `json:"is_verified" db:"is_verified"`
	BeaconEnabled          bool      `json:"beacon_enabled" db:"beacon_enabled"`
	Location               *string   `json:"location" db:"location"`
	Website                *string   `json:"website" db:"website"`
	Interests              []string  `json:"interests" db:"interests"`
	OriginCountry          *string   `json:"origin_country" db:"origin_country"`
	Strikes                int       `json:"strikes" db:"strikes"`
	IdentityKey            *string   `json:"identity_key" db:"identity_key"`
	RegistrationID         *int      `json:"registration_id" db:"registration_id"`
	EncryptedPrivateKey    *string   `json:"encrypted_private_key" db:"encrypted_private_key"`
	HasCompletedOnboarding bool      `json:"has_completed_onboarding" db:"has_completed_onboarding"`
	Role                   string    `json:"role" db:"role"`
	BirthMonth             int        `json:"birth_month" db:"birth_month"`
	BirthYear              int        `json:"birth_year" db:"birth_year"`
	// AIM-style ephemeral presence line — max 80 chars.
	StatusText             *string    `json:"status_text,omitempty" db:"status_text"`
	StatusUpdatedAt        *time.Time      `json:"status_updated_at,omitempty" db:"status_updated_at"`
	// Mastodon-style key-value metadata fields (max 8).
	// JSON array: [{"key":"Pronouns","value":"they/them","verified":false}, ...]
	MetadataFields         json.RawMessage `json:"metadata_fields" db:"metadata_fields"`
	CreatedAt              time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt              time.Time  `json:"updated_at" db:"updated_at"`

	// Computed fields (not stored in DB)
	FollowerCount  *int `json:"follower_count,omitempty" db:"-"`
	FollowingCount *int `json:"following_count,omitempty" db:"-"`
}

type Follow struct {
	FollowerID  uuid.UUID `json:"follower_id" db:"follower_id"`
	FollowingID uuid.UUID `json:"following_id" db:"following_id"`
	Status      string    `json:"status" db:"status"` // pending, accepted
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}

type TrustState struct {
	UserID            uuid.UUID  `json:"user_id" db:"user_id"`
	HarmonyScore      int        `json:"harmony_score" db:"harmony_score"`
	Tier              string     `json:"tier" db:"tier"` // new, trusted, established
	PostsToday        int        `json:"posts_today" db:"posts_today"`
	LastPostAt        *time.Time `json:"last_post_at" db:"last_post_at"`
	LastHarmonyCalcAt *time.Time `json:"last_harmony_calc_at" db:"last_harmony_calc_at"`
	UpdatedAt         time.Time  `json:"updated_at" db:"updated_at"`
}

type AuthToken struct {
	Token     string    `json:"token" db:"token"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	Type      string    `json:"type" db:"type"`
	ExpiresAt time.Time `json:"expires_at" db:"expires_at"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type MFASecret struct {
	UserID        uuid.UUID `json:"user_id" db:"user_id"`
	Secret        string    `json:"-" db:"secret"`
	RecoveryCodes []string  `json:"-" db:"recovery_codes"`
	CreatedAt     time.Time `json:"created_at" db:"created_at"`
	UpdatedAt     time.Time `json:"updated_at" db:"updated_at"`
}

type WebAuthnCredential struct {
	ID              []byte     `json:"id" db:"id"`
	UserID          uuid.UUID  `json:"user_id" db:"user_id"`
	PublicKey       []byte     `json:"public_key" db:"public_key"`
	AttestationType string     `json:"attestation_type" db:"attestation_type"`
	AAGUID          *uuid.UUID `json:"aaguid,omitempty" db:"aaguid"`
	SignCount       uint32     `json:"sign_count" db:"sign_count"`
	CreatedAt       time.Time  `json:"created_at" db:"created_at"`
	LastUsedAt      time.Time  `json:"last_used_at" db:"last_used_at"`
}

type OneTimePrekey struct {
	KeyID     int    `json:"key_id" db:"key_id"`
	PublicKey string `json:"public_key" db:"public_key"`
}
