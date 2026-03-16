// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package config

import (
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	// Core
	Port         string
	Env          string
	LogLevel     string
	DatabaseURL  string
	JWTSecret    string
	CORSOrigins  string
	RateLimitRPS int

	// Instance identity
	InstanceName string // Human-readable instance name (shown in /api/v1/instance)
	APIBaseURL   string // Public URL of the API (e.g. https://api.example.com)
	AppBaseURL   string // Public URL of the frontend app (e.g. https://example.com)
	CookieDomain string // Domain for auth cookies (e.g. .example.com). Empty = browser default.
	SupportEmail string // Contact email shown to users (e.g. support@example.com)

	// Email / SMTP
	SMTPHost       string
	SMTPPort       int
	SMTPUser       string
	SMTPPass       string
	SMTPFrom       string
	SenderAPIToken string

	// SendPulse (optional newsletter/waitlist)
	SendPulseID     string
	SendPulseSecret string

	// Cloudflare R2 / S3-compatible storage
	R2SigningSecret string
	R2PublicBaseURL string
	R2AccountID     string
	R2APIToken      string
	R2ImgDomain     string
	R2VidDomain     string
	R2Endpoint      string
	R2AccessKey     string
	R2SecretKey     string
	R2MediaBucket   string
	R2VideoBucket   string

	// Firebase (optional push notifications)
	FirebaseCredentialsFile string

	// AI / Moderation
	AIGatewayURL      string
	AIGatewayToken    string
	SightEngineUser   string
	SightEngineSecret string
	OllamaURL         string // Ollama API base URL (e.g. http://localhost:11434)
	SearxngURL        string // SearXNG search URL (e.g. http://localhost:8888)

	// External data sources
	IcedAPIBase        string // IcedCoffee public-safety API base URL
	MN511ProxyURL      string // MN511 traffic data proxy URL
	EventbriteAPIKey   string // Eventbrite API key for event ingestion
	TicketmasterAPIKey string // Ticketmaster Discovery API key for event ingestion
}

func LoadConfig() *Config {
	// Try current directory first
	err := godotenv.Load()
	if err != nil {
		// Try parent directory (common for VPS structure /opt/sojorn/.env while binary is in /opt/sojorn/go-backend)
		_ = godotenv.Load("../.env")
		// Try absolute path specified by user
		_ = godotenv.Load("/opt/sojorn/.env")
	}

	return &Config{
		// Core
		Port:         getEnv("PORT", "8080"),
		Env:          getEnv("ENV", "development"),
		LogLevel:     getEnv("LOG_LEVEL", "info"),
		DatabaseURL:  getEnv("DATABASE_URL", ""),
		JWTSecret:    getEnv("JWT_SECRET", ""),
		CORSOrigins:  getEnv("CORS_ORIGINS", "*"),
		RateLimitRPS: getEnvInt("RATE_LIMIT_RPS", 10),

		// Instance identity
		InstanceName: getEnv("INSTANCE_NAME", "Sojorn"),
		APIBaseURL:   getEnv("API_BASE_URL", "http://localhost:8080"),
		AppBaseURL:   getEnv("APP_BASE_URL", "http://localhost:3000"),
		CookieDomain: getEnv("COOKIE_DOMAIN", ""),
		SupportEmail: getEnv("SUPPORT_EMAIL", ""),

		// Email / SMTP
		SMTPHost:       getEnv("SMTP_HOST", ""),
		SMTPPort:       getEnvInt("SMTP_PORT", 587),
		SMTPUser:       getEnv("SMTP_USER", ""),
		SMTPPass:       getEnv("SMTP_PASS", ""),
		SMTPFrom:       getEnv("SMTP_FROM", ""),
		SenderAPIToken: getEnv("SENDER_API_TOKEN", ""),

		// SendPulse
		SendPulseID:     getEnv("SENDPULSE_ID", ""),
		SendPulseSecret: getEnv("SENDPULSE_SECRET", ""),

		// Cloudflare R2 / S3-compatible storage
		R2SigningSecret: getEnv("R2_SIGNING_SECRET", ""),
		R2PublicBaseURL: getEnv("R2_PUBLIC_BASE_URL", ""),
		R2AccountID:     getEnv("R2_ACCOUNT_ID", ""),
		R2APIToken:      getEnv("R2_API_TOKEN", ""),
		R2ImgDomain:     getEnv("R2_IMG_DOMAIN", ""),
		R2VidDomain:     getEnv("R2_VID_DOMAIN", ""),
		R2Endpoint:      getEnv("R2_ENDPOINT", ""),
		R2AccessKey:     getEnv("R2_ACCESS_KEY", ""),
		R2SecretKey:     getEnv("R2_SECRET_KEY", ""),
		R2MediaBucket:   getEnv("R2_MEDIA_BUCKET", "media"),
		R2VideoBucket:   getEnv("R2_VIDEO_BUCKET", "videos"),

		// Firebase
		FirebaseCredentialsFile: getEnv("FIREBASE_CREDENTIALS_FILE", ""),

		// AI / Moderation
		AIGatewayURL:      getEnv("AI_GATEWAY_URL", ""),
		AIGatewayToken:    getEnv("AI_GATEWAY_TOKEN", ""),
		SightEngineUser:   getEnv("SIGHTENGINE_USER", ""),
		SightEngineSecret: getEnv("SIGHTENGINE_SECRET", ""),
		OllamaURL:         getEnv("OLLAMA_URL", "http://localhost:11434"),
		SearxngURL:        getEnv("SEARXNG_URL", "http://localhost:8888"),

		// External data sources
		IcedAPIBase:        getEnv("ICED_API_BASE", ""),
		MN511ProxyURL:      getEnv("MN511_PROXY_URL", ""),
		EventbriteAPIKey:   getEnv("EVENTBRITE_API_KEY", ""),
		TicketmasterAPIKey: getEnv("TICKETMASTER_API_KEY", ""),
	}
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	valueStr := getEnv(key, "")
	if value, err := strconv.Atoi(valueStr); err == nil {
		return value
	}
	return fallback
}
