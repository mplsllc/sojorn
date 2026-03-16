// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package repository

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

func (r *UserRepository) Pool() *pgxpool.Pool {
	return r.pool
}

func (r *UserRepository) CreateProfile(ctx context.Context, profile *models.Profile) error {
	query := `
		INSERT INTO public.profiles (id, handle, display_name, bio, origin_country, birth_month, birth_year)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`
	_, err := r.pool.Exec(ctx, query, profile.ID, profile.Handle, profile.DisplayName, profile.Bio, profile.OriginCountry, profile.BirthMonth, profile.BirthYear)
	if err != nil {
		return fmt.Errorf("failed to create profile: %w", err)
	}

	// Initialize trust state (mimicking the trigger if we want to do it in Go)
	trustQuery := `
		INSERT INTO public.trust_state (user_id, harmony_score, tier)
		VALUES ($1, 50, 'new')
	`
	_, err = r.pool.Exec(ctx, trustQuery, profile.ID)
	if err != nil {
		return fmt.Errorf("failed to initialize trust state: %w", err)
	}

	return nil
}

func (r *UserRepository) GetProfileByID(ctx context.Context, id string) (*models.Profile, error) {
	query := `SELECT id, handle, display_name, bio, avatar_url, cover_url,
		origin_country, location, website, interests,
		has_completed_onboarding, is_official, is_private, role, created_at,
		COALESCE(birth_month, 0), COALESCE(birth_year, 0),
		status_text, status_updated_at,
		COALESCE(metadata_fields, '[]'::jsonb)
		FROM public.profiles WHERE id = $1::uuid`

	var p models.Profile
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&p.ID, &p.Handle, &p.DisplayName, &p.Bio, &p.AvatarURL, &p.CoverURL,
		&p.OriginCountry, &p.Location, &p.Website, &p.Interests,
		&p.HasCompletedOnboarding, &p.IsOfficial, &p.IsPrivate, &p.Role, &p.CreatedAt,
		&p.BirthMonth, &p.BirthYear,
		&p.StatusText, &p.StatusUpdatedAt,
		&p.MetadataFields,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *UserRepository) GetProfileByHandle(ctx context.Context, handle string) (*models.Profile, error) {
	query := `
		SELECT id, handle, display_name, bio, avatar_url, cover_url,
		       origin_country, location, website, interests,
		       has_completed_onboarding, is_official, is_private, role, created_at,
		       COALESCE(birth_month, 0), COALESCE(birth_year, 0),
		       status_text, status_updated_at,
		       COALESCE(metadata_fields, '[]'::jsonb)
		FROM public.profiles
		WHERE handle = $1
	`
	var p models.Profile
	err := r.pool.QueryRow(ctx, query, handle).Scan(
		&p.ID, &p.Handle, &p.DisplayName, &p.Bio, &p.AvatarURL, &p.CoverURL,
		&p.OriginCountry, &p.Location, &p.Website, &p.Interests,
		&p.HasCompletedOnboarding, &p.IsOfficial, &p.IsPrivate, &p.Role, &p.CreatedAt,
		&p.BirthMonth, &p.BirthYear,
		&p.StatusText, &p.StatusUpdatedAt,
		&p.MetadataFields,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *UserRepository) UpdateProfile(ctx context.Context, profile *models.Profile) error {
	query := `
		UPDATE public.profiles SET
			handle = COALESCE($1, handle),
			display_name = COALESCE($2, display_name),
			bio = COALESCE($3, bio),
			avatar_url = COALESCE($4, avatar_url),
			cover_url = COALESCE($5, cover_url),
			location = COALESCE($6, location),
			website = COALESCE($7, website),
			interests = COALESCE($8, interests),
			identity_key = COALESCE($9, identity_key),
			registration_id = COALESCE($10, registration_id),
			encrypted_private_key = COALESCE($11, encrypted_private_key),
			is_private = COALESCE($12, is_private),
			is_official = COALESCE($13, is_official),
			status_text = CASE WHEN $15::boolean THEN $14 ELSE status_text END,
			status_updated_at = CASE WHEN $15::boolean THEN NOW() ELSE status_updated_at END,
			metadata_fields = COALESCE($17, metadata_fields),
			updated_at = NOW()
		WHERE id = $16::uuid
	`
	// $15 is a sentinel: true means status_text was explicitly provided (even if empty string).
	statusProvided := profile.StatusText != nil
	_, err := r.pool.Exec(ctx, query,
		profile.Handle, profile.DisplayName, profile.Bio, profile.AvatarURL,
		profile.CoverURL, profile.Location, profile.Website, profile.Interests,
		profile.IdentityKey, profile.RegistrationID, profile.EncryptedPrivateKey,
		profile.IsPrivate, profile.IsOfficial,
		profile.StatusText, statusProvided,
		profile.ID,
		profile.MetadataFields,
	)
	return err
}

func (r *UserRepository) MarkOnboardingComplete(ctx context.Context, userID string) error {
	query := `UPDATE public.profiles SET has_completed_onboarding = TRUE, updated_at = NOW() WHERE id = $1::uuid`
	_, err := r.pool.Exec(ctx, query, userID)
	return err
}

func (r *UserRepository) SearchUsers(ctx context.Context, query string, viewerID string, limit int) ([]models.Profile, error) {
	// The % operator uses pg_trgm for fuzzy matching
	sql := `
		SELECT
			p.id, p.handle, p.display_name, p.bio, p.avatar_url, p.origin_country, p.has_completed_onboarding, p.created_at
		FROM public.profiles p
		LEFT JOIN public.trust_state t ON p.id = t.user_id
		LEFT JOIN public.profile_privacy_settings pps ON p.id = pps.user_id
		WHERE (
			p.handle % $1 OR p.handle ILIKE '%' || $1 || '%'
			OR p.display_name % $1 OR p.display_name ILIKE '%' || $1 || '%'
		)
		  AND (
			  p.is_private = FALSE
			  OR ($2 != '' AND EXISTS (
				  SELECT 1 FROM public.follows f
				  WHERE f.follower_id = $2::uuid AND f.following_id = p.id AND f.status = 'accepted'
			  ))
			  OR ($2 != '' AND p.id = $2::uuid)
		  )
		  AND NOT public.has_block_between(p.id, CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END)
		  AND COALESCE(pps.searchable_by_handle, true) = true
		ORDER BY
			(similarity(p.handle, $1) + CASE WHEN p.handle ILIKE $1 || '%' THEN 0.5 ELSE 0 END + CASE WHEN COALESCE(t.harmony_score, 0) > 80 THEN 0.3 ELSE 0 END) DESC,
			p.created_at DESC
		LIMIT $3
	`
	rows, err := r.pool.Query(ctx, sql, query, viewerID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []models.Profile
	for rows.Next() {
		var p models.Profile
		err := rows.Scan(
			&p.ID, &p.Handle, &p.DisplayName, &p.Bio, &p.AvatarURL, &p.OriginCountry, &p.HasCompletedOnboarding, &p.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		profiles = append(profiles, p)
	}
	return profiles, nil
}

func (r *UserRepository) GetTrustState(ctx context.Context, userID string) (*models.TrustState, error) {
	query := `SELECT user_id, harmony_score, tier, posts_today FROM public.trust_state WHERE user_id = $1::uuid`

	var ts models.TrustState
	err := r.pool.QueryRow(ctx, query, userID).Scan(
		&ts.UserID, &ts.HarmonyScore, &ts.Tier, &ts.PostsToday,
	)
	if err != nil {
		return nil, err
	}
	return &ts, nil
}

func (r *UserRepository) CreateUser(ctx context.Context, user *models.User) error {
	query := `
		INSERT INTO public.users (id, email, encrypted_password, status, mfa_enabled, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`
	_, err := r.pool.Exec(ctx, query, user.ID, user.Email, user.PasswordHash, user.Status, user.MFAEnabled, user.CreatedAt, user.UpdatedAt)
	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}
	return nil
}

func (r *UserRepository) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	query := `SELECT id, email, encrypted_password, status, mfa_enabled, last_login, created_at FROM public.users WHERE email = $1`
	var u models.User
	err := r.pool.QueryRow(ctx, query, email).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Status, &u.MFAEnabled, &u.LastLogin, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *UserRepository) GetUserByID(ctx context.Context, id string) (*models.User, error) {
	query := `SELECT id, email, encrypted_password, status, mfa_enabled, last_login, created_at FROM public.users WHERE id = $1::uuid`
	var u models.User
	err := r.pool.QueryRow(ctx, query, id).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Status, &u.MFAEnabled, &u.LastLogin, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *UserRepository) FollowUser(ctx context.Context, followerID, followingID string) (string, error) {
	if followerID == followingID {
		return "", fmt.Errorf("cannot follow self")
	}

	// 1. Check if follow record already exists
	var currentStatus string
	err := r.pool.QueryRow(ctx,
		"SELECT status FROM public.follows WHERE follower_id = $1::uuid AND following_id = $2::uuid",
		followerID, followingID).Scan(&currentStatus)

	if err == nil {
		return currentStatus, nil // Return existing status if found
	}

	// 2. Check target user's privacy settings
	var isPrivate, isOfficial bool
	err = r.pool.QueryRow(ctx,
		"SELECT is_private, is_official FROM public.profiles WHERE id = $1::uuid",
		followingID).Scan(&isPrivate, &isOfficial)

	if err != nil {
		// Fallback: If profile missing, assume public (or return error)
		isPrivate = false
	}

	// 3. Determine status: Official/Public -> Accepted, Private -> Pending
	newStatus := "pending"
	if isOfficial || !isPrivate {
		newStatus = "accepted"
	}

	// 4. Insert the follow
	query := `
		INSERT INTO public.follows (follower_id, following_id, status)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (follower_id, following_id) DO UPDATE SET status = EXCLUDED.status
		RETURNING status
	`
	var status string
	err = r.pool.QueryRow(ctx, query, followerID, followingID, newStatus).Scan(&status)

	if err != nil {
		return "", fmt.Errorf("failed to follow user: %w", err)
	}

	return status, nil
}

func (r *UserRepository) AcceptFollowRequest(ctx context.Context, userID, requesterID string) error {
	query := `
		UPDATE public.follows 
		SET status = 'accepted' 
		WHERE following_id = $1::uuid AND follower_id = $2::uuid AND status = 'pending'
	`
	commandTag, err := r.pool.Exec(ctx, query, userID, requesterID)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() == 0 {
		return fmt.Errorf("no pending request found")
	}
	return nil
}

func (r *UserRepository) GetPendingFollowRequests(ctx context.Context, userID string) ([]map[string]any, error) {
	query := `
		SELECT p.id as follower_id, p.handle, p.display_name, p.avatar_url, f.created_at as requested_at
		FROM public.follows f
		JOIN public.profiles p ON p.id = f.follower_id
		WHERE f.following_id = $1::uuid AND f.status = 'pending'
		ORDER BY f.created_at DESC
	`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var requests []map[string]any
	for rows.Next() {
		var id, handle, displayName, avatarURL string
		var requestedAt time.Time
		if err := rows.Scan(&id, &handle, &displayName, &avatarURL, &requestedAt); err != nil {
			return nil, err
		}
		requests = append(requests, map[string]any{
			"follower_id":  id,
			"handle":       handle,
			"display_name": displayName,
			"avatar_url":   avatarURL,
			"requested_at": requestedAt,
		})
	}
	return requests, nil
}

func (r *UserRepository) UpdateHarmonyScore(ctx context.Context, userID string, delta int) error {
	query := `
		UPDATE public.trust_state 
		SET harmony_score = GREATEST(0, LEAST(harmony_score + $1, 100)),
		    updated_at = NOW(),
		    last_harmony_calc_at = NOW()
		WHERE user_id = $2::uuid
	`
	_, err := r.pool.Exec(ctx, query, delta, userID)
	return err
}

func (r *UserRepository) RejectFollowRequest(ctx context.Context, userID, requesterID string) error {
	query := `DELETE FROM public.follows WHERE follower_id = $1::uuid AND following_id = $2::uuid AND status = 'pending'`
	_, err := r.pool.Exec(ctx, query, requesterID, userID)
	return err
}

func (r *UserRepository) UnfollowUser(ctx context.Context, followerID, followingID string) error {
	query := `
		DELETE FROM public.follows WHERE follower_id = $1::uuid AND following_id = $2::uuid
	`
	_, err := r.pool.Exec(ctx, query, followerID, followingID)
	if err != nil {
		return fmt.Errorf("failed to unfollow user: %w", err)
	}
	return nil
}

func (r *UserRepository) BlockUser(ctx context.Context, blockerID, blockedID, actorIP string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Step 1: Insert Block
	query := `INSERT INTO public.blocks (blocker_id, blocked_id) VALUES ($1::uuid, $2::uuid) ON CONFLICT DO NOTHING`
	_, err = tx.Exec(ctx, query, blockerID, blockedID)
	if err != nil {
		return err
	}

	// Step 2: Log Abuse
	var handle string
	_ = tx.QueryRow(ctx, `SELECT handle FROM public.profiles WHERE id = $1::uuid`, blockedID).Scan(&handle)

	abuseQuery := `
		INSERT INTO public.abuse_logs (actor_id, blocked_id, blocked_handle, actor_ip)
		VALUES ($1::uuid, $2::uuid, $3, $4)
	`
	_, _ = tx.Exec(ctx, abuseQuery, blockerID, blockedID, handle, actorIP)

	return tx.Commit(ctx)
}

func (r *UserRepository) UnblockUser(ctx context.Context, blockerID, blockedID string) error {
	query := `DELETE FROM public.blocks WHERE blocker_id = $1::uuid AND blocked_id = $2::uuid`
	_, err := r.pool.Exec(ctx, query, blockerID, blockedID)
	return err
}

func (r *UserRepository) GetBlockedUsers(ctx context.Context, userID string) ([]models.Profile, error) {
	query := `
		SELECT p.id, p.handle, p.display_name, p.avatar_url
		FROM public.profiles p
		JOIN public.blocks b ON p.id = b.blocked_id
		WHERE b.blocker_id = $1::uuid
	`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []models.Profile
	for rows.Next() {
		var p models.Profile
		if err := rows.Scan(&p.ID, &p.Handle, &p.DisplayName, &p.AvatarURL); err != nil {
			return nil, err
		}
		profiles = append(profiles, p)
	}
	return profiles, nil
}

func (r *UserRepository) CreateReport(ctx context.Context, report *models.Report) error {
	query := `
		INSERT INTO public.reports (reporter_id, target_user_id, post_id, comment_id, group_id, neighborhood_id, violation_type, description, status)
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, 'pending')
	`
	_, err := r.pool.Exec(ctx, query,
		report.ReporterID,
		report.TargetUserID,
		report.PostID,
		report.CommentID,
		report.GroupID,
		report.NeighborhoodID,
		report.ViolationType,
		report.Description,
	)
	return err
}

type ProfileStats struct {
	PostCount      int `json:"post_count"`
	FollowerCount  int `json:"follower_count"`
	FollowingCount int `json:"following_count"`
}

func (r *UserRepository) GetProfileStats(ctx context.Context, userID string) (*ProfileStats, error) {
	stats := &ProfileStats{}

	query := `
		SELECT
			(
				SELECT COUNT(*) FROM public.posts p
				WHERE p.author_id = $1::uuid AND p.deleted_at IS NULL
			) as post_count,
			(
				SELECT COUNT(*) FROM public.follows 
				WHERE following_id = $1::uuid AND status = 'accepted'
			) as follower_count,
			(
				SELECT COUNT(*) FROM public.follows 
				WHERE follower_id = $1::uuid AND status = 'accepted'
			) as following_count
	`
	err := r.pool.QueryRow(ctx, query, userID).Scan(
		&stats.PostCount,
		&stats.FollowerCount,
		&stats.FollowingCount,
	)
	if err != nil {
		return nil, err
	}

	return stats, nil
}

func (r *UserRepository) IsFollowing(ctx context.Context, followerID, followingID string) (bool, error) {
	var exists bool
	query := `SELECT EXISTS(SELECT 1 FROM public.follows WHERE follower_id = $1::uuid AND following_id = $2::uuid AND status = 'accepted')`
	err := r.pool.QueryRow(ctx, query, followerID, followingID).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *UserRepository) IsMutualFollow(ctx context.Context, userA, userB string) (bool, error) {
	if userA == userB {
		return true, nil
	}

	var exists bool
	query := `
		SELECT EXISTS (
			SELECT 1 FROM public.follows 
			WHERE follower_id = $1::uuid AND following_id = $2::uuid AND status = 'accepted'
		) AND EXISTS (
			SELECT 1 FROM public.follows 
			WHERE follower_id = $2::uuid AND following_id = $1::uuid AND status = 'accepted'
		)`
	err := r.pool.QueryRow(ctx, query, userA, userB).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *UserRepository) GetFollowStatus(ctx context.Context, followerID, followingID string) (string, error) {
	var status string
	query := `SELECT status FROM public.follows WHERE follower_id = $1::uuid AND following_id = $2::uuid`
	err := r.pool.QueryRow(ctx, query, followerID, followingID).Scan(&status)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil
		}
		return "", err
	}
	return status, nil
}

type SignalKeysInput struct {
	IdentityKeyPublic     string
	SignedPrekeyPublic    string
	SignedPrekeyID        int
	SignedPrekeySignature string
	OneTimePrekeys        []byte
	RegistrationID        int
}

func (r *UserRepository) UpsertKeys(ctx context.Context, userID string, keys SignalKeysInput) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Step 1: Update identity and registration
	_, err = tx.Exec(ctx, `
		UPDATE public.profiles 
		SET identity_key = $1, registration_id = $2, updated_at = NOW()
		WHERE id = $3::uuid
	`, keys.IdentityKeyPublic, keys.RegistrationID, userID)
	if err != nil {
		return err
	}

	// Step 2: Extract and Upsert Signed Prekey
	_, err = tx.Exec(ctx, `
		INSERT INTO public.signed_prekeys (user_id, key_id, public_key, signature)
		VALUES ($1::uuid, $2, $3, $4)
		ON CONFLICT (user_id, key_id) DO UPDATE SET 
			public_key = EXCLUDED.public_key,
			signature = EXCLUDED.signature,
			created_at = NOW()
	`, userID, keys.SignedPrekeyID, keys.SignedPrekeyPublic, keys.SignedPrekeySignature)
	if err != nil {
		return err
	}

	// Step 3: Clear and Bulk Insert One-Time Prekeys
	_, err = tx.Exec(ctx, `DELETE FROM public.one_time_prekeys WHERE user_id = $1::uuid`, userID)
	if err != nil {
		return err
	}

	type OTKEntry struct {
		KeyID     int    `json:"key_id"`
		PublicKey string `json:"public_key"`
	}
	var otks []OTKEntry
	if len(keys.OneTimePrekeys) > 0 {
		if err := json.Unmarshal(keys.OneTimePrekeys, &otks); err != nil {
			return fmt.Errorf("failed to unmarshal one_time_prekeys: %w", err)
		}

		for _, otk := range otks {
			_, err = tx.Exec(ctx, `
				INSERT INTO public.one_time_prekeys (user_id, key_id, public_key)
				VALUES ($1::uuid, $2, $3)
			`, userID, otk.KeyID, otk.PublicKey)
			if err != nil {
				return err
			}
		}
	}

	return tx.Commit(ctx)
}

// DeleteUsedOTK removes a one-time prekey after it's been used for encryption
func (r *UserRepository) DeleteUsedOTK(ctx context.Context, userID string, keyID int) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM public.one_time_prekeys 
		WHERE user_id = $1::uuid AND key_id = $2
	`, userID, keyID)
	if err != nil {
		return fmt.Errorf("failed to delete used OTK: %w", err)
	}
	// OTK deleted successfully
	return nil
}

func (r *UserRepository) GetSignalKeyBundle(ctx context.Context, userID string) (map[string]interface{}, error) {
	var ikPub, spkPub, spkSig string
	var regID sql.NullInt64
	var spkID sql.NullInt64
	err := r.pool.QueryRow(ctx, `
		SELECT 
			p.identity_key as identity_key_public,
			p.registration_id,
			sp.key_id as signed_prekey_id,
			sp.public_key as signed_prekey_public,
			sp.signature as signed_prekey_signature
		FROM public.profiles p
		LEFT JOIN public.signed_prekeys sp ON p.id = sp.user_id
		WHERE p.id = $1::uuid
	`, userID).Scan(
		&ikPub,
		&regID,
		&spkID,
		&spkPub,
		&spkSig,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get signal key bundle: %w", err)
	}

	// Get available OTKs for this user
	rows, err := r.pool.Query(ctx, `
		SELECT key_id, public_key
		FROM public.one_time_prekeys
		WHERE user_id = $1::uuid
		ORDER BY created_at ASC
		LIMIT 1
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get OTKs: %w", err)
	}
	defer rows.Close()

	var otkID int
	var otkPub string
	var otk map[string]interface{}

	if rows.Next() {
		if err := rows.Scan(&otkID, &otkPub); err != nil {
			return nil, fmt.Errorf("failed to scan OTK: %w", err)
		}
		otk = map[string]interface{}{
			"key_id":     otkID,
			"public_key": otkPub,
		}
		// OTK retrieved - not logging user ID for security
	}

	// Handle NULL values properly
	var regIDValue int
	if regID.Valid {
		regIDValue = int(regID.Int64)
	} else {
		regIDValue = 1 // Default value
	}

	var spkIDValue int
	if spkID.Valid {
		spkIDValue = int(spkID.Int64)
	} else {
		spkIDValue = 1 // Default value
	}

	bundle := map[string]interface{}{
		"identity_key": map[string]interface{}{
			"key_id":     1,
			"public_key": ikPub,
		},
		"registration_id": regIDValue,
		"signed_prekey": map[string]interface{}{
			"key_id":     spkIDValue,
			"public_key": spkPub,
			"signature":  spkSig,
		},
	}

	// Add OTK if available
	if otk != nil {
		bundle["one_time_prekey"] = otk
	}

	return bundle, nil
}

func (r *UserRepository) GetPrivacySettings(ctx context.Context, userID string) (*models.PrivacySettings, error) {
	query := `
		SELECT user_id, show_location, show_interests, profile_visibility,
		       posts_visibility, saved_visibility, follow_request_policy,
		       default_post_visibility, is_private_profile,
		       allow_dms_from, searchable_by_handle, searchable_by_email,
		       updated_at
		FROM public.profile_privacy_settings
		WHERE user_id = $1::uuid
	`
	var ps models.PrivacySettings
	err := r.pool.QueryRow(ctx, query, userID).Scan(
		&ps.UserID, &ps.ShowLocation, &ps.ShowInterests, &ps.ProfileVisibility,
		&ps.PostsVisibility, &ps.SavedVisibility, &ps.FollowRequestPolicy,
		&ps.DefaultPostVisibility, &ps.IsPrivateProfile,
		&ps.AllowDMsFrom, &ps.SearchableByHandle, &ps.SearchableByEmail,
		&ps.UpdatedAt,
	)
	if err != nil {
		if err.Error() == "no rows in result set" || err.Error() == "pgx: no rows in result set" {
			// Return default settings for new users (pointers required)
			uid, _ := uuid.Parse(userID)
			t := true
			f := false
			pub := "public"
			priv := "private"
			anyone := "everyone"
			return &models.PrivacySettings{
				UserID:                uid,
				ShowLocation:          &t,
				ShowInterests:         &t,
				ProfileVisibility:     &pub,
				PostsVisibility:       &pub,
				SavedVisibility:       &priv,
				FollowRequestPolicy:   &anyone,
				DefaultPostVisibility: &pub,
				IsPrivateProfile:      &f,
				AllowDMsFrom:          &anyone,
				SearchableByHandle:    &t,
				SearchableByEmail:     &f,
				UpdatedAt:             time.Now(),
			}, nil
		}
		return nil, err
	}
	return &ps, nil
}

func (r *UserRepository) UpdatePrivacySettings(ctx context.Context, ps *models.PrivacySettings) error {
	query := `
		INSERT INTO public.profile_privacy_settings (
			user_id, show_location, show_interests, profile_visibility,
			posts_visibility, saved_visibility, follow_request_policy,
			default_post_visibility, is_private_profile,
			allow_dms_from, searchable_by_handle, searchable_by_email,
			updated_at
		) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			show_location = COALESCE(EXCLUDED.show_location, profile_privacy_settings.show_location),
			show_interests = COALESCE(EXCLUDED.show_interests, profile_privacy_settings.show_interests),
			profile_visibility = COALESCE(EXCLUDED.profile_visibility, profile_privacy_settings.profile_visibility),
			posts_visibility = COALESCE(EXCLUDED.posts_visibility, profile_privacy_settings.posts_visibility),
			saved_visibility = COALESCE(EXCLUDED.saved_visibility, profile_privacy_settings.saved_visibility),
			follow_request_policy = COALESCE(EXCLUDED.follow_request_policy, profile_privacy_settings.follow_request_policy),
			default_post_visibility = COALESCE(EXCLUDED.default_post_visibility, profile_privacy_settings.default_post_visibility),
			is_private_profile = COALESCE(EXCLUDED.is_private_profile, profile_privacy_settings.is_private_profile),
			allow_dms_from = COALESCE(EXCLUDED.allow_dms_from, profile_privacy_settings.allow_dms_from),
			searchable_by_handle = COALESCE(EXCLUDED.searchable_by_handle, profile_privacy_settings.searchable_by_handle),
			searchable_by_email = COALESCE(EXCLUDED.searchable_by_email, profile_privacy_settings.searchable_by_email),
			updated_at = NOW()
	`
	_, err := r.pool.Exec(ctx, query,
		ps.UserID, ps.ShowLocation, ps.ShowInterests, ps.ProfileVisibility,
		ps.PostsVisibility, ps.SavedVisibility, ps.FollowRequestPolicy,
		ps.DefaultPostVisibility, ps.IsPrivateProfile,
		ps.AllowDMsFrom, ps.SearchableByHandle, ps.SearchableByEmail,
	)
	return err
}

// GetDMPermission returns the allow_dms_from setting for a user.
func (r *UserRepository) GetDMPermission(ctx context.Context, userID string) (string, error) {
	var perm string
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(allow_dms_from, 'everyone') FROM public.profile_privacy_settings WHERE user_id = $1::uuid`,
		userID).Scan(&perm)
	if err != nil {
		// No row means default = everyone
		return "everyone", nil
	}
	return perm, nil
}

func (r *UserRepository) GetUserSettings(ctx context.Context, userID string) (*models.UserSettings, error) {
	query := `
		SELECT user_id, theme, language, notifications_enabled, email_notifications,
		       push_notifications, content_filter_level, auto_play_videos, data_saver_mode, 
		       default_post_ttl, COALESCE(nsfw_enabled, FALSE), COALESCE(nsfw_blur_enabled, TRUE), updated_at
		FROM public.user_settings
		WHERE user_id = $1::uuid
	`
	var us models.UserSettings
	err := r.pool.QueryRow(ctx, query, userID).Scan(
		&us.UserID, &us.Theme, &us.Language, &us.NotificationsEnabled, &us.EmailNotifications,
		&us.PushNotifications, &us.ContentFilterLevel, &us.AutoPlayVideos, &us.DataSaverMode,
		&us.DefaultPostTtl, &us.NSFWEnabled, &us.NSFWBlurEnabled, &us.UpdatedAt,
	)
	if err != nil {
		if err.Error() == "no rows in result set" || err.Error() == "pgx: no rows in result set" {
			// Return default settings for new users (pointers required)
			uid, _ := uuid.Parse(userID)
			sys := "system"
			en := "en"
			med := "medium"
			t := true
			f := false
			return &models.UserSettings{
				UserID:               uid,
				Theme:                &sys,
				Language:             &en,
				NotificationsEnabled: &t,
				EmailNotifications:   &t,
				PushNotifications:    &t,
				ContentFilterLevel:   &med,
				AutoPlayVideos:       &t,
				DataSaverMode:        &f,
				NSFWEnabled:          &f,
				NSFWBlurEnabled:      &t,
				UpdatedAt:            time.Now(),
			}, nil
		}
		return nil, err
	}
	return &us, nil
}

func (r *UserRepository) UpdateUserSettings(ctx context.Context, us *models.UserSettings) error {
	query := `
		INSERT INTO public.user_settings (
			user_id, theme, language, notifications_enabled, email_notifications,
			push_notifications, content_filter_level, auto_play_videos, data_saver_mode, 
			default_post_ttl, nsfw_enabled, nsfw_blur_enabled, updated_at
		) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			theme = COALESCE(EXCLUDED.theme, user_settings.theme),
			language = COALESCE(EXCLUDED.language, user_settings.language),
			notifications_enabled = COALESCE(EXCLUDED.notifications_enabled, user_settings.notifications_enabled),
			email_notifications = COALESCE(EXCLUDED.email_notifications, user_settings.email_notifications),
			push_notifications = COALESCE(EXCLUDED.push_notifications, user_settings.push_notifications),
			content_filter_level = COALESCE(EXCLUDED.content_filter_level, user_settings.content_filter_level),
			auto_play_videos = COALESCE(EXCLUDED.auto_play_videos, user_settings.auto_play_videos),
			data_saver_mode = COALESCE(EXCLUDED.data_saver_mode, user_settings.data_saver_mode),
			default_post_ttl = COALESCE(EXCLUDED.default_post_ttl, user_settings.default_post_ttl),
			nsfw_enabled = COALESCE(EXCLUDED.nsfw_enabled, user_settings.nsfw_enabled),
			nsfw_blur_enabled = COALESCE(EXCLUDED.nsfw_blur_enabled, user_settings.nsfw_blur_enabled),
			updated_at = NOW()
	`
	_, err := r.pool.Exec(ctx, query,
		us.UserID, us.Theme, us.Language, us.NotificationsEnabled, us.EmailNotifications,
		us.PushNotifications, us.ContentFilterLevel, us.AutoPlayVideos, us.DataSaverMode,
		us.DefaultPostTtl, us.NSFWEnabled, us.NSFWBlurEnabled,
	)
	return err
}

func (r *UserRepository) UpsertFCMToken(ctx context.Context, userID string, token string, platform string) error {
	query := `
		INSERT INTO public.user_fcm_tokens (user_id, token, device_type, last_updated)
		VALUES ($1::uuid, $2, $3, NOW())
		ON CONFLICT (user_id, token) DO UPDATE SET
			last_updated = NOW(),
			device_type = EXCLUDED.device_type
	`
	_, err := r.pool.Exec(ctx, query, userID, token, platform)
	return err
}

func (r *UserRepository) GetFCMTokens(ctx context.Context, userID string) ([]string, error) {
	query := `SELECT token FROM public.user_fcm_tokens WHERE user_id = $1::uuid`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			return nil, err
		}
		tokens = append(tokens, token)
	}
	return tokens, nil
}

func (r *UserRepository) DeleteFCMToken(ctx context.Context, userID string, token string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM public.user_fcm_tokens
		WHERE user_id = $1::uuid AND token = $2
	`, userID, token)
	return err
}

func (r *UserRepository) StoreRefreshToken(ctx context.Context, userID string, tokenString string, duration time.Duration) error {
	hash := sha256.Sum256([]byte(tokenString))
	hashString := hex.EncodeToString(hash[:])

	query := `
		INSERT INTO refresh_tokens (token_hash, user_id, expires_at)
		VALUES ($1, $2::uuid, $3)
	`
	_, err := r.pool.Exec(ctx, query, hashString, userID, time.Now().Add(duration))
	return err
}

func (r *UserRepository) ValidateRefreshToken(ctx context.Context, tokenString string) (*models.RefreshToken, error) {
	hash := sha256.Sum256([]byte(tokenString))
	hashString := hex.EncodeToString(hash[:])

	var rt models.RefreshToken
	query := `
		SELECT token_hash, user_id, expires_at, revoked, created_at
		FROM refresh_tokens
		WHERE token_hash = $1
	`
	err := r.pool.QueryRow(ctx, query, hashString).Scan(
		&rt.TokenHash, &rt.UserID, &rt.ExpiresAt, &rt.Revoked, &rt.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	if rt.Revoked {
		return nil, fmt.Errorf("token revoked")
	}
	if time.Now().After(rt.ExpiresAt) {
		return nil, fmt.Errorf("token expired")
	}

	return &rt, nil
}

func (r *UserRepository) RevokeRefreshToken(ctx context.Context, tokenString string) error {
	hash := sha256.Sum256([]byte(tokenString))
	hashString := hex.EncodeToString(hash[:])

	query := `UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1`
	_, err := r.pool.Exec(ctx, query, hashString)
	return err
}

func (r *UserRepository) RevokeAllUserTokens(ctx context.Context, userID string) error {
	query := `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1::uuid`
	_, err := r.pool.Exec(ctx, query, userID)
	return err
}

func (r *UserRepository) CreateAuthToken(ctx context.Context, token *models.AuthToken) error {
	query := `INSERT INTO public.auth_tokens (token, user_id, type, expires_at, created_at) VALUES ($1, $2, $3, $4, $5)`
	_, err := r.pool.Exec(ctx, query, token.Token, token.UserID, token.Type, token.ExpiresAt, token.CreatedAt)
	return err
}

func (r *UserRepository) GetAuthToken(ctx context.Context, tokenStr string) (*models.AuthToken, error) {
	query := `SELECT token, user_id, type, expires_at, created_at FROM public.auth_tokens WHERE token = $1`
	var t models.AuthToken
	err := r.pool.QueryRow(ctx, query, tokenStr).Scan(&t.Token, &t.UserID, &t.Type, &t.ExpiresAt, &t.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *UserRepository) DeleteAuthToken(ctx context.Context, tokenStr string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM public.auth_tokens WHERE token = $1`, tokenStr)
	return err
}

func (r *UserRepository) UpdateUserStatus(ctx context.Context, userID string, status models.UserStatus) error {
	_, err := r.pool.Exec(ctx, `UPDATE public.users SET status = $1, updated_at = NOW() WHERE id = $2::uuid`, status, userID)
	return err
}

func (r *UserRepository) UpdateLastLogin(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `UPDATE public.users SET last_login = NOW() WHERE id = $1::uuid`, userID)
	return err
}

func (r *UserRepository) UpsertMFASecret(ctx context.Context, secret *models.MFASecret) error {
	query := `
		INSERT INTO public.user_mfa_secrets (user_id, secret_key, recovery_codes, updated_at)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			secret_key = EXCLUDED.secret_key,
			recovery_codes = EXCLUDED.recovery_codes,
			updated_at = NOW()
	`
	_, err := r.pool.Exec(ctx, query, secret.UserID, secret.Secret, secret.RecoveryCodes)
	return err
}

func (r *UserRepository) GetMFASecret(ctx context.Context, userID string) (*models.MFASecret, error) {
	query := `SELECT user_id, secret_key, recovery_codes FROM public.user_mfa_secrets WHERE user_id = $1::uuid`
	var s models.MFASecret
	err := r.pool.QueryRow(ctx, query, userID).Scan(&s.UserID, &s.Secret, &s.RecoveryCodes)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// Verification Tokens (New Table)
func (r *UserRepository) CreateVerificationToken(ctx context.Context, tokenHash string, userID string, duration time.Duration) error {
	query := `INSERT INTO public.verification_tokens (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`
	_, err := r.pool.Exec(ctx, query, tokenHash, userID, time.Now().Add(duration))
	return err
}

func (r *UserRepository) GetVerificationToken(ctx context.Context, tokenHash string) (string, time.Time, error) {
	query := `SELECT user_id, expires_at FROM public.verification_tokens WHERE token_hash = $1`
	var userID string
	var expiresAt time.Time
	err := r.pool.QueryRow(ctx, query, tokenHash).Scan(&userID, &expiresAt)
	if err != nil {
		return "", time.Time{}, err
	}
	return userID, expiresAt, nil
}

func (r *UserRepository) DeleteVerificationToken(ctx context.Context, tokenHash string) error {
	query := `DELETE FROM public.verification_tokens WHERE token_hash = $1`
	_, err := r.pool.Exec(ctx, query, tokenHash)
	return err
}

// Password Reset Tokens
func (r *UserRepository) CreatePasswordResetToken(ctx context.Context, tokenHash string, userID string, duration time.Duration) error {
	query := `INSERT INTO public.password_reset_tokens (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`
	_, err := r.pool.Exec(ctx, query, tokenHash, userID, time.Now().Add(duration))
	return err
}

func (r *UserRepository) GetPasswordResetToken(ctx context.Context, tokenHash string) (string, time.Time, error) {
	query := `SELECT user_id, expires_at FROM public.password_reset_tokens WHERE token_hash = $1`
	var userID string
	var expiresAt time.Time
	err := r.pool.QueryRow(ctx, query, tokenHash).Scan(&userID, &expiresAt)
	if err != nil {
		return "", time.Time{}, err
	}
	return userID, expiresAt, nil
}

func (r *UserRepository) DeletePasswordResetToken(ctx context.Context, tokenHash string) error {
	query := `DELETE FROM public.password_reset_tokens WHERE token_hash = $1`
	_, err := r.pool.Exec(ctx, query, tokenHash)
	return err
}

func (r *UserRepository) UpdateUserPassword(ctx context.Context, userID string, passwordHash string) error {
	query := `UPDATE public.users SET encrypted_password = $1, updated_at = NOW() WHERE id = $2::uuid`
	_, err := r.pool.Exec(ctx, query, passwordHash, userID)
	return err
}

// WebAuthn Credentials (placeholder comment if more methods follow, or strictly implement the requested method)

func (r *UserRepository) FetchAndConsumeOneTimeKey(ctx context.Context, userID string) (*models.OneTimePrekey, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var otk models.OneTimePrekey
	// Logic: Execute SELECT ... FROM one_time_prekeys WHERE user_id = $1 ORDER BY created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED
	query := `
		SELECT key_id, public_key
		FROM public.one_time_prekeys
		WHERE user_id = $1::uuid
		ORDER BY created_at ASC
		LIMIT 1
		FOR UPDATE SKIP LOCKED
	`

	err = tx.QueryRow(ctx, query, userID).Scan(&otk.KeyID, &otk.PublicKey)
	if err != nil {
		if err == pgx.ErrNoRows {
			// If not found: Return nil (this is valid protocol behavior)
			return nil, tx.Commit(ctx)
		}
		return nil, err
	}

	// If found: DELETE the row immediately and return the key data.
	_, err = tx.Exec(ctx, `DELETE FROM public.one_time_prekeys WHERE user_id = $1::uuid AND key_id = $2`, userID, otk.KeyID)
	if err != nil {
		return nil, fmt.Errorf("failed to delete one-time key: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &otk, nil
}
func (r *UserRepository) CreateWebAuthnCredential(ctx context.Context, cred *models.WebAuthnCredential) error {
	query := `
		INSERT INTO public.webauthn_credentials (user_id, credential_id, public_key, attestation_type, aaguid, sign_count, last_used_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`
	_, err := r.pool.Exec(ctx, query, cred.UserID, cred.ID, cred.PublicKey, cred.AttestationType, cred.AAGUID, cred.SignCount, cred.LastUsedAt)
	return err
}

func (r *UserRepository) GetWebAuthnCredentials(ctx context.Context, userID string) ([]models.WebAuthnCredential, error) {
	query := `SELECT id, user_id, credential_id, public_key, attestation_type, aaguid, sign_count, last_used_at FROM public.webauthn_credentials WHERE user_id = $1::uuid`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var creds []models.WebAuthnCredential
	for rows.Next() {
		var c models.WebAuthnCredential
		var idStr string
		err := rows.Scan(&idStr, &c.UserID, &c.ID, &c.PublicKey, &c.AttestationType, &c.AAGUID, &c.SignCount, &c.LastUsedAt)
		if err != nil {
			return nil, err
		}
		creds = append(creds, c)
	}
	return creds, nil
}

// DeleteUser removes a user by ID. SHOULD BE USED WITH CAUTION (e.g. rollback)
func (r *UserRepository) DeleteUser(ctx context.Context, userID uuid.UUID) error {
	query := `DELETE FROM public.users WHERE id = $1`
	_, err := r.pool.Exec(ctx, query, userID)
	return err
}
func (r *UserRepository) BlockUserByHandle(ctx context.Context, actorID string, handle string, actorIP string) error {
	var targetID uuid.UUID
	err := r.pool.QueryRow(ctx, "SELECT id FROM public.profiles WHERE handle = $1", handle).Scan(&targetID)
	if err != nil {
		return err
	}
	return r.BlockUser(ctx, actorID, targetID.String(), actorIP)
}

// ========================================================================
// Social Graph: Followers & Following Lists
// ========================================================================

type FollowerUser struct {
	ID           uuid.UUID `json:"id"`
	Handle       string    `json:"handle"`
	DisplayName  string    `json:"display_name"`
	AvatarURL    *string   `json:"avatar_url"`
	HarmonyScore int       `json:"harmony_score"`
	Tier         string    `json:"tier"`
	FollowedAt   time.Time `json:"followed_at"`
}

// GetFollowers returns a list of users following the specified user
func (r *UserRepository) GetFollowers(ctx context.Context, userID string, limit, offset int) ([]FollowerUser, error) {
	query := `
		SELECT 
			p.id, p.handle, p.display_name, p.avatar_url,
			COALESCE(t.harmony_score, 50) as harmony_score,
			COALESCE(t.tier, 'new') as tier,
			f.created_at as followed_at
		FROM public.follows f
		JOIN public.profiles p ON p.id = f.follower_id
		LEFT JOIN public.trust_state t ON t.user_id = p.id
		WHERE f.following_id = $1::uuid AND f.status = 'accepted'
		ORDER BY f.created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var followers []FollowerUser
	for rows.Next() {
		var f FollowerUser
		if err := rows.Scan(&f.ID, &f.Handle, &f.DisplayName, &f.AvatarURL, &f.HarmonyScore, &f.Tier, &f.FollowedAt); err != nil {
			return nil, err
		}
		followers = append(followers, f)
	}
	return followers, nil
}

// GetFollowing returns a list of users the specified user is following
func (r *UserRepository) GetFollowing(ctx context.Context, userID string, limit, offset int) ([]FollowerUser, error) {
	query := `
		SELECT 
			p.id, p.handle, p.display_name, p.avatar_url,
			COALESCE(t.harmony_score, 50) as harmony_score,
			COALESCE(t.tier, 'new') as tier,
			f.created_at as followed_at
		FROM public.follows f
		JOIN public.profiles p ON p.id = f.following_id
		LEFT JOIN public.trust_state t ON t.user_id = p.id
		WHERE f.follower_id = $1::uuid AND f.status = 'accepted'
		ORDER BY f.created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var following []FollowerUser
	for rows.Next() {
		var f FollowerUser
		if err := rows.Scan(&f.ID, &f.Handle, &f.DisplayName, &f.AvatarURL, &f.HarmonyScore, &f.Tier, &f.FollowedAt); err != nil {
			return nil, err
		}
		following = append(following, f)
	}
	return following, nil
}

// ========================================================================
// Circle (Close Friends) Management
// ========================================================================

// AddToCircle adds a user to the current user's circle
func (r *UserRepository) AddToCircle(ctx context.Context, userID, memberID string) error {
	// Verify that the user follows the member first
	isFollowing, err := r.IsFollowing(ctx, userID, memberID)
	if err != nil {
		return err
	}
	if !isFollowing {
		return fmt.Errorf("can only add users you follow to your circle")
	}

	query := `
		INSERT INTO public.circle_members (user_id, member_id)
		VALUES ($1::uuid, $2::uuid)
		ON CONFLICT DO NOTHING
	`
	_, err = r.pool.Exec(ctx, query, userID, memberID)
	return err
}

// RemoveFromCircle removes a user from the current user's circle
func (r *UserRepository) RemoveFromCircle(ctx context.Context, userID, memberID string) error {
	query := `DELETE FROM public.circle_members WHERE user_id = $1::uuid AND member_id = $2::uuid`
	_, err := r.pool.Exec(ctx, query, userID, memberID)
	return err
}

// GetCircleMembers returns all users in the current user's circle
func (r *UserRepository) GetCircleMembers(ctx context.Context, userID string) ([]FollowerUser, error) {
	query := `
		SELECT 
			p.id, p.handle, p.display_name, p.avatar_url,
			COALESCE(t.harmony_score, 50) as harmony_score,
			COALESCE(t.tier, 'new') as tier,
			c.created_at as followed_at
		FROM public.circle_members c
		JOIN public.profiles p ON p.id = c.member_id
		LEFT JOIN public.trust_state t ON t.user_id = p.id
		WHERE c.user_id = $1::uuid
		ORDER BY c.created_at DESC
	`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []FollowerUser
	for rows.Next() {
		var m FollowerUser
		if err := rows.Scan(&m.ID, &m.Handle, &m.DisplayName, &m.AvatarURL, &m.HarmonyScore, &m.Tier, &m.FollowedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	return members, nil
}

// IsInCircle checks if a user is in another user's circle
func (r *UserRepository) IsInCircle(ctx context.Context, ownerID, userID string) (bool, error) {
	var exists bool
	query := `SELECT EXISTS(SELECT 1 FROM public.circle_members WHERE user_id = $1::uuid AND member_id = $2::uuid)`
	err := r.pool.QueryRow(ctx, query, ownerID, userID).Scan(&exists)
	return exists, err
}

// ========================================================================
// Data Export (Portability)
// ========================================================================

type UserExportData struct {
	Profile   *models.Profile  `json:"profile"`
	Posts     []ExportedPost   `json:"posts"`
	Following []ExportedFollow `json:"following"`
}

type ExportedPost struct {
	ID        uuid.UUID `json:"id"`
	Body      string    `json:"body"`
	ImageURL  *string   `json:"image_url,omitempty"`
	VideoURL  *string   `json:"video_url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type ExportedFollow struct {
	Handle      string    `json:"handle"`
	DisplayName string    `json:"display_name"`
	FollowedAt  time.Time `json:"followed_at"`
}

// ExportUserData generates complete user data export for portability
func (r *UserRepository) ExportUserData(ctx context.Context, userID string) (*UserExportData, error) {
	export := &UserExportData{}

	// 1. Get Profile
	profile, err := r.GetProfileByID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get profile: %w", err)
	}
	export.Profile = profile

	// 2. Get All Posts
	postQuery := `
		SELECT id, body, image_url, video_url, created_at
		FROM public.posts
		WHERE author_id = $1::uuid AND deleted_at IS NULL
		ORDER BY created_at DESC
	`
	rows, err := r.pool.Query(ctx, postQuery, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get posts: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var p ExportedPost
		if err := rows.Scan(&p.ID, &p.Body, &p.ImageURL, &p.VideoURL, &p.CreatedAt); err != nil {
			return nil, err
		}
		export.Posts = append(export.Posts, p)
	}

	// 3. Get Following List
	followQuery := `
		SELECT p.handle, p.display_name, f.created_at
		FROM public.follows f
		JOIN public.profiles p ON p.id = f.following_id
		WHERE f.follower_id = $1::uuid AND f.status = 'accepted'
		ORDER BY f.created_at DESC
	`
	rows, err = r.pool.Query(ctx, followQuery, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get following list: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var f ExportedFollow
		if err := rows.Scan(&f.Handle, &f.DisplayName, &f.FollowedAt); err != nil {
			return nil, err
		}
		export.Following = append(export.Following, f)
	}

	return export, nil
}

// BanIP records an IP address as banned (used when a user is banned to prevent evasion)
func (r *UserRepository) BanIP(ctx context.Context, ipAddress string, userID string, reason string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO banned_ips (ip_address, user_id, reason, banned_at)
		VALUES ($1, $2::uuid, $3, NOW())
	`, ipAddress, userID, reason)
	return err
}

// IsIPBanned checks if an IP address has been banned
func (r *UserRepository) IsIPBanned(ctx context.Context, ipAddress string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM banned_ips WHERE ip_address = $1)
	`, ipAddress).Scan(&exists)
	return exists, err
}

// ========================================================================
// Account Lifecycle: Deactivate, Delete, Destroy
// ========================================================================

// DeactivateUser sets user status to deactivated, preserves all data
func (r *UserRepository) DeactivateUser(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.users 
		SET status = 'deactivated', updated_at = NOW() 
		WHERE id = $1::uuid
	`, userID)
	return err
}

// ReactivateUser sets a deactivated user back to active
func (r *UserRepository) ReactivateUser(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.users 
		SET status = 'active', deleted_at = NULL, updated_at = NOW() 
		WHERE id = $1::uuid AND status IN ('deactivated', 'pending_deletion')
	`, userID)
	return err
}

// ScheduleDeletion marks account for deletion after 14 days
func (r *UserRepository) ScheduleDeletion(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE public.users 
		SET status = 'pending_deletion', deleted_at = NOW() + INTERVAL '14 days', updated_at = NOW() 
		WHERE id = $1::uuid
	`, userID)
	return err
}

// CancelDeletion reverts a pending deletion back to active
func (r *UserRepository) CancelDeletion(ctx context.Context, userID string) error {
	return r.ReactivateUser(ctx, userID)
}

// GetAccountsPendingPurge returns user IDs whose deletion grace period has expired
func (r *UserRepository) GetAccountsPendingPurge(ctx context.Context) ([]string, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text FROM public.users 
		WHERE status = 'pending_deletion' AND deleted_at IS NOT NULL AND deleted_at <= NOW()
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}

// CascadePurgeUser permanently deletes ALL user data from every table. Irreversible.
func (r *UserRepository) CascadePurgeUser(ctx context.Context, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Order matters: delete from leaf tables first, then parent tables
	purgeQueries := []string{
		// Post-related (leaf tables first)
		`DELETE FROM public.post_reactions WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_likes WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_saves WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_mentions WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_interactions WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_metrics WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_hashtags WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		`DELETE FROM public.post_categories WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		// Also remove this user's likes/saves/reactions on OTHER people's posts
		`DELETE FROM public.post_reactions WHERE user_id = $1::uuid`,
		`DELETE FROM public.post_likes WHERE user_id = $1::uuid`,
		`DELETE FROM public.post_saves WHERE user_id = $1::uuid`,
		`DELETE FROM public.post_interactions WHERE user_id = $1::uuid`,
		// Beacon votes
		`DELETE FROM public.beacon_votes WHERE user_id = $1::uuid`,
		// Comments on user's posts
		`DELETE FROM public.comments WHERE post_id IN (SELECT id FROM public.posts WHERE author_id = $1::uuid)`,
		// User's own comments
		`DELETE FROM public.comments WHERE author_id = $1::uuid`,
		// Feed engagement
		`DELETE FROM public.feed_engagement WHERE user_id = $1::uuid`,
		// Posts themselves
		`DELETE FROM public.posts WHERE author_id = $1::uuid`,
		// Messaging / E2EE
		`DELETE FROM public.secure_messages WHERE sender_id = $1::uuid OR receiver_id = $1::uuid`,
		`DELETE FROM public.encrypted_messages WHERE sender_id = $1::uuid OR receiver_id = $1::uuid`,
		`DELETE FROM public.e2ee_session_state WHERE session_id IN (SELECT id FROM public.e2ee_sessions WHERE user_a = $1::uuid OR user_b = $1::uuid)`,
		`DELETE FROM public.e2ee_sessions WHERE user_a = $1::uuid OR user_b = $1::uuid`,
		`DELETE FROM public.encrypted_conversations WHERE participant_a = $1::uuid OR participant_b = $1::uuid`,
		// Signal keys
		`DELETE FROM public.one_time_prekeys WHERE user_id = $1::uuid`,
		`DELETE FROM public.signed_prekeys WHERE user_id = $1::uuid`,
		`DELETE FROM public.signal_keys WHERE user_id = $1::uuid`,
		// Social graph
		`DELETE FROM public.circle_members WHERE user_id = $1::uuid OR member_id = $1::uuid`,
		`DELETE FROM public.follows WHERE follower_id = $1::uuid OR following_id = $1::uuid`,
		`DELETE FROM public.blocks WHERE blocker_id = $1::uuid OR blocked_id = $1::uuid`,
		// Notifications
		`DELETE FROM public.notifications WHERE user_id = $1::uuid OR actor_id = $1::uuid`,
		`DELETE FROM public.notification_preferences WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_fcm_tokens WHERE user_id = $1::uuid`,
		// Moderation & violations
		`DELETE FROM public.moderation_flags WHERE user_id = $1::uuid`,
		`DELETE FROM public.pending_moderation WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_violation_history WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_violations WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_appeals WHERE user_id = $1::uuid`,
		`DELETE FROM public.content_strikes WHERE user_id = $1::uuid`,
		`DELETE FROM public.reports WHERE reporter_id = $1::uuid`,
		`DELETE FROM public.abuse_logs WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_status_history WHERE user_id = $1::uuid`,
		// Categories & hashtags
		`DELETE FROM public.user_category_preferences WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_category_settings WHERE user_id = $1::uuid`,
		`DELETE FROM public.hashtag_follows WHERE user_id = $1::uuid`,
		// Backup & recovery
		`DELETE FROM public.recovery_shard_submissions WHERE session_id IN (SELECT id FROM public.recovery_sessions WHERE user_id = $1::uuid)`,
		`DELETE FROM public.recovery_sessions WHERE user_id = $1::uuid`,
		`DELETE FROM public.recovery_guardians WHERE user_id = $1::uuid OR guardian_id = $1::uuid`,
		`DELETE FROM public.cloud_backups WHERE user_id = $1::uuid`,
		`DELETE FROM public.backup_preferences WHERE user_id = $1::uuid`,
		`DELETE FROM public.sync_codes WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_devices WHERE user_id = $1::uuid`,
		// Auth & tokens
		`DELETE FROM public.auth_tokens WHERE user_id = $1::uuid`,
		`DELETE FROM public.refresh_tokens WHERE user_id = $1::uuid`,
		`DELETE FROM public.verification_tokens WHERE user_id = $1::uuid`,
		`DELETE FROM public.password_reset_tokens WHERE user_id = $1::uuid`,
		`DELETE FROM public.webauthn_credentials WHERE user_id = $1::uuid`,
		`DELETE FROM public.user_mfa_secrets WHERE user_id = $1::uuid`,
		// Settings
		`DELETE FROM public.user_settings WHERE user_id = $1::uuid`,
		`DELETE FROM public.profile_privacy_settings WHERE user_id = $1::uuid`,
		// Trust
		`DELETE FROM public.trust_state WHERE user_id = $1::uuid`,
		// Username claims
		`DELETE FROM public.username_claim_requests WHERE user_id = $1::uuid`,
		// AI moderation log (content snippets from public posts; must be purged with user)
		`DELETE FROM public.ai_moderation_log WHERE author_id = $1::uuid`,
		// Profile & user (last)
		`DELETE FROM public.profiles WHERE id = $1::uuid`,
		`DELETE FROM public.users WHERE id = $1::uuid`,
	}

	for _, q := range purgeQueries {
		if _, err := tx.Exec(ctx, q, userID); err != nil {
			return fmt.Errorf("purge query failed: %s: %w", q[:60], err)
		}
	}

	return tx.Commit(ctx)
}
