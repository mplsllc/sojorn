// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package models

import (
	"time"

	"github.com/google/uuid"
)

type RefreshToken struct {
	TokenHash string    `json:"-" db:"token_hash"`
	UserID    uuid.UUID `json:"user_id" db:"user_id"`
	ExpiresAt time.Time `json:"expires_at" db:"expires_at"`
	Revoked   bool      `json:"revoked" db:"revoked"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}
