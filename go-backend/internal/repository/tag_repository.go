// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package repository

import (
	"context"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"github.com/rs/zerolog/log"
)

type TagRepository struct {
	pool *pgxpool.Pool
}

func NewTagRepository(pool *pgxpool.Pool) *TagRepository {
	return &TagRepository{pool: pool}
}

// ============================================================================
// Hashtag CRUD
// ============================================================================

// GetOrCreateHashtag finds or creates a hashtag by name
func (r *TagRepository) GetOrCreateHashtag(ctx context.Context, name string) (*models.Hashtag, error) {
	normalized := strings.ToLower(strings.TrimPrefix(name, "#"))
	if normalized == "" {
		return nil, nil
	}

	var hashtag models.Hashtag
	err := r.pool.QueryRow(ctx, `
		INSERT INTO hashtags (name, display_name)
		VALUES ($1, $2)
		ON CONFLICT (name) DO UPDATE SET updated_at = NOW()
		RETURNING id, name, display_name, use_count, trending_score, is_trending, is_featured, category, created_at
	`, normalized, name).Scan(
		&hashtag.ID, &hashtag.Name, &hashtag.DisplayName, &hashtag.UseCount,
		&hashtag.TrendingScore, &hashtag.IsTrending, &hashtag.IsFeatured, &hashtag.Category, &hashtag.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	return &hashtag, nil
}

// GetHashtagByName retrieves a hashtag by its normalized name
func (r *TagRepository) GetHashtagByName(ctx context.Context, name string) (*models.Hashtag, error) {
	normalized := strings.ToLower(strings.TrimPrefix(name, "#"))

	var hashtag models.Hashtag
	err := r.pool.QueryRow(ctx, `
		SELECT id, name, display_name, use_count, trending_score, is_trending, is_featured, category, created_at
		FROM hashtags WHERE name = $1
	`, normalized).Scan(
		&hashtag.ID, &hashtag.Name, &hashtag.DisplayName, &hashtag.UseCount,
		&hashtag.TrendingScore, &hashtag.IsTrending, &hashtag.IsFeatured, &hashtag.Category, &hashtag.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &hashtag, nil
}

// SearchHashtags searches for hashtags matching a query
func (r *TagRepository) SearchHashtags(ctx context.Context, query string, limit int) ([]models.Hashtag, error) {
	normalized := strings.ToLower(strings.TrimPrefix(query, "#"))

	rows, err := r.pool.Query(ctx, `
		SELECT id, name, display_name, use_count, trending_score, is_trending, is_featured, category, created_at
		FROM hashtags
		WHERE name ILIKE $1 || '%'
		ORDER BY use_count DESC, name ASC
		LIMIT $2
	`, normalized, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hashtags []models.Hashtag
	for rows.Next() {
		var h models.Hashtag
		err := rows.Scan(
			&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
			&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		hashtags = append(hashtags, h)
	}

	return hashtags, nil
}

// ============================================================================
// Post-Hashtag Linking
// ============================================================================

// LinkHashtagsToPost extracts hashtags from text and links them to a post
func (r *TagRepository) LinkHashtagsToPost(ctx context.Context, postID uuid.UUID, text string) error {
	hashtags := extractHashtags(text)
	if len(hashtags) == 0 {
		return nil
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, tag := range hashtags {
		// Get or create the hashtag
		var hashtagID uuid.UUID
		err := tx.QueryRow(ctx, `
			INSERT INTO hashtags (name, display_name)
			VALUES ($1, $2)
			ON CONFLICT (name) DO UPDATE SET updated_at = NOW()
			RETURNING id
		`, strings.ToLower(tag), tag).Scan(&hashtagID)
		if err != nil {
			log.Warn().Err(err).Str("tag", tag).Msg("Failed to create hashtag")
			continue
		}

		// Link to post
		_, err = tx.Exec(ctx, `
			INSERT INTO post_hashtags (post_id, hashtag_id)
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, postID, hashtagID)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to link hashtag to post")
		}
	}

	return tx.Commit(ctx)
}

// UnlinkHashtagsFromPost removes all hashtag links for a post
func (r *TagRepository) UnlinkHashtagsFromPost(ctx context.Context, postID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM post_hashtags WHERE post_id = $1`, postID)
	return err
}

// GetHashtagsForPost returns all hashtags linked to a post
func (r *TagRepository) GetHashtagsForPost(ctx context.Context, postID uuid.UUID) ([]models.Hashtag, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT h.id, h.name, h.display_name, h.use_count, h.trending_score, h.is_trending, h.is_featured, h.category, h.created_at
		FROM hashtags h
		JOIN post_hashtags ph ON h.id = ph.hashtag_id
		WHERE ph.post_id = $1
		ORDER BY h.name
	`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hashtags []models.Hashtag
	for rows.Next() {
		var h models.Hashtag
		err := rows.Scan(
			&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
			&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		hashtags = append(hashtags, h)
	}

	return hashtags, nil
}

// GetPostsByHashtag returns posts that contain a specific hashtag
func (r *TagRepository) GetPostsByHashtag(ctx context.Context, hashtagName, viewerID string, limit, offset int) ([]models.Post, error) {
	normalized := strings.ToLower(strings.TrimPrefix(hashtagName, "#"))

	rows, err := r.pool.Query(ctx, `
		SELECT 
			p.id, p.author_id, p.body, p.image_url, p.video_url, p.status, p.created_at,
			p.tone_label, p.cis_score, p.body_format, p.tags, p.visibility, p.is_beacon,
			pr.id, pr.handle, pr.display_name, pr.avatar_url,
			(SELECT COUNT(*) FROM post_likes WHERE post_id = p.id) as like_count,
			EXISTS(SELECT 1 FROM post_likes WHERE post_id = p.id AND user_id = $3::uuid) as user_has_liked
		FROM posts p
		JOIN post_hashtags ph ON p.id = ph.post_id
		JOIN hashtags h ON ph.hashtag_id = h.id
		JOIN profiles pr ON p.author_id = pr.id
		WHERE h.name = $1
		AND p.deleted_at IS NULL
		AND p.status = 'active'
		AND COALESCE(p.is_nsfw, FALSE) = FALSE
		ORDER BY p.created_at DESC
		LIMIT $4 OFFSET $5
	`, normalized, normalized, viewerID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		var authorID uuid.UUID
		var authorHandle, authorDisplayName, authorAvatarURL *string
		var likeCount int
		var isLiked bool

		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.Body, &p.ImageURL, &p.VideoURL, &p.Status, &p.CreatedAt,
			&p.ToneLabel, &p.CISScore, &p.BodyFormat, &p.Tags, &p.Visibility, &p.IsBeacon,
			&authorID, &authorHandle, &authorDisplayName, &authorAvatarURL,
			&likeCount, &isLiked,
		)
		if err != nil {
			return nil, err
		}

		p.LikeCount = likeCount
		p.IsLiked = isLiked

		// Build author profile
		handle := ""
		displayName := ""
		avatarURL := ""
		if authorHandle != nil {
			handle = *authorHandle
		}
		if authorDisplayName != nil {
			displayName = *authorDisplayName
		}
		if authorAvatarURL != nil {
			avatarURL = *authorAvatarURL
		}
		p.Author = &models.AuthorProfile{
			ID:          authorID,
			Handle:      handle,
			DisplayName: displayName,
			AvatarURL:   avatarURL,
		}

		posts = append(posts, p)
	}

	return posts, nil
}

// ============================================================================
// Trending & Discover
// ============================================================================

// GetTrendingHashtags returns top trending hashtags
func (r *TagRepository) GetTrendingHashtags(ctx context.Context, limit int) ([]models.Hashtag, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT h.id, h.name, h.display_name, h.use_count, h.trending_score, h.is_trending, h.is_featured, h.category, h.created_at,
			(SELECT COUNT(*) FROM post_hashtags ph WHERE ph.hashtag_id = h.id AND ph.created_at > NOW() - INTERVAL '24 hours') as recent_count
		FROM hashtags h
		WHERE h.trending_score > 0
		ORDER BY h.trending_score DESC, h.use_count DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hashtags []models.Hashtag
	for rows.Next() {
		var h models.Hashtag
		var recentCount int
		err := rows.Scan(
			&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
			&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt, &recentCount,
		)
		if err != nil {
			return nil, err
		}
		h.RecentCount = recentCount
		hashtags = append(hashtags, h)
	}

	// Backfill with featured or most-used hashtags if not enough trending results
	if len(hashtags) < limit {
		existingIDs := make([]string, len(hashtags))
		for i, h := range hashtags {
			existingIDs[i] = h.ID.String()
		}
		remaining := limit - len(hashtags)
		backfillRows, err := r.pool.Query(ctx, `
			SELECT id, name, display_name, use_count, trending_score, is_trending, is_featured, category, created_at, 0 as recent_count
			FROM hashtags
			WHERE ($1::uuid[] IS NULL OR id != ALL($1::uuid[]))
			ORDER BY is_featured DESC, use_count DESC
			LIMIT $2
		`, existingIDs, remaining)
		if err == nil {
			defer backfillRows.Close()
			for backfillRows.Next() {
				var h models.Hashtag
				var recentCount int
				if err := backfillRows.Scan(
					&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
					&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt, &recentCount,
				); err == nil {
					h.RecentCount = recentCount
					hashtags = append(hashtags, h)
				}
			}
		}
	}

	return hashtags, nil
}

// GetFeaturedHashtags returns curated/featured hashtags
func (r *TagRepository) GetFeaturedHashtags(ctx context.Context, limit int) ([]models.Hashtag, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, name, display_name, use_count, trending_score, is_trending, is_featured, category, created_at
		FROM hashtags
		WHERE is_featured = true
		ORDER BY use_count DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hashtags []models.Hashtag
	for rows.Next() {
		var h models.Hashtag
		err := rows.Scan(
			&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
			&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		hashtags = append(hashtags, h)
	}

	return hashtags, nil
}

// ============================================================================
// Hashtag Follows
// ============================================================================

// FollowHashtag adds a user to a hashtag's followers
func (r *TagRepository) FollowHashtag(ctx context.Context, userID, hashtagID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO hashtag_follows (user_id, hashtag_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, userID, hashtagID)
	return err
}

// UnfollowHashtag removes a user from a hashtag's followers
func (r *TagRepository) UnfollowHashtag(ctx context.Context, userID, hashtagID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM hashtag_follows WHERE user_id = $1 AND hashtag_id = $2`, userID, hashtagID)
	return err
}

// GetFollowedHashtags returns hashtags followed by a user
func (r *TagRepository) GetFollowedHashtags(ctx context.Context, userID uuid.UUID) ([]models.Hashtag, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT h.id, h.name, h.display_name, h.use_count, h.trending_score, h.is_trending, h.is_featured, h.category, h.created_at
		FROM hashtags h
		JOIN hashtag_follows hf ON h.id = hf.hashtag_id
		WHERE hf.user_id = $1
		ORDER BY h.name
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hashtags []models.Hashtag
	for rows.Next() {
		var h models.Hashtag
		err := rows.Scan(
			&h.ID, &h.Name, &h.DisplayName, &h.UseCount,
			&h.TrendingScore, &h.IsTrending, &h.IsFeatured, &h.Category, &h.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		hashtags = append(hashtags, h)
	}

	return hashtags, nil
}

// IsFollowingHashtag checks if a user is following a hashtag
func (r *TagRepository) IsFollowingHashtag(ctx context.Context, userID, hashtagID uuid.UUID) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM hashtag_follows WHERE user_id = $1 AND hashtag_id = $2)
	`, userID, hashtagID).Scan(&exists)
	return exists, err
}

// ============================================================================
// Mentions
// ============================================================================

// LinkMentionsToPost extracts @mentions from text and links them to a post
func (r *TagRepository) LinkMentionsToPost(ctx context.Context, postID uuid.UUID, text string) ([]uuid.UUID, error) {
	mentions := extractMentions(text)
	if len(mentions) == 0 {
		return nil, nil
	}

	var mentionedUserIDs []uuid.UUID

	for _, handle := range mentions {
		var userID uuid.UUID
		err := r.pool.QueryRow(ctx, `SELECT id FROM profiles WHERE handle = $1`, handle).Scan(&userID)
		if err != nil {
			continue // User not found
		}

		_, err = r.pool.Exec(ctx, `
			INSERT INTO post_mentions (post_id, mentioned_user_id)
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, postID, userID)
		if err == nil {
			mentionedUserIDs = append(mentionedUserIDs, userID)
		}
	}

	return mentionedUserIDs, nil
}

// GetMentionsForPost returns all mentioned users in a post
func (r *TagRepository) GetMentionsForPost(ctx context.Context, postID uuid.UUID) ([]models.Profile, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT p.id, p.handle, p.display_name, p.avatar_url, p.is_verified
		FROM profiles p
		JOIN post_mentions pm ON p.id = pm.mentioned_user_id
		WHERE pm.post_id = $1
	`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []models.Profile
	for rows.Next() {
		var p models.Profile
		if err := rows.Scan(&p.ID, &p.Handle, &p.DisplayName, &p.AvatarURL, &p.IsVerified); err != nil {
			return nil, err
		}
		profiles = append(profiles, p)
	}

	return profiles, nil
}

// ============================================================================
// Suggested Users (Discover)
// ============================================================================

// GetSuggestedUsers returns suggested users for the discover page
func (r *TagRepository) GetSuggestedUsers(ctx context.Context, userID string, limit int) ([]models.SuggestedUser, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT 
			p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.is_verified, p.is_official,
			su.reason, su.category, su.score,
			(SELECT COUNT(*) FROM follows WHERE following_id = p.id AND status = 'accepted') as follower_count
		FROM suggested_users su
		JOIN profiles p ON su.user_id = p.id
		WHERE su.is_active = true
		AND p.id != $1::uuid
		AND NOT EXISTS (SELECT 1 FROM follows WHERE follower_id = $1::uuid AND following_id = p.id)
		ORDER BY su.score DESC, p.is_verified DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []models.SuggestedUser
	for rows.Next() {
		var u models.SuggestedUser
		err := rows.Scan(
			&u.ID, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.Bio, &u.IsVerified, &u.IsOfficial,
			&u.Reason, &u.Category, &u.Score, &u.FollowerCount,
		)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}

	return users, nil
}

// GetPopularCreators returns popular users for the discover page
func (r *TagRepository) GetPopularCreators(ctx context.Context, userID string, limit int) ([]models.Profile, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT 
			p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.is_verified, p.is_official,
			(SELECT COUNT(*) FROM follows WHERE following_id = p.id AND status = 'accepted') as follower_count
		FROM profiles p
		WHERE p.id != $1::uuid
		AND p.is_official = false
		AND NOT EXISTS (SELECT 1 FROM follows WHERE follower_id = $1::uuid AND following_id = p.id)
		ORDER BY (SELECT COUNT(*) FROM follows WHERE following_id = p.id AND status = 'accepted') DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []models.Profile
	for rows.Next() {
		var p models.Profile
		var followerCount int
		err := rows.Scan(
			&p.ID, &p.Handle, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.IsVerified, &p.IsOfficial, &followerCount,
		)
		if err != nil {
			return nil, err
		}
		p.FollowerCount = &followerCount
		profiles = append(profiles, p)
	}

	return profiles, nil
}

// ============================================================================
// Trending Calculation (for scheduled jobs)
// ============================================================================

// RefreshTrendingScores recalculates trending scores for all hashtags
func (r *TagRepository) RefreshTrendingScores(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `SELECT calculate_trending_scores()`)
	return err
}

// ============================================================================
// Helpers
// ============================================================================

var hashtagRegex = regexp.MustCompile(`#(\w+)`)
var mentionRegex = regexp.MustCompile(`@(\w+)`)

func extractHashtags(text string) []string {
	matches := hashtagRegex.FindAllStringSubmatch(text, -1)
	seen := make(map[string]bool)
	var hashtags []string

	for _, match := range matches {
		if len(match) > 1 {
			tag := match[1]
			if !seen[strings.ToLower(tag)] {
				seen[strings.ToLower(tag)] = true
				hashtags = append(hashtags, tag)
			}
		}
	}

	return hashtags
}

func extractMentions(text string) []string {
	matches := mentionRegex.FindAllStringSubmatch(text, -1)
	seen := make(map[string]bool)
	var mentions []string

	for _, match := range matches {
		if len(match) > 1 {
			handle := strings.ToLower(match[1])
			if !seen[handle] {
				seen[handle] = true
				mentions = append(mentions, handle)
			}
		}
	}

	return mentions
}
