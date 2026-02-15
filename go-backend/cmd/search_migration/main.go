package main

import (
	"context"
	"os"
	"time"

	"github.com/patbritton/sojorn-backend/internal/config"
	"github.com/patbritton/sojorn-backend/internal/database"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	cfg := config.LoadConfig()
	if cfg.DatabaseURL == "" {
		log.Fatal().Msg("DATABASE_URL is not set")
	}

	log.Info().Msg("Connecting to database...")
	pool, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to connect")
	}
	defer pool.Close()

	// SQL to enable pg_trgm and create GIN indices
	sql := `
		-- Enable pg_trgm extension
		CREATE EXTENSION IF NOT EXISTS pg_trgm;

		-- Create GIN indices for profiles
		CREATE INDEX IF NOT EXISTS idx_profiles_handle_trgm ON profiles USING gin (handle gin_trgm_ops);
		CREATE INDEX IF NOT EXISTS idx_profiles_display_name_trgm ON profiles USING gin (display_name gin_trgm_ops);

		-- Create GIN index for post body
		CREATE INDEX IF NOT EXISTS idx_posts_body_trgm ON posts USING gin (body gin_trgm_ops);

		-- Create GIN index for post tags
		CREATE INDEX IF NOT EXISTS idx_posts_tags_gin ON posts USING gin (tags);
	`

	log.Info().Msg("Applying search optimization indexes...")
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Minute)
	defer cancel()

	_, err = pool.Exec(ctx, sql)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to apply migration")
	}

	log.Info().Msg("Successfully applied search optimization!")
}
