// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	log.Println("Starting seeder...")
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on env vars")
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v", err)
	}
	defer pool.Close()

	ctx := context.Background()

	// 1. Fix Schema (Missing Columns)
	log.Println("Fixing schema...")
	schemaFixes := []string{
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE`,
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon_url TEXT`,
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS official_account_id UUID`,
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE`,
		`CREATE TABLE IF NOT EXISTS user_category_settings (
            user_id UUID NOT NULL,
            category_id UUID NOT NULL,
            enabled BOOLEAN NOT NULL DEFAULT TRUE,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            PRIMARY KEY (user_id, category_id)
        )`,
	}

	for _, query := range schemaFixes {
		_, err := pool.Exec(ctx, query)
		if err != nil {
			log.Printf("Warning executing schema fix: %s\nError: %v", query, err)
			// Continue as column might exist or other non-fatal error
		}
	}

	// 2. Seed Categories
	log.Println("Seeding categories...")
	categories := []struct {
		Name        string
		Slug        string
		Description string
		IconURL     string
	}{
		{"Travel", "travel", "Explore the world", "✈️"},
		{"Food", "food", "Delicious eats", "🍔"},
		{"Tech", "tech", "Latest gadgets and software", "💻"},
		{"Art", "art", "Creative expressions", "🎨"},
		{"Music", "music", "Sounds and rhythms", "🎵"},
	}

	for _, cat := range categories {
		var catID uuid.UUID
		// Check if exists
		err := pool.QueryRow(ctx, "SELECT id FROM categories WHERE slug = $1", cat.Slug).Scan(&catID)
		if err == pgx.ErrNoRows {
			// Create
			err = pool.QueryRow(ctx, `
                INSERT INTO categories (name, slug, description, icon_url, is_active)
                VALUES ($1, $2, $3, $4, true)
                RETURNING id
            `, cat.Name, cat.Slug, cat.Description, cat.IconURL).Scan(&catID)
			if err != nil {
				log.Printf("Failed to create category %s: %v", cat.Name, err)
				continue
			}
			log.Printf("Created category: %s", cat.Name)
		} else if err != nil {
			log.Printf("Error checking category %s: %v", cat.Name, err)
			continue
		} else {
			// Update icon/active
			_, err = pool.Exec(ctx, "UPDATE categories SET icon_url = $1, is_active = true WHERE id = $2", cat.IconURL, catID)
			if err != nil {
				log.Printf("Failed to update category %s: %v", cat.Name, err)
			}
		}

		// 3. Create/Link Official Account
		if err := ensureOfficialAccount(ctx, pool, cat.Name, catID); err != nil {
			log.Printf("Failed to ensure official account for %s: %v", cat.Name, err)
		}
	}

	// 4. Generate Random Users & Posts (Stress Test Data)
	log.Println("Generating stress test data (50 users, 200 posts)...")

	commonPasswordsBytes, _ := bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)
	commonPasswordHash := string(commonPasswordsBytes)

	for i := 0; i < 50; i++ {
		email := fmt.Sprintf("user_%d@stress.test", i)
		handle := fmt.Sprintf("user_%d", i)
		displayName := fmt.Sprintf("Stress User %d", i)

		// Create User
		var userID uuid.UUID
		err := pool.QueryRow(ctx, "SELECT id FROM users WHERE email = $1", email).Scan(&userID)
		if err == pgx.ErrNoRows {
			err = pool.QueryRow(ctx, `
				INSERT INTO users (email, encrypted_password, created_at, updated_at)
				VALUES ($1, $2, NOW(), NOW())
				RETURNING id
			`, email, commonPasswordHash).Scan(&userID)
			if err != nil {
				log.Printf("Failed to create user %s: %v", email, err)
				continue
			}

			// Create Profile
			_, err = pool.Exec(ctx, `
				INSERT INTO profiles (id, handle, display_name, created_at, updated_at)
				VALUES ($1, $2, $3, NOW(), NOW())
			`, userID, handle, displayName)

			// Initialize Trust State
			pool.Exec(ctx, "INSERT INTO trust_state (user_id) VALUES ($1)", userID)

			// Initialize Privacy Settings
			pool.Exec(ctx, "INSERT INTO profile_privacy_settings (user_id) VALUES ($1)", userID)
		} else if err != nil {
			continue
		}

		// Create 4-5 Posts per user
		for j := 0; j < 5; j++ {
			body := fmt.Sprintf("Stress test post #%d from user %d. #stress #test", j, i)
			_, err := pool.Exec(ctx, `
				INSERT INTO posts (author_id, body, status, visibility, created_at)
				VALUES ($1, $2, 'active', 'public', NOW())
			`, userID, body)
			if err != nil {
				log.Printf("Failed to create post for %s: %v", handle, err)
			}
		}
	}

	log.Println("Seeding complete.")
}

func ensureOfficialAccount(ctx context.Context, pool *pgxpool.Pool, catName string, catID uuid.UUID) error {
	// Check if category has official account
	var officialAccountID *uuid.UUID
	err := pool.QueryRow(ctx, "SELECT official_account_id FROM categories WHERE id = $1", catID).Scan(&officialAccountID)
	if err != nil {
		return err
	}

	if officialAccountID != nil {
		// Exists, ensure profile is correct?
		return nil // Assume good
	}

	// Create User
	email := fmt.Sprintf("official_%s@sojorn.com", catName)
	handle := fmt.Sprintf("sojorn_%s", catName)
	displayName := fmt.Sprintf("Sojorn %s", catName)
	password := "OfficialAccount123!" // Should change later

	hashedBytes, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	passwordHash := string(hashedBytes)

	var userID uuid.UUID
	// Check user exists
	err = pool.QueryRow(ctx, "SELECT id FROM users WHERE email = $1", email).Scan(&userID)
	if err == pgx.ErrNoRows {
		err = pool.QueryRow(ctx, `
            INSERT INTO users (email, encrypted_password, created_at, updated_at)
            VALUES ($1, $2, NOW(), NOW())
            RETURNING id
        `, email, passwordHash).Scan(&userID)
		if err != nil {
			return fmt.Errorf("creating user: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("checking user: %w", err)
	}

	// Check/Create Profile
	var profileID uuid.UUID
	err = pool.QueryRow(ctx, "SELECT id FROM profiles WHERE id = $1", userID).Scan(&profileID)
	if err == pgx.ErrNoRows {
		_, err = pool.Exec(ctx, `
            INSERT INTO profiles (id, handle, display_name, is_official, created_at, updated_at)
            VALUES ($1, $2, $3, true, NOW(), NOW())
        `, userID, handle, displayName)
		if err != nil {
			return fmt.Errorf("creating profile: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("checking profile: %w", err)
	}

	// Update Category
	_, err = pool.Exec(ctx, "UPDATE categories SET official_account_id = $1 WHERE id = $2", userID, catID)
	if err != nil {
		return fmt.Errorf("linking category: %w", err)
	}

	// Create Seed Posts
	for i := 1; i <= 5; i++ {
		body := fmt.Sprintf("Welcome to the official %s feed! Post #%d. #%s", catName, i, catName)
		_, err := pool.Exec(ctx, `
            INSERT INTO posts (author_id, category_id, body, status, visibility, created_at)
            VALUES ($1, $2, $3, 'active', 'public', NOW())
         `, userID, catID, body)
		if err != nil {
			log.Printf("Failed to seed post for %s: %v", catName, err)
		}
	}

	log.Printf("Official account setup content for %s", catName)
	return nil
}
