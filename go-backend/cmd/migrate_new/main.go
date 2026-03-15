// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package main

import (
	"context"
	"io/ioutil"
	"os"
	"path/filepath"
	"time"

	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/database"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	// Setup logging
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	// Load configuration
	cfg := config.LoadConfig()
	if cfg.DatabaseURL == "" {
		log.Fatal().Msg("DATABASE_URL environment variable is not set")
	}

	// Connect to database
	log.Info().Msg("Connecting to database...")
	pool, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to connect to database")
	}
	defer pool.Close()

	migrationsDir := "internal/database/migrations"

	// New migrations to apply
	migrations := []string{
		"000010_notification_preferences.up.sql",
		"000011_tagging_system.up.sql",
	}

	ctx := context.Background()

	for _, filename := range migrations {
		log.Info().Msgf("Applying migration: %s", filename)

		content, err := ioutil.ReadFile(filepath.Join(migrationsDir, filename))
		if err != nil {
			log.Error().Err(err).Msgf("Failed to read file: %s", filename)
			continue
		}

		ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
		_, err = pool.Exec(ctx, string(content))
		cancel()

		if err != nil {
			// Check if the error is just "already exists"
			errStr := err.Error()
			if contains(errStr, "already exists") || contains(errStr, "duplicate key") {
				log.Warn().Msgf("Migration %s may have already been applied (partial): %s", filename, errStr)
				continue
			}
			log.Error().Err(err).Msgf("Failed to execute migration: %s", filename)
			os.Exit(1)
		}

		log.Info().Msgf("Successfully applied: %s", filename)
	}

	log.Info().Msg("All new migrations applied successfully.")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsRune(s, substr))
}

func containsRune(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
