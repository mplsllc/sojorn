package config

import (
	"os"
)

// ModerationConfig holds configuration for AI moderation services
type ModerationConfig struct {
	OpenAIKey       string
	GoogleKey       string
	GoogleCredsFile string
	Enabled         bool
}

// NewModerationConfig creates a new moderation configuration
func NewModerationConfig() *ModerationConfig {
	return &ModerationConfig{
		OpenAIKey:       os.Getenv("OPENAI_API_KEY"),
		GoogleKey:       os.Getenv("GOOGLE_VISION_API_KEY"),
		GoogleCredsFile: os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"),
		Enabled:         os.Getenv("MODERATION_ENABLED") != "false",
	}
}

// IsConfigured returns true if the moderation service is properly configured
func (c *ModerationConfig) IsConfigured() bool {
	return c.Enabled && (c.OpenAIKey != "" || c.GoogleKey != "")
}

// HasOpenAI returns true if OpenAI moderation is configured
func (c *ModerationConfig) HasOpenAI() bool {
	return c.OpenAIKey != ""
}

// HasGoogleVision returns true if Google Vision API is configured
func (c *ModerationConfig) HasGoogleVision() bool {
	return c.GoogleKey != "" || c.GoogleCredsFile != ""
}
