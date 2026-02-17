package main

import (
	"context"
	"io/ioutil"
	"os"
	"time"

	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/database"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	cfg := config.LoadConfig()
	if cfg.DatabaseURL == "" {
		log.Fatal().Msg("DATABASE_URL is not set")
	}

	pool, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to connect to database")
	}
	defer pool.Close()

	migrationPath := "internal/database/migrations/20260127000001_add_status_and_privacy.up.sql"
	content, err := ioutil.ReadFile(migrationPath)
	if err != nil {
		log.Fatal().Err(err).Msgf("Failed to read migration: %s", migrationPath)
	}

	log.Info().Msg("Applying specific migration...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err = pool.Exec(ctx, string(content))
	if err != nil {
		log.Fatal().Err(err).Msg("Migration failed")
	}

	log.Info().Msg("Migration applied successfully!")
}
