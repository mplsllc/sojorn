package services

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestModerationService_ImageURLDetection(t *testing.T) {
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

func TestModerationService_ContainsAny(t *testing.T) {
	tests := []struct {
		name     string
		text     string
		words    []string
		expected bool
	}{
		{"match found", "get rich quick scheme", []string{"rich quick", "scam"}, true},
		{"no match", "hello world", []string{"scam", "fraud"}, false},
		{"empty text", "", []string{"test"}, false},
		{"empty words", "some text", []string{}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := containsAny(tt.text, tt.words)
			assert.Equal(t, tt.expected, result)
		})
	}
}
