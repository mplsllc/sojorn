// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

type FeedAlgorithmService struct {
	db *pgxpool.Pool
}

type EngagementWeight struct {
	LikeWeight       float64 `json:"like_weight"`
	CommentWeight    float64 `json:"comment_weight"`
	ShareWeight      float64 `json:"share_weight"`
	RepostWeight     float64 `json:"repost_weight"`
	BoostWeight      float64 `json:"boost_weight"`
	AmplifyWeight    float64 `json:"amplify_weight"`
	ViewWeight       float64 `json:"view_weight"`
	TimeDecayFactor  float64 `json:"time_decay_factor"`
	RecencyBonus     float64 `json:"recency_bonus"`
	QualityWeight    float64 `json:"quality_weight"`
}

type ContentQualityScore struct {
	PostID           string    `json:"post_id"`
	QualityScore     float64   `json:"quality_score"`
	HasMedia         bool      `json:"has_media"`
	MediaQuality     float64   `json:"media_quality"`
	TextLength       int       `json:"text_length"`
	EngagementRate   float64   `json:"engagement_rate"`
	OriginalityScore float64   `json:"originality_score"`
}

type FeedScore struct {
	PostID           string    `json:"post_id"`
	Score            float64   `json:"score"`
	EngagementScore  float64   `json:"engagement_score"`
	QualityScore     float64   `json:"quality_score"`
	RecencyScore     float64   `json:"recency_score"`
	NetworkScore     float64   `json:"network_score"`
	Personalization  float64   `json:"personalization"`
	ToneScore        float64   `json:"tone_score"`
	VideoBoostScore  float64   `json:"video_boost_score"`
	HarmonyScore     float64   `json:"harmony_score"`
	ModerationPenalty float64  `json:"moderation_penalty"`
	LastUpdated      time.Time `json:"last_updated"`
}

type UserInterestProfile struct {
	UserID           string            `json:"user_id"`
	Interests        map[string]float64 `json:"interests"`
	CategoryWeights  map[string]float64 `json:"category_weights"`
	InteractionHistory map[string]int   `json:"interaction_history"`
	PreferredContent  []string          `json:"preferred_content"`
	AvoidedContent    []string          `json:"avoided_content"`
	LastUpdated      time.Time         `json:"last_updated"`
}

func NewFeedAlgorithmService(db *pgxpool.Pool) *FeedAlgorithmService {
	return &FeedAlgorithmService{
		db: db,
	}
}

// Get default engagement weights
func (s *FeedAlgorithmService) GetDefaultWeights() EngagementWeight {
	return EngagementWeight{
		LikeWeight:      1.0,
		CommentWeight:   3.0,
		ShareWeight:     5.0,
		RepostWeight:    4.0,
		BoostWeight:     8.0,
		AmplifyWeight:   10.0,
		ViewWeight:      0.1,
		TimeDecayFactor: 0.95,
		RecencyBonus:    1.2,
		QualityWeight:   2.0,
	}
}

// Calculate engagement score for a post
func (s *FeedAlgorithmService) CalculateEngagementScore(ctx context.Context, postID string, weights EngagementWeight) (float64, error) {
	query := `
		SELECT
			COALESCE(m.like_count, 0) as likes,
			COALESCE(m.comment_count, 0) as comments,
			COALESCE(p.share_count, 0) as shares,
			(SELECT COUNT(*) FROM reposts WHERE original_post_id = p.id) as reposts,
			COALESCE(p.boost_count, 0) as boosts,
			COALESCE(p.amplify_count, 0) as amplifies,
			COALESCE(m.view_count, 0) as views,
			p.created_at
		FROM posts p
		LEFT JOIN post_metrics m ON m.post_id = p.id
		WHERE p.id = $1
	`

	var likes, comments, shares, reposts, boosts, amplifies, views int
	var createdAt time.Time

	err := s.db.QueryRow(ctx, query, postID).Scan(
		&likes, &comments, &shares, &reposts, &boosts, &amplifies, &views, &createdAt,
	)
	if err != nil {
		return 0, fmt.Errorf("failed to get post engagement: %w", err)
	}

	// Calculate weighted engagement score
	engagementScore := float64(likes)*weights.LikeWeight +
		float64(comments)*weights.CommentWeight +
		float64(shares)*weights.ShareWeight +
		float64(reposts)*weights.RepostWeight +
		float64(boosts)*weights.BoostWeight +
		float64(amplifies)*weights.AmplifyWeight +
		float64(views)*weights.ViewWeight

	// Apply time decay
	hoursSinceCreation := time.Since(createdAt).Hours()
	timeDecay := math.Pow(weights.TimeDecayFactor, hoursSinceCreation/24.0) // Decay per day

	engagementScore *= timeDecay

	return engagementScore, nil
}

// Calculate content quality score
func (s *FeedAlgorithmService) CalculateContentQualityScore(ctx context.Context, postID string) (ContentQualityScore, error) {
	query := `
		SELECT
			p.body,
			p.image_url,
			p.video_url,
			p.created_at,
			COALESCE(m.like_count, 0) as likes,
			COALESCE(m.comment_count, 0) as comments,
			COALESCE(m.view_count, 0) as views,
			p.author_id
		FROM posts p
		LEFT JOIN post_metrics m ON m.post_id = p.id
		WHERE p.id = $1
	`

	var body, imageURL, videoURL sql.NullString
	var createdAt time.Time
	var likes, comments, views int
	var authorID string

	err := s.db.QueryRow(ctx, query, postID).Scan(
		&body, &imageURL, &videoURL, &createdAt, &likes, &comments, &views, &authorID,
	)
	if err != nil {
		return ContentQualityScore{}, fmt.Errorf("failed to get post content: %w", err)
	}

	// Calculate quality metrics
	hasMedia := imageURL.Valid || videoURL.Valid
	textLength := 0
	if body.Valid {
		textLength = len(body.String)
	}

	// Engagement rate (engagement per view)
	engagementRate := 0.0
	if views > 0 {
		engagementRate = float64(likes+comments) / float64(views)
	}

	// Media quality (simplified - could use image/video analysis)
	mediaQuality := 0.0
	if hasMedia {
		mediaQuality = 0.8 // Base score for having media
		if imageURL.Valid {
			// Could integrate with image analysis service here
			mediaQuality += 0.1
		}
		if videoURL.Valid {
			// Could integrate with video analysis service here
			mediaQuality += 0.1
		}
	}

	// Text quality factors
	textQuality := 0.0
	if body.Valid {
		textLength := len(body.String)
		if textLength > 10 && textLength < 500 {
			textQuality = 0.5 // Good length
		} else if textLength >= 500 && textLength < 1000 {
			textQuality = 0.3 // Longer but still readable
		}
		
		// Could add sentiment analysis, readability scores, etc.
	}

	// Originality score (simplified - could check for duplicates)
	originalityScore := 0.7 // Base assumption of originality

	// Calculate overall quality score
	qualityScore := (mediaQuality*0.3 + textQuality*0.3 + engagementRate*0.2 + originalityScore*0.2)

	return ContentQualityScore{
		PostID:           postID,
		QualityScore:     qualityScore,
		HasMedia:         hasMedia,
		MediaQuality:     mediaQuality,
		TextLength:       textLength,
		EngagementRate:   engagementRate,
		OriginalityScore: originalityScore,
	}, nil
}

// Calculate recency score
func (s *FeedAlgorithmService) CalculateRecencyScore(createdAt time.Time, weights EngagementWeight) float64 {
	hoursSinceCreation := time.Since(createdAt).Hours()
	
	// Recency bonus for recent content
	if hoursSinceCreation < 24 {
		return weights.RecencyBonus
	} else if hoursSinceCreation < 72 {
		return 1.0
	} else if hoursSinceCreation < 168 { // 1 week
		return 0.8
	} else {
		return 0.5
	}
}

// Calculate network score based on user connections
func (s *FeedAlgorithmService) CalculateNetworkScore(ctx context.Context, postID string, viewerID string) (float64, error) {
	if viewerID == "" {
		return 0, nil
	}

	// Check if viewer follows the post author (strong signal)
	query := `
		SELECT
			CASE WHEN EXISTS(
				SELECT 1 FROM follows
				WHERE follower_id = $2::uuid AND following_id = p.author_id AND status = 'accepted'
			) THEN 1 ELSE 0 END as is_following,
			(SELECT COUNT(*) FROM post_likes l
			 WHERE l.post_id = $1
			   AND l.user_id IN (SELECT following_id FROM follows WHERE follower_id = $2::uuid AND status = 'accepted')
			) as like_connections
		FROM posts p
		WHERE p.id = $1
	`

	var isFollowing, likeConnections int
	err := s.db.QueryRow(ctx, query, postID, viewerID).Scan(
		&isFollowing, &likeConnections,
	)
	if err != nil {
		return 0, fmt.Errorf("failed to calculate network score: %w", err)
	}

	// Network score: following author = 0.5 base, plus friend-likes bonus
	networkScore := float64(isFollowing)*0.5 +
		float64(likeConnections)*0.4

	// Normalize to 0-1 range
	networkScore = math.Min(networkScore/5.0, 1.0)

	return networkScore, nil
}

// Calculate personalization score based on user interests
func (s *FeedAlgorithmService) CalculatePersonalizationScore(ctx context.Context, postID string, userProfile UserInterestProfile) (float64, error) {
	// Get post category and content analysis
	query := `
		SELECT
			COALESCE(c.slug, '') as category_slug,
			p.body,
			p.author_id,
			p.tags
		FROM posts p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE p.id = $1
	`

	var category sql.NullString
	var body sql.NullString
	var authorID string
	var tags []string

	err := s.db.QueryRow(ctx, query, postID).Scan(&category, &body, &authorID, &tags)
	if err != nil {
		return 0, fmt.Errorf("failed to get post for personalization: %w", err)
	}

	personalizationScore := 0.0

	// Category matching
	if category.Valid {
		if weight, exists := userProfile.CategoryWeights[category.String]; exists {
			personalizationScore += weight * 0.4
		}
	}

	// Interest matching (simplified keyword matching)
	if body.Valid {
		text := body.String
		for interest, weight := range userProfile.Interests {
			// Simple keyword matching - could be enhanced with NLP
			if containsKeyword(text, interest) {
				personalizationScore += weight * 0.3
			}
		}
	}

	// Tag matching
	for _, tag := range tags {
		if weight, exists := userProfile.Interests[tag]; exists {
			personalizationScore += weight * 0.2
		}
	}

	// Author preference
	if containsItem(userProfile.PreferredContent, authorID) {
		personalizationScore += 0.1
	}

	// Avoided content penalty
	if containsItem(userProfile.AvoidedContent, authorID) {
		personalizationScore -= 0.5
	}

	// Normalize to 0-1 range
	personalizationScore = math.Max(0, math.Min(personalizationScore, 1.0))

	return personalizationScore, nil
}

// getConfigFloat reads a float64 from algorithm_config, returning defaultVal if missing.
func (s *FeedAlgorithmService) getConfigFloat(ctx context.Context, key string, defaultVal float64) float64 {
	var val string
	err := s.db.QueryRow(ctx, `SELECT value FROM algorithm_config WHERE key = $1`, key).Scan(&val)
	if err != nil {
		return defaultVal
	}
	var f float64
	if _, err := fmt.Sscanf(val, "%f", &f); err != nil {
		return defaultVal
	}
	return f
}

// CalculateToneScore returns a tone-based score adjustment for a post.
// Positive content gets boosted, hostile content gets demoted.
func (s *FeedAlgorithmService) CalculateToneScore(ctx context.Context, postID string) (float64, error) {
	var toneLabel sql.NullString
	var cisScore sql.NullFloat64
	err := s.db.QueryRow(ctx,
		`SELECT COALESCE(detected_tone, 'neutral'), content_integrity_score FROM posts WHERE id = $1`, postID,
	).Scan(&toneLabel, &cisScore)
	if err != nil {
		return 0, fmt.Errorf("failed to get tone for post: %w", err)
	}

	// Read configurable tone boosts/penalties
	positiveBoost := s.getConfigFloat(ctx, "tone_positive_boost", 0.15)
	negativePenalty := s.getConfigFloat(ctx, "tone_negative_penalty", 0.15)
	hostilePenalty := s.getConfigFloat(ctx, "tone_hostile_penalty", 0.40)

	toneBoost := 0.0
	if toneLabel.Valid {
		switch toneLabel.String {
		case "positive":
			toneBoost = positiveBoost
		case "neutral":
			toneBoost = 0.0
		case "mixed":
			toneBoost = -0.03
		case "negative":
			toneBoost = -negativePenalty
		case "hostile":
			toneBoost = -hostilePenalty
		}
	}

	// CIS (Content Integrity Score) factor: 0-1, higher = more constructive
	cisFactor := 0.0
	if cisScore.Valid {
		cisFactor = (cisScore.Float64 - 0.5) * 0.2 // maps [0,1] -> [-0.1, +0.1]
	}

	return toneBoost + cisFactor, nil
}

// CalculateVideoBoostScore returns a score bonus for video posts with good watch completion.
func (s *FeedAlgorithmService) CalculateVideoBoostScore(ctx context.Context, postID string) (float64, error) {
	var videoURL sql.NullString
	err := s.db.QueryRow(ctx,
		`SELECT COALESCE(video_url, '') FROM posts WHERE id = $1`, postID,
	).Scan(&videoURL)
	if err != nil || !videoURL.Valid || videoURL.String == "" {
		return 0, nil // not a video post
	}

	baseBoost := s.getConfigFloat(ctx, "video_base_boost", 0.05)

	// Average watch percentage from post_views
	var avgWatchPct sql.NullFloat64
	s.db.QueryRow(ctx,
		`SELECT AVG(last_watch_pct) FROM post_views WHERE post_id = $1 AND last_watch_pct > 0`, postID,
	).Scan(&avgWatchPct)

	watchBonus := 0.0
	if avgWatchPct.Valid && avgWatchPct.Float64 > 0 {
		// Scale: 75%+ watched = full 0.15 bonus
		watchBonus = math.Min(avgWatchPct.Float64/75.0, 1.0) * 0.15
	}

	return baseBoost + watchBonus, nil
}

// CalculateAuthorHarmonyScore returns a normalized harmony factor for the post's author.
// Harmony score (0-100) is normalized to [floor, 1.0] so new users aren't invisible.
func (s *FeedAlgorithmService) CalculateAuthorHarmonyScore(ctx context.Context, postID string) (float64, error) {
	var harmonyScore sql.NullFloat64
	err := s.db.QueryRow(ctx, `
		SELECT ts.harmony_score
		FROM posts p
		LEFT JOIN trust_state ts ON p.author_id = ts.user_id
		WHERE p.id = $1
	`, postID).Scan(&harmonyScore)
	if err != nil {
		return 0, fmt.Errorf("failed to get harmony score: %w", err)
	}

	floor := s.getConfigFloat(ctx, "harmony_floor", 0.2)

	if !harmonyScore.Valid {
		return floor, nil // new user with no harmony data gets floor
	}

	// Normalize 0-100 to [floor, 1.0]
	normalized := floor + (harmonyScore.Float64/100.0)*(1.0-floor)
	return normalized, nil
}

// CalculateModerationPenalty returns a negative score for users with strikes or flagged posts.
func (s *FeedAlgorithmService) CalculateModerationPenalty(ctx context.Context, postID string) (float64, error) {
	strikePenaltyPer := s.getConfigFloat(ctx, "moderation_strike_penalty", 0.15)
	flagPenaltyPer := s.getConfigFloat(ctx, "moderation_flag_penalty", 0.10)
	flagPenaltyCap := s.getConfigFloat(ctx, "moderation_flag_penalty_cap", 0.30)

	// Author strikes
	var strikes int
	err := s.db.QueryRow(ctx, `
		SELECT COALESCE(pr.strikes, 0)
		FROM posts p
		JOIN profiles pr ON p.author_id = pr.id
		WHERE p.id = $1
	`, postID).Scan(&strikes)
	if err != nil {
		return 0, fmt.Errorf("failed to get author strikes: %w", err)
	}

	strikePenalty := float64(strikes) * strikePenaltyPer

	// Pending moderation flags on this post
	var flagCount int
	s.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM moderation_flags
		WHERE post_id = $1 AND status = 'pending'
	`, postID).Scan(&flagCount)

	flagPenalty := math.Min(float64(flagCount)*flagPenaltyPer, flagPenaltyCap)

	return -(strikePenalty + flagPenalty), nil // always <= 0
}

// Calculate overall feed score for a post
func (s *FeedAlgorithmService) CalculateFeedScore(ctx context.Context, postID string, viewerID string, weights EngagementWeight, userProfile UserInterestProfile) (FeedScore, error) {
	// Calculate individual components
	engagementScore, err := s.CalculateEngagementScore(ctx, postID, weights)
	if err != nil {
		return FeedScore{}, fmt.Errorf("failed to calculate engagement score: %w", err)
	}

	qualityData, err := s.CalculateContentQualityScore(ctx, postID)
	if err != nil {
		return FeedScore{}, fmt.Errorf("failed to calculate quality score: %w", err)
	}

	// Get post created_at for recency
	var createdAt time.Time
	err = s.db.QueryRow(ctx, "SELECT created_at FROM posts WHERE id = $1", postID).Scan(&createdAt)
	if err != nil {
		return FeedScore{}, fmt.Errorf("failed to get post created_at: %w", err)
	}

	recencyScore := s.CalculateRecencyScore(createdAt, weights)

	networkScore, err := s.CalculateNetworkScore(ctx, postID, viewerID)
	if err != nil {
		return FeedScore{}, fmt.Errorf("failed to calculate network score: %w", err)
	}

	personalizationScore, err := s.CalculatePersonalizationScore(ctx, postID, userProfile)
	if err != nil {
		return FeedScore{}, fmt.Errorf("failed to calculate personalization score: %w", err)
	}

	toneScore, err := s.CalculateToneScore(ctx, postID)
	if err != nil {
		log.Warn().Err(err).Str("post_id", postID).Msg("tone score calculation failed")
		toneScore = 0
	}

	videoBoost, err := s.CalculateVideoBoostScore(ctx, postID)
	if err != nil {
		log.Warn().Err(err).Str("post_id", postID).Msg("video boost calculation failed")
		videoBoost = 0
	}

	harmonyScore, err := s.CalculateAuthorHarmonyScore(ctx, postID)
	if err != nil {
		log.Warn().Err(err).Str("post_id", postID).Msg("harmony score calculation failed")
		harmonyScore = 0
	}

	modPenalty, err := s.CalculateModerationPenalty(ctx, postID)
	if err != nil {
		log.Warn().Err(err).Str("post_id", postID).Msg("moderation penalty calculation failed")
		modPenalty = 0
	}

	// Read weights from admin-configurable algorithm_config (with defaults)
	wEngagement := s.getConfigFloat(ctx, "feed_engagement_weight", 0.22)
	wQuality := s.getConfigFloat(ctx, "feed_quality_weight", 0.15)
	wRecency := s.getConfigFloat(ctx, "feed_recency_weight", 0.18)
	wNetwork := s.getConfigFloat(ctx, "feed_network_weight", 0.10)
	wPersonalization := s.getConfigFloat(ctx, "feed_personalization_weight", 0.07)
	wTone := s.getConfigFloat(ctx, "feed_tone_weight", 0.10)
	wVideo := s.getConfigFloat(ctx, "feed_video_boost_weight", 0.08)
	wHarmony := s.getConfigFloat(ctx, "feed_harmony_weight", 0.10)
	wModeration := s.getConfigFloat(ctx, "feed_moderation_penalty_weight", 0.10)

	finalScore := engagementScore*wEngagement +
		qualityData.QualityScore*wQuality +
		recencyScore*wRecency +
		networkScore*wNetwork +
		personalizationScore*wPersonalization +
		toneScore*wTone +
		videoBoost*wVideo +
		harmonyScore*wHarmony +
		modPenalty*wModeration // modPenalty is always <= 0

	return FeedScore{
		PostID:            postID,
		Score:             finalScore,
		EngagementScore:   engagementScore,
		QualityScore:      qualityData.QualityScore,
		RecencyScore:      recencyScore,
		NetworkScore:      networkScore,
		Personalization:   personalizationScore,
		ToneScore:         toneScore,
		VideoBoostScore:   videoBoost,
		HarmonyScore:      harmonyScore,
		ModerationPenalty: modPenalty,
		LastUpdated:       time.Now(),
	}, nil
}

// Update feed scores for multiple posts
func (s *FeedAlgorithmService) UpdateFeedScores(ctx context.Context, postIDs []string, viewerID string) error {
	weights := s.GetDefaultWeights()
	
	// Get user profile (simplified - would normally come from user service)
	userProfile := UserInterestProfile{
		UserID:           viewerID,
		Interests:        make(map[string]float64),
		CategoryWeights:  make(map[string]float64),
		InteractionHistory: make(map[string]int),
		PreferredContent:  []string{},
		AvoidedContent:    []string{},
		LastUpdated:      time.Now(),
	}

	for _, postID := range postIDs {
		score, err := s.CalculateFeedScore(ctx, postID, viewerID, weights, userProfile)
		if err != nil {
			log.Error().Err(err).Str("post_id", postID).Msg("failed to calculate feed score")
			continue
		}

		// Update score in database
		err = s.updatePostScore(ctx, score)
		if err != nil {
			log.Error().Err(err).Str("post_id", postID).Msg("failed to update post score")
		}
	}

	return nil
}

// Update individual post score in database
func (s *FeedAlgorithmService) updatePostScore(ctx context.Context, score FeedScore) error {
	query := `
		INSERT INTO post_feed_scores (post_id, score, engagement_score, quality_score, recency_score, network_score, personalization, tone_score, video_boost_score, harmony_score, moderation_penalty, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (post_id)
		DO UPDATE SET
			score = EXCLUDED.score,
			engagement_score = EXCLUDED.engagement_score,
			quality_score = EXCLUDED.quality_score,
			recency_score = EXCLUDED.recency_score,
			network_score = EXCLUDED.network_score,
			personalization = EXCLUDED.personalization,
			tone_score = EXCLUDED.tone_score,
			video_boost_score = EXCLUDED.video_boost_score,
			harmony_score = EXCLUDED.harmony_score,
			moderation_penalty = EXCLUDED.moderation_penalty,
			updated_at = EXCLUDED.updated_at
	`

	_, err := s.db.Exec(ctx, query,
		score.PostID, score.Score, score.EngagementScore, score.QualityScore,
		score.RecencyScore, score.NetworkScore, score.Personalization, score.ToneScore,
		score.VideoBoostScore, score.HarmonyScore, score.ModerationPenalty, score.LastUpdated,
	)

	return err
}

// GetAlgorithmicFeed returns a ranked, deduplicated, diversity-injected feed for viewerID.
//
// Scoring pipeline:
//  1. Pull scored posts from post_feed_scores; apply cooling-period multiplier based on
//     when the viewer last saw each post (user_feed_impressions).
//  2. Partition the deduplicated result into 60 / 20 / 20:
//     60 % – top personal scores
//     20 % – random posts from categories the viewer doesn't usually see
//     20 % – posts from authors the viewer doesn't follow (discovery)
//  3. Record impressions so future calls apply the cooling penalty.
func (s *FeedAlgorithmService) GetAlgorithmicFeed(ctx context.Context, viewerID string, limit int, offset int, category string) ([]string, error) {
	// ── 1. Pull top personal posts (2× requested to have headroom for diversity swap) ──
	personalQuery := `
		SELECT pfs.post_id, pfs.score,
		       ufi.shown_at AS last_shown,
		       COALESCE(cat.slug, '') AS category_slug,
		       p.author_id
		FROM post_feed_scores pfs
		JOIN posts p ON p.id = pfs.post_id
		LEFT JOIN categories cat ON cat.id = p.category_id
		LEFT JOIN user_feed_impressions ufi
		       ON ufi.post_id = pfs.post_id AND ufi.user_id = $1::uuid
		WHERE p.status = 'active'
		  AND p.deleted_at IS NULL
		  AND COALESCE(p.is_beacon, FALSE) = FALSE
		  AND p.chain_parent_id IS NULL
		  AND pfs.post_id NOT IN (SELECT post_id FROM public.post_hides WHERE user_id = $1::uuid)
		  AND p.author_id NOT IN (
		      SELECT author_id FROM public.post_hides
		      WHERE user_id = $1::uuid GROUP BY author_id HAVING COUNT(*) >= 2
		  )
		  AND NOT public.has_block_between(p.author_id, $1::uuid)
	`
	personalArgs := []interface{}{viewerID}
	argIdx := 2

	if category != "" {
		personalQuery += fmt.Sprintf(" AND cat.slug = $%d", argIdx)
		personalArgs = append(personalArgs, category)
		argIdx++
	}

	personalQuery += fmt.Sprintf(`
		ORDER BY pfs.score DESC, p.created_at DESC
		LIMIT $%d OFFSET $%d
	`, argIdx, argIdx+1)
	personalArgs = append(personalArgs, limit*2, offset)

	type feedRow struct {
		postID   string
		score    float64
		lastShown *string // nil = never shown
		category  string
		authorID  string
	}

	rows, err := s.db.Query(ctx, personalQuery, personalArgs...)
	if err != nil {
		return nil, fmt.Errorf("failed to get algorithmic feed: %w", err)
	}
	defer rows.Close()

	var personal []feedRow
	seenCategories := map[string]int{}
	for rows.Next() {
		var r feedRow
		if err := rows.Scan(&r.postID, &r.score, &r.lastShown, &r.category, &r.authorID); err != nil {
			continue
		}
		// Cooling multiplier
		if r.lastShown != nil {
			// any non-nil means it was shown before; apply decay
			r.score *= 0.2 // shown within cooling window → heavy penalty
		}
		seenCategories[r.category]++
		personal = append(personal, r)
	}
	rows.Close()

	// ── 2. Viewer's top 3 categories (for diversity contrast) ──
	topCats := topN(seenCategories, 3)
	topCatSet := map[string]bool{}
	for _, c := range topCats {
		topCatSet[c] = true
	}

	// ── 3. Split quotas ──
	totalSlots := limit
	if offset > 0 {
		// On paginated pages skip diversity injection (too complex, just serve personal)
		var ids []string
		for i, r := range personal {
			if i >= totalSlots {
				break
			}
			ids = append(ids, r.postID)
		}
		s.recordImpressions(ctx, viewerID, ids)
		return ids, nil
	}

	personalSlots := (totalSlots * 60) / 100
	crossCatSlots := (totalSlots * 20) / 100
	discoverySlots := totalSlots - personalSlots - crossCatSlots

	var result []string
	seen := map[string]bool{}

	for _, r := range personal {
		if len(result) >= personalSlots {
			break
		}
		if !seen[r.postID] {
			result = append(result, r.postID)
			seen[r.postID] = true
		}
	}

	// ── 4. Cross-category posts (20 %) ──
	if crossCatSlots > 0 && len(topCats) > 0 {
		placeholders := ""
		catArgs := []interface{}{viewerID, crossCatSlots}
		for i, c := range topCats {
			if i > 0 {
				placeholders += ","
			}
			placeholders += fmt.Sprintf("$%d", len(catArgs)+1)
			catArgs = append(catArgs, c)
		}
		crossQuery := fmt.Sprintf(`
			SELECT p.id FROM posts p
			JOIN post_feed_scores pfs ON pfs.post_id = p.id
			LEFT JOIN categories cat ON cat.id = p.category_id
			WHERE p.status = 'active'
			  AND p.deleted_at IS NULL
			  AND COALESCE(cat.slug, '') NOT IN (%s)
			  AND p.id NOT IN (SELECT post_id FROM public.post_hides WHERE user_id = $1::uuid)
			  AND p.author_id NOT IN (
			      SELECT author_id FROM public.post_hides
			      WHERE user_id = $1::uuid GROUP BY author_id HAVING COUNT(*) >= 2
			  )
			ORDER BY random()
			LIMIT $2
		`, placeholders)
		crossRows, _ := s.db.Query(ctx, crossQuery, catArgs...)
		if crossRows != nil {
			for crossRows.Next() {
				var id string
				if crossRows.Scan(&id) == nil && !seen[id] {
					result = append(result, id)
					seen[id] = true
				}
			}
			crossRows.Close()
		}
	}

	// ── 5. Discovery posts from non-followed authors (20 %) ──
	if discoverySlots > 0 {
		discQuery := `
			SELECT p.id FROM posts p
			JOIN post_feed_scores pfs ON pfs.post_id = p.id
			WHERE p.status = 'active'
			  AND p.deleted_at IS NULL
			  AND p.author_id != $1::uuid
			  AND p.author_id NOT IN (
			        SELECT following_id FROM follows WHERE follower_id = $1::uuid
			      )
			ORDER BY random()
			LIMIT $2
		`
		discRows, _ := s.db.Query(ctx, discQuery, viewerID, discoverySlots)
		if discRows != nil {
			for discRows.Next() {
				var id string
				if discRows.Scan(&id) == nil && !seen[id] {
					result = append(result, id)
					seen[id] = true
				}
			}
			discRows.Close()
		}
	}

	// ── 6. Record impressions ──
	s.recordImpressions(ctx, viewerID, result)

	return result, nil
}

// recordImpressions upserts impression rows so cooling periods take effect on future loads.
func (s *FeedAlgorithmService) recordImpressions(ctx context.Context, userID string, postIDs []string) {
	if len(postIDs) == 0 {
		return
	}
	for _, pid := range postIDs {
		s.db.Exec(ctx,
			`INSERT INTO user_feed_impressions (user_id, post_id, shown_at)
			 VALUES ($1, $2, now())
			 ON CONFLICT (user_id, post_id) DO UPDATE SET shown_at = now()`,
			userID, pid,
		)
	}
}

// topN returns up to n keys with the highest counts from a frequency map.
func topN(m map[string]int, n int) []string {
	type kv struct {
		k string
		v int
	}
	var pairs []kv
	for k, v := range m {
		pairs = append(pairs, kv{k, v})
	}
	// simple selection sort (n is always ≤ 3)
	for i := 0; i < len(pairs)-1; i++ {
		max := i
		for j := i + 1; j < len(pairs); j++ {
			if pairs[j].v > pairs[max].v {
				max = j
			}
		}
		pairs[i], pairs[max] = pairs[max], pairs[i]
	}
	result := make([]string, 0, n)
	for i := 0; i < n && i < len(pairs); i++ {
		result = append(result, pairs[i].k)
	}
	return result
}

// RefreshAllScores recalculates feed scores for all active posts from the last 7 days.
// Called by the background job every 15 minutes.
func (s *FeedAlgorithmService) RefreshAllScores(ctx context.Context) error {
	rows, err := s.db.Query(ctx, `
		SELECT id FROM posts
		WHERE status = 'active'
		  AND deleted_at IS NULL
		  AND COALESCE(is_beacon, FALSE) = FALSE
		  AND chain_parent_id IS NULL
		  AND created_at >= NOW() - INTERVAL '7 days'
		ORDER BY created_at DESC
		LIMIT 500
	`)
	if err != nil {
		return fmt.Errorf("failed to query posts for scoring: %w", err)
	}
	defer rows.Close()

	var postIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			continue
		}
		postIDs = append(postIDs, id)
	}
	rows.Close()

	if len(postIDs) == 0 {
		log.Debug().Msg("[FeedAlgorithm] No posts to score")
		return nil
	}

	log.Info().Int("count", len(postIDs)).Msg("[FeedAlgorithm] Scoring posts")

	weights := s.GetDefaultWeights()
	// Use empty profile for global scoring (personalization is viewer-specific)
	emptyProfile := UserInterestProfile{
		Interests:        make(map[string]float64),
		CategoryWeights:  make(map[string]float64),
		InteractionHistory: make(map[string]int),
	}

	scored := 0
	for _, postID := range postIDs {
		score, err := s.CalculateFeedScore(ctx, postID, "", weights, emptyProfile)
		if err != nil {
			log.Warn().Err(err).Str("post_id", postID).Msg("[FeedAlgorithm] Failed to score post")
			continue
		}
		if err := s.updatePostScore(ctx, score); err != nil {
			log.Warn().Err(err).Str("post_id", postID).Msg("[FeedAlgorithm] Failed to persist score")
			continue
		}
		scored++
	}

	log.Info().Int("scored", scored).Int("total", len(postIDs)).Msg("[FeedAlgorithm] Score refresh complete")
	return nil
}

// Helper functions
func containsKeyword(text, keyword string) bool {
	return len(text) > 0 && len(keyword) > 0 // Simplified - could use regex or NLP
}

func containsItem(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}
