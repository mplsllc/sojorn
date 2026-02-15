package services

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// MockModerationService tests the AI moderation functionality
func TestModerationService_AnalyzeContent(t *testing.T) {
	// Test with mock service (no API keys for testing)
	pool := &pgxpool.Pool{} // Mock pool
	service := NewModerationService(pool, "", "")

	ctx := context.Background()

	tests := []struct {
		name       string
		content    string
		mediaURLs  []string
		wantReason string
		wantHate   float64
		wantGreed  float64
		wantDelusion float64
	}{
		{
			name:       "Clean content",
			content:    "Hello world, how are you today?",
			mediaURLs:  []string{},
			wantReason: "",
			wantHate:   0.0,
			wantGreed:  0.0,
			wantDelusion: 0.0,
		},
		{
			name:       "Hate content",
			content:    "I hate everyone and want to attack them",
			mediaURLs:  []string{},
			wantReason: "hate",
			wantHate:   0.0, // Will be 0 without OpenAI API
			wantGreed:  0.0,
			wantDelusion: 0.0,
		},
		{
			name:       "Greed content",
			content:    "Get rich quick with crypto investment guaranteed returns",
			mediaURLs:  []string{},
			wantReason: "greed",
			wantHate:   0.0,
			wantGreed:  0.7, // Keyword-based detection
			wantDelusion: 0.0,
		},
		{
			name:       "Delusion content",
			content:    "Fake news conspiracy theories about truth",
			mediaURLs:  []string{},
			wantReason: "delusion",
			wantHate:   0.0,
			wantGreed:  0.0,
			wantDelusion: 0.0, // Will be 0 without OpenAI API
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score, reason, err := service.AnalyzeContent(ctx, tt.content, tt.mediaURLs)
			
			assert.NoError(t, err)
			assert.Equal(t, tt.wantReason, reason)
			assert.Equal(t, tt.wantHate, score.Hate)
			assert.Equal(t, tt.wantGreed, score.Greed)
			assert.Equal(t, tt.wantDelusion, score.Delusion)
		})
	}
}

func TestModerationService_KeywordDetection(t *testing.T) {
	pool := &pgxpool.Pool{} // Mock pool
	service := NewModerationService(pool, "", "")

	ctx := context.Background()

	// Test keyword-based greed detection
	score, reason, err := service.AnalyzeContent(ctx, "Buy now get rich quick crypto scam", []string{})
	
	assert.NoError(t, err)
	assert.Equal(t, "greed", reason)
	assert.Greater(t, score.Greed, 0.5)
}

func TestModerationService_ImageURLDetection(t *testing.T) {
	// Test the isImageURL helper function
	tests := []struct {
		url      string
		expected bool
	}{
		{"https://example.com/image.jpg", true},
		{"https://example.com/image.jpeg", true},
		{"https://example.com/image.png", true},
		{"https://example.com/image.gif", true},
		{"https://example.com/image.webp", true},
		{"https://example.com/video.mp4", false},
		{"https://example.com/document.pdf", false},
		{"https://example.com/", false},
	}

	for _, tt := range tests {
		t.Run(tt.url, func(t *testing.T) {
			result := isImageURL(tt.url)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestModerationService_VisionScoreConversion(t *testing.T) {
	pool := &pgxpool.Pool{} // Mock pool
	service := NewModerationService(pool, "", "")

	tests := []struct {
		name           string
		safeSearch     GoogleVisionSafeSearch
		expectedHate   float64
		expectedDelusion float64
	}{
		{
			name: "Clean image",
			safeSearch: GoogleVisionSafeSearch{
				Adult:    "UNLIKELY",
				Violence: "UNLIKELY",
				Racy:     "UNLIKELY",
			},
			expectedHate:     0.3,
			expectedDelusion: 0.3,
		},
		{
			name: "Violent image",
			safeSearch: GoogleVisionSafeSearch{
				Adult:    "UNLIKELY",
				Violence: "VERY_LIKELY",
				Racy:     "UNLIKELY",
			},
			expectedHate:     0.9,
			expectedDelusion: 0.3,
		},
		{
			name: "Adult content",
			safeSearch: GoogleVisionSafeSearch{
				Adult:    "VERY_LIKELY",
				Violence: "UNLIKELY",
				Racy:     "UNLIKELY",
			},
			expectedHate:     0.9,
			expectedDelusion: 0.3,
		},
		{
			name: "Racy content",
			safeSearch: GoogleVisionSafeSearch{
				Adult:    "UNLIKELY",
				Violence: "UNLIKELY",
				Racy:     "VERY_LIKELY",
			},
			expectedHate:     0.3,
			expectedDelusion: 0.9,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score := service.convertVisionScore(tt.safeSearch)
			assert.Equal(t, tt.expectedHate, score.Hate)
			assert.Equal(t, tt.expectedDelusion, score.Delusion)
		})
	}
}

func TestThreePoisonsScore_Max(t *testing.T) {
	tests := []struct {
		name     string
		values   []float64
		expected float64
	}{
		{
			name:     "Single value",
			values:   []float64{0.5},
			expected: 0.5,
		},
		{
			name:     "Multiple values",
			values:   []float64{0.1, 0.7, 0.3},
			expected: 0.7,
		},
		{
			name:     "All zeros",
			values:   []float64{0.0, 0.0, 0.0},
			expected: 0.0,
		},
		{
			name:     "Empty slice",
			values:   []float64{},
			expected: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := max(tt.values...)
			assert.Equal(t, tt.expected, result)
		})
	}
}

// Integration test example (requires actual database and API keys)
func TestModerationService_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// This test requires:
	// 1. A real database connection
	// 2. OpenAI and Google Vision API keys
	// 3. Proper test environment setup
	
	t.Skip("Integration test requires database and API keys setup")
	
	// Example structure for integration test:
	/*
	ctx := context.Background()
	
	// Setup test database
	pool := setupTestDB(t)
	defer cleanupTestDB(t, pool)
	
	// Setup service with real API keys
	service := NewModerationService(pool, "test-openai-key", "test-google-key")
	
	// Test actual content analysis
	score, reason, err := service.AnalyzeContent(ctx, "Test content", []string{})
	assert.NoError(t, err)
	assert.NotNil(t, score)
	
	// Test database operations
	postID := uuid.New()
	err = service.FlagPost(ctx, postID, score, reason)
	assert.NoError(t, err)
	
	// Verify flag was created
	flags, err := service.GetPendingFlags(ctx, 10, 0)
	assert.NoError(t, err)
	assert.Len(t, flags, 1)
	*/
}

// Benchmark tests
func BenchmarkModerationService_AnalyzeContent(b *testing.B) {
	pool := &pgxpool.Pool{} // Mock pool
	service := NewModerationService(pool, "", "")
	ctx := context.Background()
	content := "This is a test post with some content to analyze"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = service.AnalyzeContent(ctx, content, []string{})
	}
}

func BenchmarkModerationService_KeywordDetection(b *testing.B) {
	pool := &pgxpool.Pool{} // Mock pool
	service := NewModerationService(pool, "", "")
	ctx := context.Background()
	content := "Buy crypto get rich quick investment scam"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = service.AnalyzeContent(ctx, content, []string{})
	}
}

// Helper function to setup test database (for integration tests)
func setupTestDB(t *testing.T) *pgxpool.Pool {
	// This would setup a test database connection
	// Implementation depends on your test environment
	t.Helper()
	return nil
}

// Helper function to cleanup test database (for integration tests)
func cleanupTestDB(t *testing.T, pool *pgxpool.Pool) {
	// This would cleanup the test database
	// Implementation depends on your test environment
	t.Helper()
}
