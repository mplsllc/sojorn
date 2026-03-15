// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package repository

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type MFASecret struct {
	UserID        uuid.UUID
	Secret        string
	RecoveryCodes []string
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

type MFARepository struct {
	pool *pgxpool.Pool
}

func NewMFARepository(pool *pgxpool.Pool) *MFARepository {
	return &MFARepository{pool: pool}
}

func (r *MFARepository) SaveSecret(ctx context.Context, userID uuid.UUID, secret string, hashedCodes []string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO mfa_secrets (user_id, secret, recovery_codes)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE
		SET secret = $2, recovery_codes = $3, updated_at = NOW()
	`, userID, secret, hashedCodes)
	return err
}

func (r *MFARepository) GetSecret(ctx context.Context, userID uuid.UUID) (*MFASecret, error) {
	var s MFASecret
	err := r.pool.QueryRow(ctx, `
		SELECT user_id, secret, recovery_codes, created_at, updated_at
		FROM mfa_secrets WHERE user_id = $1
	`, userID).Scan(&s.UserID, &s.Secret, &s.RecoveryCodes, &s.CreatedAt, &s.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *MFARepository) DeleteSecret(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM mfa_secrets WHERE user_id = $1`, userID)
	return err
}

func (r *MFARepository) SetMFAEnabled(ctx context.Context, userID uuid.UUID, enabled bool) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET mfa_enabled = $2 WHERE id = $1`, userID, enabled)
	return err
}

// UpdateRecoveryCodes replaces the recovery codes for a user (e.g. after one is used).
func (r *MFARepository) UpdateRecoveryCodes(ctx context.Context, userID uuid.UUID, codes []string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE mfa_secrets SET recovery_codes = $2, updated_at = NOW() WHERE user_id = $1
	`, userID, codes)
	return err
}
