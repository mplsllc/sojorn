// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package main

import (
	"context"
	"io/ioutil"
	"os"
	"path/filepath"
	"sort"
	"strings"
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

	// Locate migrations directory
	// Assuming running from project root: go run cmd/migrate/main.go
	migrationsDir := "internal/database/migrations"
	if _, err := os.Stat(migrationsDir); os.IsNotExist(err) {
		// Try absolute path or different relative path logic if needed
		// getting executable path is tricky with 'go run', so we rely on CWD being project root
		log.Fatal().Msgf("Migrations directory not found at: %s. Make sure you run this from the project root.", migrationsDir)
	}

	// Get all .sql files
	files, err := ioutil.ReadDir(migrationsDir)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to read migrations directory")
	}

	var sqlFiles []string
	for _, file := range files {
		if !file.IsDir() && strings.HasSuffix(file.Name(), ".up.sql") {
			sqlFiles = append(sqlFiles, file.Name())
		}
	}

	// Sort files to ensure order
	sort.Strings(sqlFiles)

	if len(sqlFiles) == 0 {
		log.Info().Msg("No migration files found.")
		return
	}

	ctx := context.Background()

	// Simple migration runner: just runs them all
	// In a production system, you'd want a migrations table to track what has been run.
	// For this transition, we are manually applying specific schema changes.

	for _, filename := range sqlFiles {
		log.Info().Msgf("Applying migration: %s", filename)

		content, err := ioutil.ReadFile(filepath.Join(migrationsDir, filename))
		if err != nil {
			log.Error().Err(err).Msgf("Failed to read file: %s", filename)
			continue
		}

		ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
		_, err = pool.Exec(ctx, string(content))
		cancel()

		if err != nil {
			log.Error().Err(err).Msgf("Failed to execute migration: %s", filename)
			// Decide if we should stop or continue. Usually stop.
			os.Exit(1)
		}

		log.Info().Msgf("Successfully applied: %s", filename)
	}

	log.Info().Msg("All migrations applied successfully.")
}
