// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"github.com/rs/zerolog/log"
)

type PostRepository struct {
	pool *pgxpool.Pool
}

func NewPostRepository(pool *pgxpool.Pool) *PostRepository {
	return &PostRepository{pool: pool}
}

func (r *PostRepository) Pool() *pgxpool.Pool {
	return r.pool
}

func (r *PostRepository) CreatePost(ctx context.Context, post *models.Post) error {
	// Beacons are fully anonymous — author_id is never stored.
	// Confidence is set by the handler; community vouches drive it up from 0.3.
	// Non-beacon posts retain author_id for all standard operations.

	// authorIDArg is nil for beacons so the DB column stores NULL.
	var authorIDArg interface{}
	if !post.IsBeacon {
		authorIDArg = post.AuthorID
	}

	query := `
		INSERT INTO public.posts (
			author_id, category_id, body, status, tone_label, cis_score,
			image_url, video_url, thumbnail_url, duration_ms, body_format, background_id, tags,
			is_beacon, beacon_type, location, confidence_score,
			is_active_beacon, allow_chain, chain_parent_id, visibility, expires_at,
			is_nsfw, nsfw_reason,
			severity, incident_status, radius, overlay_json, audio_overlay_url
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
			$14, $15,
			CASE WHEN ($16::double precision) IS NOT NULL AND ($17::double precision) IS NOT NULL
				 THEN ST_SetSRID(ST_MakePoint(($17::double precision), ($16::double precision)), 4326)::geography
				 ELSE NULL END,
			$18, $19, $20, $21, $22, $23,
			$24, $25,
			$26, $27, $28, $29, $30
		) RETURNING id, created_at
	`

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	err = tx.QueryRow(ctx, query,
		authorIDArg, post.CategoryID, post.Body, post.Status, post.ToneLabel, post.CISScore,
		post.ImageURL, post.VideoURL, post.ThumbnailURL, post.DurationMS, post.BodyFormat, post.BackgroundID, post.Tags,
		post.IsBeacon, post.BeaconType, post.Lat, post.Long, post.Confidence,
		post.IsActiveBeacon, post.AllowChain, post.ChainParentID, post.Visibility, post.ExpiresAt,
		post.IsNSFW, post.NSFWReason,
		post.Severity, post.IncidentStatus, post.Radius, post.OverlayJSON, post.AudioOverlayURL,
	).Scan(&post.ID, &post.CreatedAt)

	if err != nil {
		return fmt.Errorf("failed to create post: %w", err)
	}

	// Initialize metrics
	if _, err := tx.Exec(ctx, "INSERT INTO public.post_metrics (post_id) VALUES ($1)", post.ID); err != nil {
		return fmt.Errorf("failed to initialize post metrics: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit post transaction: %w", err)
	}

	return nil
}

func (r *PostRepository) GetRandomSponsoredPost(ctx context.Context, userID string) (*models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, COALESCE(p.image_url, ''), COALESCE(p.video_url, ''), COALESCE(p.thumbnail_url, ''), COALESCE(p.duration_ms, 0), COALESCE(p.tags, ARRAY[]::text[]), p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			FALSE as is_liked,
			sp.advertiser_name
		FROM public.sponsored_posts sp
		JOIN public.posts p ON sp.post_id = p.id
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		WHERE p.deleted_at IS NULL AND p.status = 'active'
		  AND (
		      p.category_id IS NULL OR EXISTS (
		          SELECT 1 FROM public.user_category_settings ucs 
		          WHERE ucs.user_id = CASE WHEN $1::text != '' THEN $1::text::uuid ELSE NULL END AND ucs.category_id = p.category_id AND ucs.enabled = true
		      )
		  )
		ORDER BY RANDOM()
		LIMIT 1
	`
	var p models.Post
	var advertiserName string
	err := r.pool.QueryRow(ctx, query, userID).Scan(
		&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
		&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
		&p.LikeCount, &p.CommentCount, &p.IsLiked,
		&advertiserName,
	)
	if err != nil {
		return nil, err
	}
	p.Author = &models.AuthorProfile{
		ID:          p.AuthorID,
		Handle:      p.AuthorHandle,
		DisplayName: advertiserName, // Display advertiser name for ads
		AvatarURL:   p.AuthorAvatarURL,
	}
	p.IsSponsored = true
	return &p, nil
}

func (r *PostRepository) GetFeed(ctx context.Context, userID string, categorySlug string, hasVideo bool, limit int, offset int, showNSFW bool) ([]models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			CASE
				WHEN COALESCE(p.video_url, '') <> '' THEN p.video_url
				WHEN COALESCE(p.image_url, '') ILIKE '%.mp4' THEN p.image_url
				ELSE ''
			END AS resolved_video_url,
			COALESCE(NULLIF(p.thumbnail_url, ''), p.image_url, '') AS resolved_thumbnail_url,
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]),
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN ($4::text) != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $4::text::uuid) ELSE FALSE END as is_liked,
			p.allow_chain, p.visibility,
			COALESCE((SELECT jsonb_object_agg(emoji, count) FROM (SELECT emoji, COUNT(*) as count FROM public.post_reactions WHERE post_id = p.id GROUP BY emoji) r), '{}'::jsonb) as reaction_counts,
			CASE WHEN ($4::text) != '' THEN COALESCE((SELECT jsonb_agg(emoji) FROM public.post_reactions WHERE post_id = p.id AND user_id = $4::text::uuid), '[]'::jsonb) ELSE '[]'::jsonb END as my_reactions,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
			p.overlay_json,
			COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.categories c ON p.category_id = c.id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE p.deleted_at IS NULL AND p.status = 'active'
		  AND p.chain_parent_id IS NULL
		  AND COALESCE(p.is_beacon, FALSE) = FALSE
		  AND (
		      -- Author always sees their own posts
		      p.author_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		      OR (
		          -- Profile-level privacy: private profiles require accepted follow
		          (pr.is_private = FALSE OR EXISTS (
		              SELECT 1 FROM public.follows f
		              WHERE f.follower_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		                AND f.following_id = p.author_id AND f.status = 'accepted'
		          ))
		          AND
		          -- Post-level visibility
		          (
		              COALESCE(p.visibility, 'public') = 'public'
		              OR (p.visibility = 'followers' AND EXISTS (
		                  SELECT 1 FROM public.follows f2
		                  WHERE f2.follower_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		                    AND f2.following_id = p.author_id AND f2.status = 'accepted'
		              ))
		              OR (p.visibility = 'circle' AND EXISTS (
		                  SELECT 1 FROM public.circle_members cm
		                  WHERE cm.user_id = p.author_id
		                    AND cm.member_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		              ))
		              OR (p.visibility = 'neighborhood' AND EXISTS (
		                  SELECT 1 FROM public.profiles viewer_pr
		                  WHERE viewer_pr.id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		                    AND viewer_pr.home_neighborhood_id IS NOT NULL
		                    AND viewer_pr.home_neighborhood_id = pr.home_neighborhood_id
		              ))
		          )
		      )
		  )
		  AND NOT public.has_block_between(p.author_id, CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END)
		  AND ($4::text = '' OR NOT EXISTS (
		      SELECT 1 FROM public.post_hides ph
		      WHERE ph.post_id = p.id AND ph.user_id = $4::text::uuid
		  ))
		  AND ($3 = FALSE OR (COALESCE(p.video_url, '') <> '' OR (COALESCE(p.image_url, '') ILIKE '%.mp4')))
		  AND ($5 = '' OR c.slug = $5)
		  AND (
		      COALESCE(p.is_nsfw, FALSE) = FALSE
		      OR (
		          $6 = TRUE
		          AND (
		              p.author_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		              OR EXISTS (
		                  SELECT 1 FROM public.follows f
		                  WHERE f.follower_id = CASE WHEN $4::text != '' THEN $4::text::uuid ELSE NULL END
		                    AND f.following_id = p.author_id AND f.status = 'accepted'
		              )
		          )
		      )
		  )
		ORDER BY p.created_at DESC 
		LIMIT $1 OFFSET $2
	`
	rows, err := r.pool.Query(ctx, query, limit, offset, hasVideo, userID, categorySlug, showNSFW)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	posts := []models.Post{}
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.AllowChain, &p.Visibility, &p.Reactions, &p.MyReactions,
			&p.IsNSFW, &p.NSFWReason,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.OverlayJSON,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) GetCategories(ctx context.Context) ([]models.Category, error) {
	query := `SELECT id, slug, name, description, is_sensitive, created_at FROM public.categories ORDER BY name ASC`
	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var categories []models.Category
	for rows.Next() {
		var c models.Category
		err := rows.Scan(&c.ID, &c.Slug, &c.Name, &c.Description, &c.IsSensitive, &c.CreatedAt)
		if err != nil {
			return nil, err
		}
		categories = append(categories, c)
	}
	return categories, nil
}

func (r *PostRepository) GetPostsByAuthor(ctx context.Context, authorID string, viewerID string, limit int, offset int, onlyChains bool, showNSFW bool) ([]models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			CASE
				WHEN COALESCE(p.video_url, '') <> '' THEN p.video_url
				WHEN COALESCE(p.image_url, '') ILIKE '%.mp4' THEN p.image_url
				ELSE ''
			END AS resolved_video_url,
			COALESCE(NULLIF(p.thumbnail_url, ''), p.image_url, '') AS resolved_thumbnail_url,
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]),
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN $4 != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $4::uuid) ELSE FALSE END as is_liked,
			p.allow_chain, p.visibility,
			COALESCE((SELECT jsonb_object_agg(emoji, count) FROM (SELECT emoji, COUNT(*) as count FROM public.post_reactions WHERE post_id = p.id GROUP BY emoji) r), '{}'::jsonb) as reaction_counts,
			CASE WHEN ($4::text) != '' THEN COALESCE((SELECT jsonb_agg(emoji) FROM public.post_reactions WHERE post_id = p.id AND user_id = $4::text::uuid), '[]'::jsonb) ELSE '[]'::jsonb END as my_reactions,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
			COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE p.author_id = $1::uuid AND p.deleted_at IS NULL AND p.status = 'active'
		  AND p.is_beacon = FALSE
		  AND (
		      -- Author always sees their own posts
		      p.author_id = CASE WHEN $4 != '' THEN $4::uuid ELSE NULL END
		      OR (
		          -- Profile-level privacy: private profiles require accepted follow
		          (pr.is_private = FALSE OR EXISTS (
		              SELECT 1 FROM public.follows f
		              WHERE f.follower_id = CASE WHEN $4 != '' THEN $4::uuid ELSE NULL END
		                AND f.following_id = p.author_id AND f.status = 'accepted'
		          ))
		          AND
		          -- Post-level visibility
		          (
		              COALESCE(p.visibility, 'public') = 'public'
		              OR (p.visibility = 'followers' AND EXISTS (
		                  SELECT 1 FROM public.follows f2
		                  WHERE f2.follower_id = CASE WHEN $4 != '' THEN $4::uuid ELSE NULL END
		                    AND f2.following_id = p.author_id AND f2.status = 'accepted'
		              ))
		              OR (p.visibility = 'circle' AND EXISTS (
		                  SELECT 1 FROM public.circle_members cm
		                  WHERE cm.user_id = p.author_id
		                    AND cm.member_id = CASE WHEN $4 != '' THEN $4::uuid ELSE NULL END
		              ))
		              OR (p.visibility = 'neighborhood' AND EXISTS (
		                  SELECT 1 FROM public.profiles viewer_pr
		                  WHERE viewer_pr.id = CASE WHEN $4 != '' THEN $4::uuid ELSE NULL END
		                    AND viewer_pr.home_neighborhood_id IS NOT NULL
		                    AND viewer_pr.home_neighborhood_id = pr.home_neighborhood_id
		              ))
		          )
		      )
		  )
		  AND (($5 = FALSE AND p.chain_parent_id IS NULL) OR ($5 = TRUE AND p.chain_parent_id IS NOT NULL))
		  AND (
		      COALESCE(p.is_nsfw, FALSE) = FALSE
		      OR $6 = TRUE
		  )
		ORDER BY p.created_at DESC 
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, authorID, limit, offset, viewerID, onlyChains, showNSFW)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked, &p.AllowChain, &p.Visibility, &p.Reactions, &p.MyReactions,
			&p.IsNSFW, &p.NSFWReason,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) GetPostByID(ctx context.Context, postID string, userID string, showNSFW ...bool) (*models.Post, error) {
	log.Error().Str("postID", postID).Str("userID", userID).Msg("TEST: GetPostByID called")
	filterNSFW := true
	if len(showNSFW) > 0 && showNSFW[0] {
		filterNSFW = false
	}
	query := `
		SELECT 
			p.id,
			p.author_id,
			p.category_id,
			p.body,
			COALESCE(p.image_url, ''),
			CASE
				WHEN COALESCE(p.video_url, '') <> '' THEN p.video_url
				WHEN COALESCE(p.image_url, '') ILIKE '%.mp4' THEN p.image_url
				ELSE ''
			END AS resolved_video_url,
			COALESCE(NULLIF(p.thumbnail_url, ''), p.image_url, '') AS resolved_thumbnail_url,
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]),
			p.created_at,
			p.chain_parent_id,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN $2 != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $2::uuid) ELSE FALSE END as is_liked,
			p.allow_chain, p.visibility,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
			p.overlay_json,
			COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE p.id = $1::uuid AND p.deleted_at IS NULL
		  AND (
		      -- Author always sees their own posts
		      p.author_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		      OR (
		          -- Profile-level privacy: private profiles require accepted follow
		          (pr.is_private = FALSE OR EXISTS (
		              SELECT 1 FROM public.follows f
		              WHERE f.follower_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		                AND f.following_id = p.author_id AND f.status = 'accepted'
		          ))
		          AND
		          -- Post-level visibility
		          (
		              COALESCE(p.visibility, 'public') = 'public'
		              OR (p.visibility = 'followers' AND EXISTS (
		                  SELECT 1 FROM public.follows f2
		                  WHERE f2.follower_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		                    AND f2.following_id = p.author_id AND f2.status = 'accepted'
		              ))
		              OR (p.visibility = 'circle' AND EXISTS (
		                  SELECT 1 FROM public.circle_members cm
		                  WHERE cm.user_id = p.author_id
		                    AND cm.member_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		              ))
		              OR (p.visibility = 'neighborhood' AND EXISTS (
		                  SELECT 1 FROM public.profiles viewer_pr
		                  WHERE viewer_pr.id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		                    AND viewer_pr.home_neighborhood_id IS NOT NULL
		                    AND viewer_pr.home_neighborhood_id = pr.home_neighborhood_id
		              ))
		          )
		      )
		  )
		  AND NOT public.has_block_between(p.author_id, CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END)
		  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $3 = FALSE)
	`
	var p models.Post
	err := r.pool.QueryRow(ctx, query, postID, userID, filterNSFW).Scan(
		&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
		&p.ChainParentID,
		&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
		&p.LikeCount, &p.CommentCount, &p.IsLiked,
		&p.AllowChain, &p.Visibility,
		&p.IsNSFW, &p.NSFWReason,
		&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
		&p.OverlayJSON,
		&p.AuthorTrustTier,
	)
	if err != nil {
		return nil, err
	}
	p.Author = &models.AuthorProfile{
		ID:          p.AuthorID,
		Handle:      p.AuthorHandle,
		DisplayName: p.AuthorDisplayName,
		AvatarURL:   p.AuthorAvatarURL,
		TrustTier:   p.AuthorTrustTier,
	}

	// Always load reactions (counts and users), but only load user-specific reactions if userID is provided
	counts, myReactions, reactionUsers, err := r.LoadReactionsForPost(ctx, postID, userID)
	if err != nil {
		// Log error but don't fail the post loading
		fmt.Printf("Warning: failed to load reactions for post %s: %v\n", postID, err)
	} else {
		p.Reactions = counts
		p.MyReactions = myReactions
		p.ReactionUsers = reactionUsers
		log.Error().Str("postID", postID).Interface("counts", counts).Interface("myReactions", myReactions).Msg("TEST: Assigned reactions to post")
	}

	return &p, nil
}

func (r *PostRepository) UpdatePost(ctx context.Context, postID string, authorID string, body string) error {
	query := `UPDATE public.posts SET body = $1, edited_at = NOW() WHERE id = $2::uuid AND author_id = $3::uuid AND deleted_at IS NULL`
	res, err := r.pool.Exec(ctx, query, body, postID, authorID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("post not found or unauthorized")
	}
	return nil
}

func (r *PostRepository) DeletePost(ctx context.Context, postID string, authorID string) error {
	query := `UPDATE public.posts SET deleted_at = NOW() WHERE id = $1::uuid AND author_id = $2::uuid AND deleted_at IS NULL`
	res, err := r.pool.Exec(ctx, query, postID, authorID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("post not found or unauthorized")
	}
	return nil
}

func (r *PostRepository) PinPost(ctx context.Context, postID string, authorID string, pinned bool) error {
	var val *time.Time
	if pinned {
		t := time.Now()
		val = &t
	}
	query := `UPDATE public.posts SET pinned_at = $1 WHERE id = $2::uuid AND author_id = $3::uuid AND deleted_at IS NULL`
	res, err := r.pool.Exec(ctx, query, val, postID, authorID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("post not found or unauthorized")
	}
	return nil
}

func (r *PostRepository) UpdateVisibility(ctx context.Context, postID string, authorID string, visibility string) error {
	query := `UPDATE public.posts SET visibility = $1 WHERE id = $2::uuid AND author_id = $3::uuid AND deleted_at IS NULL`
	res, err := r.pool.Exec(ctx, query, visibility, postID, authorID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("post not found or unauthorized")
	}
	return nil
}

func (r *PostRepository) LikePost(ctx context.Context, postID string, userID string) error {
	query := `
		WITH inserted AS (
			INSERT INTO public.post_likes (post_id, user_id)
			VALUES ($1::uuid, $2::uuid)
			ON CONFLICT DO NOTHING
			RETURNING 1
		)
		UPDATE public.post_metrics
		SET like_count = like_count + (SELECT COUNT(*) FROM inserted)
		WHERE post_id = $1::uuid
	`
	_, err := r.pool.Exec(ctx, query, postID, userID)
	return err
}

func (r *PostRepository) UnlikePost(ctx context.Context, postID string, userID string) error {
	query := `
		WITH deleted AS (
			DELETE FROM public.post_likes
			WHERE post_id = $1::uuid AND user_id = $2::uuid
			RETURNING 1
		)
		UPDATE public.post_metrics
		SET like_count = GREATEST(like_count - (SELECT COUNT(*) FROM deleted), 0)
		WHERE post_id = $1::uuid
	`
	_, err := r.pool.Exec(ctx, query, postID, userID)
	return err
}

// HidePost records a "Not Interested" signal.
// Denormalises author_id so feeds can suppress prolific-hide authors without a JOIN.
func (r *PostRepository) HidePost(ctx context.Context, postID, userID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO public.post_hides (user_id, post_id, author_id)
		SELECT $2::uuid, $1::uuid, author_id
		FROM public.posts WHERE id = $1::uuid
		ON CONFLICT (user_id, post_id) DO NOTHING
	`, postID, userID)
	return err
}

func (r *PostRepository) SavePost(ctx context.Context, postID string, userID string) error {
	query := `
		WITH inserted AS (
			INSERT INTO public.post_saves (post_id, user_id)
			VALUES ($1::uuid, $2::uuid)
			ON CONFLICT DO NOTHING
			RETURNING 1
		)
		UPDATE public.post_metrics
		SET save_count = save_count + (SELECT COUNT(*) FROM inserted)
		WHERE post_id = $1::uuid
	`
	_, err := r.pool.Exec(ctx, query, postID, userID)
	return err
}

func (r *PostRepository) UnsavePost(ctx context.Context, postID string, userID string) error {
	query := `
		WITH deleted AS (
			DELETE FROM public.post_saves
			WHERE post_id = $1::uuid AND user_id = $2::uuid
			RETURNING 1
		)
		UPDATE public.post_metrics
		SET save_count = GREATEST(save_count - (SELECT COUNT(*) FROM deleted), 0)
		WHERE post_id = $1::uuid
	`
	_, err := r.pool.Exec(ctx, query, postID, userID)
	return err
}

func (r *PostRepository) CreateComment(ctx context.Context, comment *models.Comment) error {
	query := `
		INSERT INTO public.comments (post_id, author_id, body, status, created_at)
		VALUES ($1::uuid, $2, $3, $4, NOW())
		RETURNING id, created_at
	`
	err := r.pool.QueryRow(ctx, query, comment.PostID, comment.AuthorID, comment.Body, comment.Status).Scan(&comment.ID, &comment.CreatedAt)
	if err != nil {
		return err
	}

	// Increment comment count in metrics
	_, _ = r.pool.Exec(ctx, "UPDATE public.post_metrics SET comment_count = comment_count + 1 WHERE post_id = $1::uuid", comment.PostID)

	return nil
}

func (r *PostRepository) GetNearbyBeacons(ctx context.Context, lat float64, long float64, radius int) ([]models.Post, error) {
	// Beacons are anonymous: we never expose author info to the API.
	// author_id is stored internally for abuse tracking only.
	query := `
		SELECT 
			p.id, p.category_id, p.body, COALESCE(p.image_url, ''), p.tags, p.created_at,
			p.beacon_type, p.confidence_score, p.is_active_beacon, COALESCE(p.is_priority, FALSE) as is_priority,
			ST_Y(p.location::geometry) as lat, ST_X(p.location::geometry) as long,
			COALESCE(p.severity, 'medium') as severity,
			COALESCE(p.incident_status, 'active') as incident_status,
			COALESCE(p.radius, 500) as radius,
			COALESCE((SELECT COUNT(*) FROM beacon_votes bv WHERE bv.beacon_id = p.id AND bv.vote_type = 'vouch'), 0) as vouch_count,
			COALESCE((SELECT COUNT(*) FROM beacon_votes bv WHERE bv.beacon_id = p.id AND bv.vote_type = 'report'), 0) as report_count,
			ST_Distance(p.location::geography, ST_SetSRID(ST_Point($2, $1), 4326)::geography) AS distance_meters
		FROM public.posts p
		WHERE p.is_beacon = true
		  AND ST_DWithin(p.location, ST_SetSRID(ST_Point($2, $1), 4326)::geography, $3)
		  AND p.status = 'active'
		  AND COALESCE(p.incident_status, 'active') = 'active'
		ORDER BY p.is_priority DESC, p.created_at DESC
	`
	rows, err := r.pool.Query(ctx, query, lat, long, radius)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var beacons []models.Post
	for rows.Next() {
		var p models.Post
		var vouchCount, reportCount int
		err := rows.Scan(
			&p.ID, &p.CategoryID, &p.Body, &p.ImageURL, &p.Tags, &p.CreatedAt,
			&p.BeaconType, &p.Confidence, &p.IsActiveBeacon, &p.IsPriority, &p.Lat, &p.Long,
			&p.Severity, &p.IncidentStatus, &p.Radius,
			&vouchCount, &reportCount, &p.DistanceMeters,
		)
		if err != nil {
			return nil, err
		}
		// Return anonymous author placeholder — no real user info
		p.AuthorHandle = "Anonymous"
		p.AuthorDisplayName = "Anonymous"
		p.AuthorAvatarURL = ""
		p.Author = &models.AuthorProfile{
			Handle:      "Anonymous",
			DisplayName: "Anonymous",
			AvatarURL:   "",
		}
		p.LikeCount = vouchCount     // repurpose like_count as vouch_count for beacon API
		p.CommentCount = reportCount // repurpose comment_count as report_count for beacon API
		beacons = append(beacons, p)
	}
	return beacons, nil
}

func (r *PostRepository) GetSavedPosts(ctx context.Context, userID string, limit int, offset int, showNSFW bool) ([]models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			COALESCE(p.video_url, ''),
			COALESCE(p.thumbnail_url, ''),
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]), 
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $1::uuid) as is_liked,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
		COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.post_saves ps
		JOIN public.posts p ON ps.post_id = p.id
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE ps.user_id = $1::uuid AND p.deleted_at IS NULL
		  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $4 = TRUE)
		ORDER BY ps.created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, userID, limit, offset, showNSFW)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.IsNSFW, &p.NSFWReason,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) GetLikedPosts(ctx context.Context, userID string, limit int, offset int, showNSFW bool) ([]models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			COALESCE(p.video_url, ''),
			COALESCE(p.thumbnail_url, ''),
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]), 
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			TRUE as is_liked,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
		COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.post_likes pl
		JOIN public.posts p ON pl.post_id = p.id
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE pl.user_id = $1::uuid AND p.deleted_at IS NULL
		  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $4 = TRUE)
		ORDER BY pl.created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, query, userID, limit, offset, showNSFW)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.IsNSFW, &p.NSFWReason,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) GetPostChain(ctx context.Context, rootID string, showNSFW bool) ([]models.Post, error) {
	// Recursive CTE to get the chain
	query := `
		WITH RECURSIVE object_chain AS (
			-- Anchor member: select the root post
			SELECT 
				p.id, p.author_id, p.category_id, p.body, 
				COALESCE(p.image_url, '') as image_url,
				COALESCE(p.video_url, '') as video_url,
				COALESCE(p.thumbnail_url, '') as thumbnail_url,
				COALESCE(p.duration_ms, 0) as duration_ms,
				COALESCE(p.tags, ARRAY[]::text[]) as tags, 
				p.created_at, p.chain_parent_id,
				pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
				COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
				COALESCE(p.is_nsfw, FALSE) as is_nsfw, COALESCE(p.nsfw_reason, '') as nsfw_reason,
				1 as level
			FROM public.posts p
			JOIN public.profiles pr ON p.author_id = pr.id
			LEFT JOIN public.post_metrics m ON p.id = m.post_id
			WHERE p.id = $1::uuid AND p.deleted_at IS NULL
			  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $2 = TRUE)

			UNION ALL

			-- Recursive member: select children
			SELECT 
				p.id, p.author_id, p.category_id, p.body, 
				COALESCE(p.image_url, '') as image_url,
				COALESCE(p.video_url, '') as video_url,
				COALESCE(p.thumbnail_url, '') as thumbnail_url,
				COALESCE(p.duration_ms, 0) as duration_ms,
				COALESCE(p.tags, ARRAY[]::text[]) as tags, 
				p.created_at, p.chain_parent_id,
				pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
				COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
				COALESCE(p.is_nsfw, FALSE) as is_nsfw, COALESCE(p.nsfw_reason, '') as nsfw_reason,
				oc.level + 1
			FROM public.posts p
			JOIN public.profiles pr ON p.author_id = pr.id
			LEFT JOIN public.post_metrics m ON p.id = m.post_id
			JOIN object_chain oc ON p.chain_parent_id = oc.id
			WHERE p.deleted_at IS NULL
			  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $2 = TRUE)
		),
		comments_chain AS (
			SELECT
				c.id,
				c.author_id,
				NULL::uuid as category_id,
				c.body,
				'' as image_url,
				'' as video_url,
				'' as thumbnail_url,
				0 as duration_ms,
				ARRAY[]::text[] as tags,
				c.created_at,
				c.post_id as chain_parent_id,
				pr.handle as author_handle,
				pr.display_name as author_display_name,
				COALESCE(pr.avatar_url, '') as author_avatar_url,
				0 as like_count,
				0 as comment_count,
				FALSE as is_nsfw, '' as nsfw_reason,
				2 as level
			FROM public.comments c
			JOIN public.profiles pr ON c.author_id = pr.id
			WHERE c.deleted_at IS NULL
				AND c.post_id IN (SELECT id FROM object_chain)
		)
		SELECT 
			oc.id, oc.author_id, oc.category_id, oc.body, oc.image_url, oc.video_url, oc.thumbnail_url, oc.duration_ms, oc.tags, oc.created_at, oc.chain_parent_id, oc.level,
			oc.author_handle, oc.author_display_name, oc.author_avatar_url,
			oc.like_count, oc.comment_count, oc.is_nsfw, oc.nsfw_reason, FALSE as is_liked,
			COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM object_chain oc
		LEFT JOIN public.trust_state t ON oc.author_id = t.user_id
		UNION ALL
		SELECT
			cc.id, cc.author_id, cc.category_id, cc.body, cc.image_url, cc.video_url, cc.thumbnail_url, cc.duration_ms, cc.tags, cc.created_at, cc.chain_parent_id, cc.level,
			cc.author_handle, cc.author_display_name, cc.author_avatar_url,
			cc.like_count, cc.comment_count, cc.is_nsfw, cc.nsfw_reason, FALSE as is_liked,
			'new_user'::text as author_trust_tier
		FROM comments_chain cc
		ORDER BY level ASC, created_at ASC;
	`
	rows, err := r.pool.Query(ctx, query, rootID, showNSFW)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		var level int
		// Fixed: Added Scan for &p.ChainParentID
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt, &p.ChainParentID, &level,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsNSFW, &p.NSFWReason, &p.IsLiked,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) SearchPosts(ctx context.Context, query string, viewerID string, limit int) ([]models.Post, error) {
	// Using % operator for trigram fuzzy match on body
	sql := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			COALESCE(p.video_url, ''),
			COALESCE(p.thumbnail_url, ''),
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]), 
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN $3 != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $3::uuid) ELSE FALSE END as is_liked,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
		COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE (
			p.body % $1 OR p.body ILIKE '%' || $1 || '%'
			OR $1 = ANY(p.tags)
		) 
		  AND p.deleted_at IS NULL AND p.status = 'active'
		  AND COALESCE(p.is_nsfw, FALSE) = FALSE
		  AND (
		      -- Author always sees their own posts
		      p.author_id = CASE WHEN $3 != '' THEN $3::uuid ELSE NULL END
		      OR (
		          -- Profile-level privacy: private profiles require accepted follow
		          (pr.is_private = FALSE OR EXISTS (
		              SELECT 1 FROM public.follows f
		              WHERE f.follower_id = CASE WHEN $3 != '' THEN $3::uuid ELSE NULL END
		                AND f.following_id = p.author_id AND f.status = 'accepted'
		          ))
		          AND
		          -- Post-level visibility (only_me excluded — never appears in search)
		          (
		              COALESCE(p.visibility, 'public') = 'public'
		              OR (p.visibility = 'followers' AND EXISTS (
		                  SELECT 1 FROM public.follows f2
		                  WHERE f2.follower_id = CASE WHEN $3 != '' THEN $3::uuid ELSE NULL END
		                    AND f2.following_id = p.author_id AND f2.status = 'accepted'
		              ))
		              OR (p.visibility = 'circle' AND EXISTS (
		                  SELECT 1 FROM public.circle_members cm
		                  WHERE cm.user_id = p.author_id
		                    AND cm.member_id = CASE WHEN $3 != '' THEN $3::uuid ELSE NULL END
		              ))
		              OR (p.visibility = 'neighborhood' AND EXISTS (
		                  SELECT 1 FROM public.profiles viewer_pr
		                  WHERE viewer_pr.id = CASE WHEN $3 != '' THEN $3::uuid ELSE NULL END
		                    AND viewer_pr.home_neighborhood_id IS NOT NULL
		                    AND viewer_pr.home_neighborhood_id = pr.home_neighborhood_id
		              ))
		          )
		      )
		  )
		ORDER BY similarity(p.body, $1) DESC, p.created_at DESC
		LIMIT $2
	`
	rows, err := r.pool.Query(ctx, sql, query, limit, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}

func (r *PostRepository) SearchTags(ctx context.Context, query string, limit int) ([]models.TagResult, error) {
	searchQuery := "%" + query + "%"
	sql := `
		SELECT tag, COUNT(*) as count
		FROM (
			SELECT unnest(tags) as tag FROM public.posts WHERE deleted_at IS NULL AND status = 'active'
		) t
		WHERE tag ILIKE $1
		GROUP BY tag
		ORDER BY count DESC
		LIMIT $2
	`
	rows, err := r.pool.Query(ctx, sql, searchQuery, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tags []models.TagResult
	for rows.Next() {
		var t models.TagResult
		if err := rows.Scan(&t.Tag, &t.Count); err != nil {
			return nil, err
		}
		tags = append(tags, t)
	}
	return tags, nil
}

func (r *PostRepository) VouchBeacon(ctx context.Context, beaconID string, userID string) error {
	// Verify the post is a beacon
	var isBeacon bool
	err := r.pool.QueryRow(ctx, "SELECT is_beacon FROM public.posts WHERE id = $1::uuid AND deleted_at IS NULL", beaconID).Scan(&isBeacon)
	if err != nil {
		return fmt.Errorf("beacon not found: %w", err)
	}
	if !isBeacon {
		return fmt.Errorf("post is not a beacon")
	}

	// Insert vouch record
	query := `INSERT INTO public.beacon_vouches (beacon_id, user_id) VALUES ($1::uuid, $2::uuid) ON CONFLICT DO NOTHING`
	_, err = r.pool.Exec(ctx, query, beaconID, userID)
	if err != nil {
		return fmt.Errorf("failed to vouch for beacon: %w", err)
	}

	// Update confidence score and auto-elevate to priority when vouches >= 3
	updateQuery := `
		UPDATE public.posts
		SET confidence_score = (
			SELECT COALESCE(
				0.5 + (COUNT(*) * 0.1), -- Base 0.5 + 0.1 per vouch
				0.5
			)
			FROM public.beacon_vouches
			WHERE beacon_id = $1::uuid
		),
		is_priority = (
			(SELECT COUNT(*) FROM public.beacon_vouches WHERE beacon_id = $1::uuid) >= 3
		)
		WHERE id = $1::uuid
	`
	_, err = r.pool.Exec(ctx, updateQuery, beaconID)
	if err != nil {
		return fmt.Errorf("failed to update beacon confidence: %w", err)
	}

	return nil
}

func (r *PostRepository) ReportBeacon(ctx context.Context, beaconID string, userID string) error {
	// Verify the post is a beacon
	var isBeacon bool
	err := r.pool.QueryRow(ctx, "SELECT is_beacon FROM public.posts WHERE id = $1::uuid AND deleted_at IS NULL", beaconID).Scan(&isBeacon)
	if err != nil {
		return fmt.Errorf("beacon not found: %w", err)
	}
	if !isBeacon {
		return fmt.Errorf("post is not a beacon")
	}

	// Insert report record
	query := `INSERT INTO public.beacon_reports (beacon_id, user_id) VALUES ($1::uuid, $2::uuid) ON CONFLICT DO NOTHING`
	_, err = r.pool.Exec(ctx, query, beaconID, userID)
	if err != nil {
		return fmt.Errorf("failed to report beacon: %w", err)
	}

	// Check if beacon should be flagged based on reports
	var reportCount int
	countQuery := `SELECT COUNT(*) FROM public.beacon_reports WHERE beacon_id = $1::uuid`
	err = r.pool.QueryRow(ctx, countQuery, beaconID).Scan(&reportCount)
	if err != nil {
		return fmt.Errorf("failed to check report count: %w", err)
	}

	// Auto-flag if too many reports (threshold: 5 reports)
	if reportCount >= 5 {
		flagQuery := `UPDATE public.posts SET status = 'flagged' WHERE id = $1::uuid`
		_, err = r.pool.Exec(ctx, flagQuery, beaconID)
		if err != nil {
			return fmt.Errorf("failed to flag beacon: %w", err)
		}
	}

	return nil
}

func (r *PostRepository) RemoveBeaconVote(ctx context.Context, beaconID string, userID string) error {
	// Remove vouch if it exists
	vouchQuery := `DELETE FROM public.beacon_vouches WHERE beacon_id = $1::uuid AND user_id = $2::uuid`
	result, err := r.pool.Exec(ctx, vouchQuery, beaconID, userID)
	if err != nil {
		return fmt.Errorf("failed to remove beacon vouch: %w", err)
	}

	// Remove report if it exists
	reportQuery := `DELETE FROM public.beacon_reports WHERE beacon_id = $1::uuid AND user_id = $2::uuid`
	_, err = r.pool.Exec(ctx, reportQuery, beaconID, userID)
	if err != nil {
		return fmt.Errorf("failed to remove beacon report: %w", err)
	}

	// If a vouch was removed, update confidence score
	if result.RowsAffected() > 0 {
		updateQuery := `
			UPDATE public.posts 
			SET confidence_score = (
				SELECT COALESCE(
					0.5 + (COUNT(*) * 0.1),
					0.5
				) 
				FROM public.beacon_vouches 
				WHERE beacon_id = $1::uuid
			)
			WHERE id = $1::uuid
		`
		_, err = r.pool.Exec(ctx, updateQuery, beaconID)
		if err != nil {
			return fmt.Errorf("failed to update beacon confidence: %w", err)
		}
	}

	return nil
}

// ResolveBeacon marks a beacon as resolved or false_alarm (community action — no user linkage).
// Beacons are fully anonymous; any authenticated user can mark one resolved.
// Setting is_active_beacon=false removes it from the live map immediately.
func (r *PostRepository) ResolveBeacon(ctx context.Context, beaconID, status string) error {
	if status != "resolved" && status != "false_alarm" {
		return fmt.Errorf("invalid status: must be resolved or false_alarm")
	}

	var isBeacon bool
	err := r.pool.QueryRow(ctx,
		"SELECT is_beacon FROM public.posts WHERE id = $1::uuid AND deleted_at IS NULL",
		beaconID,
	).Scan(&isBeacon)
	if err != nil {
		return fmt.Errorf("beacon not found: %w", err)
	}
	if !isBeacon {
		return fmt.Errorf("post is not a beacon")
	}

	_, err = r.pool.Exec(ctx, `
		UPDATE public.posts
		SET incident_status = $2, is_active_beacon = false
		WHERE id = $1::uuid
	`, beaconID, status)
	if err != nil {
		return fmt.Errorf("failed to resolve beacon: %w", err)
	}
	return nil
}

// GetPostFocusContext retrieves minimal data for Focus-Context view
// Returns: Target Post, Direct Parent (if any), and Direct Children (1st layer only)
func (r *PostRepository) GetPostFocusContext(ctx context.Context, postID string, userID string, showNSFW bool) (*models.FocusContext, error) {
	log.Info().Str("postID", postID).Str("userID", userID).Msg("DEBUG: GetPostFocusContext called")

	// Get target post
	targetPost, err := r.GetPostByID(ctx, postID, userID, showNSFW)
	if err != nil {
		return nil, fmt.Errorf("failed to get target post: %w", err)
	}

	var parentPost *models.Post
	var children []models.Post
	var parentChildren []models.Post

	// Get parent post if chain_parent_id exists
	if targetPost.ChainParentID != nil {
		parentPost, err = r.GetPostByID(ctx, targetPost.ChainParentID.String(), userID, showNSFW)
		if err != nil {
			// Parent might not exist or be inaccessible - continue without it
			parentPost = nil
		}
	}

	// Get direct children (1st layer replies only)
	childrenQuery := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			CASE
				WHEN COALESCE(p.video_url, '') <> '' THEN p.video_url
				WHEN COALESCE(p.image_url, '') ILIKE '%.mp4' THEN p.image_url
				ELSE ''
			END AS resolved_video_url,
			COALESCE(NULLIF(p.thumbnail_url, ''), p.image_url, '') AS resolved_thumbnail_url,
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]),
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN $2 != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $2::uuid) ELSE FALSE END as is_liked,
			p.allow_chain, p.visibility,
			COALESCE(p.is_nsfw, FALSE) as is_nsfw,
			COALESCE(p.nsfw_reason, '') as nsfw_reason,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
		COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE p.chain_parent_id = $1::uuid AND p.deleted_at IS NULL AND p.status = 'active'
		  AND (
		      p.author_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END
		      OR pr.is_private = FALSE
		      OR EXISTS (
		          SELECT 1 FROM public.follows f 
		          WHERE f.follower_id = CASE WHEN $2 != '' THEN $2::uuid ELSE NULL END AND f.following_id = p.author_id AND f.status = 'accepted'
		      )
		  )
		  AND (COALESCE(p.is_nsfw, FALSE) = FALSE OR $3 = TRUE)
		ORDER BY p.created_at ASC
	`

	rows, err := r.pool.Query(ctx, childrenQuery, postID, userID, showNSFW)
	if err != nil {
		return nil, fmt.Errorf("failed to get children posts: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.AllowChain, &p.Visibility,
			&p.IsNSFW, &p.NSFWReason,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan child post: %w", err)
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}

		// Always load reactions for child post
		counts, myReactions, reactionUsers, err := r.LoadReactionsForPost(ctx, p.ID.String(), userID)
		if err != nil {
			// Log error but don't fail the post loading
			fmt.Printf("Warning: failed to load reactions for child post %s: %v\n", p.ID.String(), err)
		} else {
			p.Reactions = counts
			p.MyReactions = myReactions
			p.ReactionUsers = reactionUsers
		}

		children = append(children, p)
	}

	// If we have a parent, fetch its direct children (siblings + current)
	if parentPost != nil {
		siblingRows, err := r.pool.Query(ctx, childrenQuery, parentPost.ID.String(), userID, showNSFW)
		if err != nil {
			return nil, fmt.Errorf("failed to get parent children: %w", err)
		}
		defer siblingRows.Close()

		for siblingRows.Next() {
			var p models.Post
			err := siblingRows.Scan(
				&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
				&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
				&p.LikeCount, &p.CommentCount, &p.IsLiked,
				&p.AllowChain, &p.Visibility,
				&p.IsNSFW, &p.NSFWReason,
				&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
				&p.AuthorTrustTier,
			)
			if err != nil {
				return nil, fmt.Errorf("failed to scan parent child post: %w", err)
			}
			p.Author = &models.AuthorProfile{
				ID:          p.AuthorID,
				Handle:      p.AuthorHandle,
				DisplayName: p.AuthorDisplayName,
				AvatarURL:   p.AuthorAvatarURL,
				TrustTier:   p.AuthorTrustTier,
			}

			// Always load reactions for parent child post
			counts, myReactions, reactionUsers, err := r.LoadReactionsForPost(ctx, p.ID.String(), userID)
			if err != nil {
				// Log error but don't fail the post loading
				fmt.Printf("Warning: failed to load reactions for parent child post %s: %v\n", p.ID.String(), err)
			} else {
				p.Reactions = counts
				p.MyReactions = myReactions
				p.ReactionUsers = reactionUsers
			}

			parentChildren = append(parentChildren, p)
		}
	}

	return &models.FocusContext{
		TargetPost:     targetPost,
		ParentPost:     parentPost,
		Children:       children,
		ParentChildren: parentChildren,
	}, nil
}

func (r *PostRepository) ToggleReaction(ctx context.Context, postID string, userID string, emoji string) (map[string]int, []string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Check if user has any existing reaction on this post
	var existingEmoji string
	err = tx.QueryRow(
		ctx,
		`SELECT emoji FROM public.post_reactions
		 WHERE post_id = $1::uuid AND user_id = $2::uuid LIMIT 1`,
		postID,
		userID,
	).Scan(&existingEmoji)

	if err == nil {
		// User has an existing reaction, remove it
		if _, err := tx.Exec(
			ctx,
			`DELETE FROM public.post_reactions
			 WHERE post_id = $1::uuid AND user_id = $2::uuid`,
			postID,
			userID,
		); err != nil {
			return nil, nil, fmt.Errorf("failed to remove existing reaction: %w", err)
		}

		// If they're trying to add the same reaction back, just return the updated counts
		if existingEmoji == emoji {
			// Still need to calculate and return counts
			goto calculate_counts
		}
	} else if err != pgx.ErrNoRows {
		log.Error().Err(err).Str("postID", postID).Str("userID", userID).Msg("DEBUG: Failed to check existing reaction - unexpected error")
		return nil, nil, fmt.Errorf("failed to check existing reaction: %w", err)
	} else {
		log.Info().Str("postID", postID).Str("userID", userID).Msg("DEBUG: No existing reaction found (expected)")
	}

	// Add the new reaction
	if _, err := tx.Exec(
		ctx,
		`INSERT INTO public.post_reactions (post_id, user_id, emoji)
		 VALUES ($1::uuid, $2::uuid, $3)`,
		postID,
		userID,
		emoji,
	); err != nil {
		return nil, nil, fmt.Errorf("failed to add reaction: %w", err)
	}

calculate_counts:

	rows, err := tx.Query(
		ctx,
		`SELECT emoji, COUNT(*) FROM public.post_reactions
		 WHERE post_id = $1::uuid
		 GROUP BY emoji`,
		postID,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load reaction counts: %w", err)
	}
	defer rows.Close()

	counts := make(map[string]int)
	for rows.Next() {
		var reaction string
		var count int
		if err := rows.Scan(&reaction, &count); err != nil {
			return nil, nil, fmt.Errorf("failed to scan reaction counts: %w", err)
		}
		counts[reaction] = count
	}
	if rows.Err() != nil {
		return nil, nil, fmt.Errorf("failed to iterate reaction counts: %w", rows.Err())
	}

	userRows, err := tx.Query(
		ctx,
		`SELECT emoji FROM public.post_reactions
		 WHERE post_id = $1::uuid AND user_id = $2::uuid`,
		postID,
		userID,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load user reactions: %w", err)
	}
	defer userRows.Close()

	myReactions := []string{}
	for userRows.Next() {
		var reaction string
		if err := userRows.Scan(&reaction); err != nil {
			return nil, nil, fmt.Errorf("failed to scan user reactions: %w", err)
		}
		myReactions = append(myReactions, reaction)
	}
	if userRows.Err() != nil {
		return nil, nil, fmt.Errorf("failed to iterate user reactions: %w", userRows.Err())
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to commit reaction toggle: %w", err)
	}

	return counts, myReactions, nil
}

// LoadReactionsForPost loads reaction data for a specific post
func (r *PostRepository) LoadReactionsForPost(ctx context.Context, postID string, userID string) (map[string]int, []string, map[string][]string, error) {
	log.Info().Str("postID", postID).Str("userID", userID).Msg("DEBUG: Loading reactions for post")

	// Load reaction counts
	rows, err := r.pool.Query(ctx, `
		SELECT emoji, COUNT(*) FROM public.post_reactions
		 WHERE post_id = $1::uuid
		 GROUP BY emoji`,
		postID,
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to load reaction counts: %w", err)
	}
	defer rows.Close()

	counts := make(map[string]int)
	for rows.Next() {
		var reaction string
		var count int
		if err := rows.Scan(&reaction, &count); err != nil {
			return nil, nil, nil, fmt.Errorf("failed to scan reaction counts: %w", err)
		}
		counts[reaction] = count
	}
	if rows.Err() != nil {
		return nil, nil, nil, fmt.Errorf("failed to iterate reaction counts: %w", rows.Err())
	}

	log.Info().Interface("counts", counts).Msg("DEBUG: Loaded reaction counts")

	// Load user's reactions (only if userID is provided)
	var myReactions []string
	if userID != "" {
		userRows, err := r.pool.Query(ctx, `
			SELECT emoji FROM public.post_reactions
			 WHERE post_id = $1::uuid AND user_id = $2::uuid`,
			postID,
			userID,
		)
		if err != nil {
			return nil, nil, nil, fmt.Errorf("failed to load user reactions: %w", err)
		}
		defer userRows.Close()

		myReactions = []string{}
		for userRows.Next() {
			var reaction string
			if err := userRows.Scan(&reaction); err != nil {
				return nil, nil, nil, fmt.Errorf("failed to scan user reactions: %w", err)
			}
			myReactions = append(myReactions, reaction)
		}
		if userRows.Err() != nil {
			return nil, nil, nil, fmt.Errorf("failed to iterate user reactions: %w", userRows.Err())
		}
	}

	// Load reaction users (who reacted with what)
	userListRows, err := r.pool.Query(ctx, `
		SELECT pr.emoji, p.handle as user_handle 
		FROM public.post_reactions pr
		JOIN public.profiles p ON pr.user_id = p.id
		WHERE pr.post_id = $1::uuid
		ORDER BY pr.created_at ASC`,
		postID,
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to load reaction users: %w", err)
	}
	defer userListRows.Close()

	reactionUsers := make(map[string][]string)
	for userListRows.Next() {
		var emoji, userHandle string
		if err := userListRows.Scan(&emoji, &userHandle); err != nil {
			return nil, nil, nil, fmt.Errorf("failed to scan reaction users: %w", err)
		}
		reactionUsers[emoji] = append(reactionUsers[emoji], userHandle)
	}
	if userListRows.Err() != nil {
		return nil, nil, nil, fmt.Errorf("failed to iterate reaction users: %w", userListRows.Err())
	}

	return counts, myReactions, reactionUsers, nil
}

func (r *PostRepository) GetPopularPublicPosts(ctx context.Context, viewerID string, limit int) ([]models.Post, error) {
	query := `
		SELECT 
			p.id, p.author_id, p.category_id, p.body, 
			COALESCE(p.image_url, ''),
			CASE
				WHEN COALESCE(p.video_url, '') <> '' THEN p.video_url
				WHEN COALESCE(p.image_url, '') ILIKE '%.mp4' THEN p.image_url
				ELSE ''
			END AS resolved_video_url,
			COALESCE(NULLIF(p.thumbnail_url, ''), p.image_url, '') AS resolved_thumbnail_url,
			COALESCE(p.duration_ms, 0),
			COALESCE(p.tags, ARRAY[]::text[]),
			p.created_at,
			pr.handle as author_handle, pr.display_name as author_display_name, COALESCE(pr.avatar_url, '') as author_avatar_url,
			COALESCE(m.like_count, 0) as like_count, COALESCE(m.comment_count, 0) as comment_count,
			CASE WHEN ($2::text) != '' THEN EXISTS(SELECT 1 FROM public.post_likes WHERE post_id = p.id AND user_id = $2::text::uuid) ELSE FALSE END as is_liked,
			p.allow_chain, p.visibility,
			p.link_preview_url, p.link_preview_title, p.link_preview_description, p.link_preview_image_url, p.link_preview_site_name,
		COALESCE(t.tier, 'new_user') as author_trust_tier
		FROM public.posts p
		JOIN public.profiles pr ON p.author_id = pr.id
		LEFT JOIN public.post_metrics m ON p.id = m.post_id
		LEFT JOIN public.trust_state t ON p.author_id = t.user_id
		WHERE p.deleted_at IS NULL AND p.status = 'active'
		  AND pr.is_private = FALSE
		  AND p.visibility = 'public'
		  AND COALESCE(p.is_nsfw, FALSE) = FALSE
		ORDER BY (COALESCE(m.like_count, 0) * 2 + COALESCE(m.comment_count, 0) * 5) DESC, p.created_at DESC
		LIMIT $1
	`
	rows, err := r.pool.Query(ctx, query, limit, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	posts := []models.Post{}
	for rows.Next() {
		var p models.Post
		err := rows.Scan(
			&p.ID, &p.AuthorID, &p.CategoryID, &p.Body, &p.ImageURL, &p.VideoURL, &p.ThumbnailURL, &p.DurationMS, &p.Tags, &p.CreatedAt,
			&p.AuthorHandle, &p.AuthorDisplayName, &p.AuthorAvatarURL,
			&p.LikeCount, &p.CommentCount, &p.IsLiked,
			&p.AllowChain, &p.Visibility,
			&p.LinkPreviewURL, &p.LinkPreviewTitle, &p.LinkPreviewDescription, &p.LinkPreviewImageURL, &p.LinkPreviewSiteName,
			&p.AuthorTrustTier,
		)
		if err != nil {
			return nil, err
		}
		p.Author = &models.AuthorProfile{
			ID:          p.AuthorID,
			Handle:      p.AuthorHandle,
			DisplayName: p.AuthorDisplayName,
			AvatarURL:   p.AuthorAvatarURL,
			TrustTier:   p.AuthorTrustTier,
		}
		posts = append(posts, p)
	}
	return posts, nil
}
