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
			COALESCE(like_count, 0) as likes,
			COALESCE(comment_count, 0) as comments,
			COALESCE(share_count, 0) as shares,
			COALESCE(repost_count, 0) as reposts,
			COALESCE(boost_count, 0) as boosts,
			COALESCE(amplify_count, 0) as amplifies,
			COALESCE(view_count, 0) as views,
			created_at
		FROM posts 
		WHERE id = $1
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
			COALESCE(p.like_count, 0) as likes,
			COALESCE(p.comment_count, 0) as comments,
			COALESCE(p.view_count, 0) as views,
			p.author_id
		FROM posts p
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
	query := `
		SELECT 
			COUNT(DISTINCT CASE 
				WHEN f.following_id = $2 THEN 1 
				WHEN f.follower_id = $2 THEN 1 
			END) as connection_interactions,
			COUNT(DISTINCT l.user_id) as like_connections,
			COUNT(DISTINCT c.user_id) as comment_connections
		FROM posts p
		LEFT JOIN follows f ON (f.following_id = p.author_id OR f.follower_id = p.author_id)
		LEFT JOIN post_likes l ON l.post_id = p.id AND l.user_id IN (
			SELECT following_id FROM follows WHERE follower_id = $2
			UNION
			SELECT follower_id FROM follows WHERE following_id = $2
		)
		LEFT JOIN post_comments c ON c.post_id = p.id AND c.user_id IN (
			SELECT following_id FROM follows WHERE follower_id = $2
			UNION
			SELECT follower_id FROM follows WHERE following_id = $2
		)
		WHERE p.id = $1
	`

	var connectionInteractions, likeConnections, commentConnections int
	err := s.db.QueryRow(ctx, query, postID, viewerID).Scan(
		&connectionInteractions, &likeConnections, &commentConnections,
	)
	if err != nil {
		return 0, fmt.Errorf("failed to calculate network score: %w", err)
	}

	// Network score based on connections
	networkScore := float64(connectionInteractions)*0.3 +
		float64(likeConnections)*0.4 +
		float64(commentConnections)*0.3

	// Normalize to 0-1 range
	networkScore = math.Min(networkScore/10.0, 1.0)

	return networkScore, nil
}

// Calculate personalization score based on user interests
func (s *FeedAlgorithmService) CalculatePersonalizationScore(ctx context.Context, postID string, userProfile UserInterestProfile) (float64, error) {
	// Get post category and content analysis
	query := `
		SELECT 
			p.category,
			p.body,
			p.author_id,
			p.tags
		FROM posts p
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

	// Calculate overall score with weights
	finalScore := engagementScore*0.3 +
		qualityData.QualityScore*weights.QualityWeight*0.2 +
		recencyScore*0.2 +
		networkScore*0.15 +
		personalizationScore*0.15

	return FeedScore{
		PostID:          postID,
		Score:           finalScore,
		EngagementScore: engagementScore,
		QualityScore:    qualityData.QualityScore,
		RecencyScore:    recencyScore,
		NetworkScore:    networkScore,
		Personalization: personalizationScore,
		LastUpdated:     time.Now(),
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
		INSERT INTO post_feed_scores (post_id, score, engagement_score, quality_score, recency_score, network_score, personalization, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (post_id) 
		DO UPDATE SET 
			score = EXCLUDED.score,
			engagement_score = EXCLUDED.engagement_score,
			quality_score = EXCLUDED.quality_score,
			recency_score = EXCLUDED.recency_score,
			network_score = EXCLUDED.network_score,
			personalization = EXCLUDED.personalization,
			updated_at = EXCLUDED.updated_at
	`

	_, err := s.db.Exec(ctx, query,
		score.PostID, score.Score, score.EngagementScore, score.QualityScore,
		score.RecencyScore, score.NetworkScore, score.Personalization, score.LastUpdated,
	)

	return err
}

// Get feed with algorithmic ranking
func (s *FeedAlgorithmService) GetAlgorithmicFeed(ctx context.Context, viewerID string, limit int, offset int, category string) ([]string, error) {
	weights := s.GetDefaultWeights()
	
	// Update scores for recent posts first
	err := s.UpdateFeedScores(ctx, []string{}, viewerID) // This would normally get recent posts
	if err != nil {
		log.Error().Err(err).Msg("failed to update feed scores")
	}

	// Build query with algorithmic ordering
	query := `
		SELECT post_id 
		FROM post_feed_scores pfs
		JOIN posts p ON p.id = pfs.post_id
		WHERE p.status = 'active'
	`

	args := []interface{}{}
	argIndex := 1

	if category != "" {
		query += fmt.Sprintf(" AND p.category = $%d", argIndex)
		args = append(args, category)
		argIndex++
	}

	query += fmt.Sprintf(`
		ORDER BY pfs.score DESC, p.created_at DESC
		LIMIT $%d OFFSET $%d
	`, argIndex, argIndex+1)

	args = append(args, limit, offset)

	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get algorithmic feed: %w", err)
	}
	defer rows.Close()

	var postIDs []string
	for rows.Next() {
		var postID string
		if err := rows.Scan(&postID); err != nil {
			return nil, fmt.Errorf("failed to scan post ID: %w", err)
		}
		postIDs = append(postIDs, postID)
	}

	return postIDs, nil
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
