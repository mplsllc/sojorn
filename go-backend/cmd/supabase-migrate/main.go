package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

type SupabaseProfile struct {
	ID            string    `json:"id"`
	Handle        string    `json:"handle"`
	DisplayName   string    `json:"display_name"`
	Bio           *string   `json:"bio"`
	AvatarURL     *string   `json:"avatar_url"`
	IsOfficial    bool      `json:"is_official"`
	IsPrivate     bool      `json:"is_private"`
	BeaconEnabled bool      `json:"beacon_enabled"`
	CreatedAt     time.Time `json:"created_at"`
}

type SupabasePost struct {
	ID         string    `json:"id"`
	AuthorID   string    `json:"author_id"`
	Body       string    `json:"body"`
	ImageURL   *string   `json:"image_url"`
	CreatedAt  time.Time `json:"created_at"`
	CategoryID *string   `json:"category_id"`
	Status     string    `json:"status"`
	Visibility string    `json:"visibility"`
}

func main() {
	godotenv.Load()

	dbURL := os.Getenv("DATABASE_URL")
	sbURL := os.Getenv("SUPABASE_URL")
	sbKey := os.Getenv("SUPABASE_KEY")

	if dbURL == "" || sbURL == "" || sbKey == "" {
		log.Fatal("Missing env vars: DATABASE_URL, SUPABASE_URL, or SUPABASE_KEY")
	}

	// Connect to Local DB
	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	ctx := context.Background()

	// 1. Fetch Profiles
	log.Println("Fetching profiles from Supabase...")
	var profiles []SupabaseProfile
	if err := fetchSupabase(sbURL, sbKey, "profiles", &profiles); err != nil {
		log.Fatal(err)
	}
	log.Printf("Found %d profiles", len(profiles))

	// 2. Insert Profiles (and Users if needed)
	for _, p := range profiles {
		// Ensure User Exists
		var exists bool
		pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)", p.ID).Scan(&exists)
		if !exists {
			// Create placeholder user
			placeholderEmail := fmt.Sprintf("imported_%s@sojorn.com", p.ID[:8])
			_, err := pool.Exec(ctx, `
				INSERT INTO users (id, email, encrypted_password, created_at)
				VALUES ($1, $2, 'placeholder_hash', $3)
			`, p.ID, placeholderEmail, p.CreatedAt)
			if err != nil {
				log.Printf("Failed to create user for profile %s: %v", p.Handle, err)
				continue
			}
		}

		// Upsert Profile
		_, err := pool.Exec(ctx, `
			INSERT INTO profiles (id, handle, display_name, bio, avatar_url, is_official, is_private, beacon_enabled, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
			ON CONFLICT (id) DO UPDATE SET
				handle = EXCLUDED.handle,
				display_name = EXCLUDED.display_name,
				bio = EXCLUDED.bio,
				avatar_url = EXCLUDED.avatar_url,
				is_private = EXCLUDED.is_private
		`, p.ID, p.Handle, p.DisplayName, p.Bio, p.AvatarURL, p.IsOfficial, p.IsPrivate, p.BeaconEnabled, p.CreatedAt)

		if err != nil {
			log.Printf("Failed to import profile %s: %v", p.Handle, err)
		}
	}

	// 3. Fetch Posts
	log.Println("Fetching posts from Supabase...")
	var posts []SupabasePost
	if err := fetchSupabase(sbURL, sbKey, "posts", &posts); err != nil {
		log.Fatal(err)
	}
	log.Printf("Found %d posts", len(posts))

	// 4. Insert Posts
	for _, p := range posts {
		// Default values if missing
		status := "active"
		if p.Status != "" {
			status = p.Status
		}
		visibility := "public"
		if p.Visibility != "" {
			visibility = p.Visibility
		}

		_, err := pool.Exec(ctx, `
			INSERT INTO posts (id, author_id, body, image_url, category_id, status, visibility, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			ON CONFLICT (id) DO NOTHING
		`, p.ID, p.AuthorID, p.Body, p.ImageURL, p.CategoryID, status, visibility, p.CreatedAt)

		if err != nil {
			log.Printf("Failed to import post %s: %v", p.ID, err)
		}
	}

	log.Println("Migration complete.")
}

func fetchSupabase(url, key, table string, target interface{}) error {
	req, err := http.NewRequest("GET", fmt.Sprintf("%s/rest/v1/%s?select=*", url, table), nil)
	if err != nil {
		return err
	}
	req.Header.Add("apikey", key)
	req.Header.Add("Authorization", "Bearer "+key)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("supabase API error (%d): %s", resp.StatusCode, string(body))
	}

	return json.NewDecoder(resp.Body).Decode(target)
}
