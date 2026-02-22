// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package config

import (
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port                    string
	Env                     string
	LogLevel                string
	DatabaseURL             string
	JWTSecret               string
	CORSOrigins             string
	RateLimitRPS            int
	SMTPHost                string
	SMTPPort                int
	SMTPUser                string
	SMTPPass                string
	SMTPFrom                string
	SenderAPIToken          string
	SendPulseID             string
	SendPulseSecret         string
	R2SigningSecret         string
	R2PublicBaseURL         string
	FirebaseCredentialsFile string
	R2AccountID             string
	R2APIToken              string
	R2ImgDomain             string
	R2VidDomain             string
	R2Endpoint              string
	R2AccessKey             string
	R2SecretKey             string
	R2MediaBucket           string
	R2VideoBucket           string
	APIBaseURL              string
	AppBaseURL              string
	AIGatewayURL            string
	AIGatewayToken          string
	SightEngineUser         string
	SightEngineSecret       string
	FunkwhaleBase           string // deprecated — Freesound replaces Funkwhale
	FreesoundAPIKey         string // Freesound.org API key for royalty-free audio
	IcedAPIBase             string // IcedCoffee public-safety API base URL
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
		Port:            getEnv("PORT", "8080"),
		Env:             getEnv("ENV", "development"),
		LogLevel:        getEnv("LOG_LEVEL", "info"),
		DatabaseURL:     getEnv("DATABASE_URL", ""),
		JWTSecret:       getEnv("JWT_SECRET", ""),
		CORSOrigins:     getEnv("CORS_ORIGINS", "*"),
		RateLimitRPS:    getEnvInt("RATE_LIMIT_RPS", 10),
		SMTPHost:        getEnv("SMTP_HOST", "smtp.sender.net"),
		SMTPPort:        getEnvInt("SMTP_PORT", 587),
		SMTPUser:        getEnv("SMTP_USER", ""),
		SMTPPass:        getEnv("SMTP_PASS", ""),
		SMTPFrom:        getEnv("SMTP_FROM", "no-reply@sojorn.net"),
		SenderAPIToken:  getEnv("SENDER_API_TOKEN", ""),
		SendPulseID:     getEnv("SENDPULSE_ID", ""),
		SendPulseSecret: getEnv("SENDPULSE_SECRET", ""),
		R2SigningSecret: getEnv("R2_SIGNING_SECRET", ""),
		// Default to the public CDN domain to avoid mixed-content/http defaults.
		R2PublicBaseURL:         getEnv("R2_PUBLIC_BASE_URL", "https://img.sojorn.net"),
		FirebaseCredentialsFile: getEnv("FIREBASE_CREDENTIALS_FILE", "firebase-service-account.json"),
		R2AccountID:             getEnv("R2_ACCOUNT_ID", ""),
		R2APIToken:              getEnv("R2_API_TOKEN", ""),
		R2ImgDomain:             getEnv("R2_IMG_DOMAIN", "img.sojorn.net"),
		R2VidDomain:             getEnv("R2_VID_DOMAIN", "quips.sojorn.net"),
		R2Endpoint:              getEnv("R2_ENDPOINT", ""),
		R2AccessKey:             getEnv("R2_ACCESS_KEY", ""),
		R2SecretKey:             getEnv("R2_SECRET_KEY", ""),
		R2MediaBucket:           getEnv("R2_MEDIA_BUCKET", "sojorn-media"),
		R2VideoBucket:           getEnv("R2_VIDEO_BUCKET", "sojorn-videos"),
		APIBaseURL:              getEnv("API_BASE_URL", "https://api.sojorn.net"),
		AppBaseURL:              getEnv("APP_BASE_URL", "https://mp.ls"),
		AIGatewayURL:            getEnv("AI_GATEWAY_URL", ""),
		AIGatewayToken:          getEnv("AI_GATEWAY_TOKEN", ""),
		SightEngineUser:         getEnv("SIGHTENGINE_USER", ""),
		SightEngineSecret:       getEnv("SIGHTENGINE_SECRET", ""),
		FunkwhaleBase:           getEnv("FUNKWHALE_BASE", ""),
		FreesoundAPIKey:         getEnv("FREESOUND_API_KEY", ""),
		IcedAPIBase:             getEnv("ICED_API_BASE", "http://127.0.0.1:8089"),
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
