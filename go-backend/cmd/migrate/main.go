// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/database"
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

	// Locate migrations directory — try multiple paths for flexibility.
	// 1. Running from go-backend/: internal/database/migrations
	// 2. Running from repo root:   go-backend/internal/database/migrations
	// 3. Docker / compiled binary:  migrations/ next to the binary
	candidates := []string{
		"internal/database/migrations",
		"go-backend/internal/database/migrations",
		"migrations",
	}

	// Also check relative to the executable path (for Docker deployments
	// where the binary lives in /app and migrations in /app/migrations).
	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(exeDir, "migrations"),
			filepath.Join(exeDir, "internal", "database", "migrations"),
		)
	}

	var migrationsDir string
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			migrationsDir = candidate
			break
		}
	}
	if migrationsDir == "" {
		log.Fatal().Strs("tried", candidates).Msg("Migrations directory not found. Make sure you run this from the project root or place a migrations/ directory next to the binary.")
	}

	log.Info().Str("dir", migrationsDir).Msg("Using migrations directory")

	// Get all .up.sql files
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to read migrations directory")
	}

	var sqlFiles []string
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".up.sql") {
			sqlFiles = append(sqlFiles, entry.Name())
		}
	}

	// Sort files to ensure order (000_init runs first)
	sort.Strings(sqlFiles)

	if len(sqlFiles) == 0 {
		log.Info().Msg("No migration files found.")
		return
	}

	ctx := context.Background()

	// Ensure schema_migrations tracking table exists.
	_, err = pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`)
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to create schema_migrations table")
	}

	applied := 0
	skipped := 0

	for _, filename := range sqlFiles {
		// Check if this migration was already applied.
		var exists int
		err := pool.QueryRow(ctx, `SELECT 1 FROM schema_migrations WHERE version = $1`, filename).Scan(&exists)
		if err == nil {
			log.Info().Msgf("Skipping %s, already applied", filename)
			skipped++
			continue
		}

		log.Info().Msgf("Applying migration: %s", filename)

		content, err := os.ReadFile(filepath.Join(migrationsDir, filename))
		if err != nil {
			log.Error().Err(err).Msgf("Failed to read file: %s", filename)
			os.Exit(1)
		}

		// Run migration + record in a single transaction.
		tx, err := pool.Begin(ctx)
		if err != nil {
			log.Error().Err(err).Msgf("Failed to begin transaction for: %s", filename)
			os.Exit(1)
		}

		txCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		_, execErr := tx.Exec(txCtx, string(content))
		cancel()

		if execErr != nil {
			_ = tx.Rollback(ctx)
			log.Error().Err(execErr).Msgf("Failed to execute migration: %s", filename)
			os.Exit(1)
		}

		_, execErr = tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, filename)
		if execErr != nil {
			_ = tx.Rollback(ctx)
			log.Error().Err(execErr).Msgf("Failed to record migration: %s", filename)
			os.Exit(1)
		}

		if err := tx.Commit(ctx); err != nil {
			log.Error().Err(err).Msgf("Failed to commit migration: %s", filename)
			os.Exit(1)
		}

		log.Info().Msgf("Successfully applied: %s", filename)
		applied++
	}

	log.Info().Msg(fmt.Sprintf("%d migrations applied, %d already up-to-date", applied, skipped))
}
