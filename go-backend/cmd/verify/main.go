package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on env vars")
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL required")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v", err)
	}
	defer pool.Close()

	repo := repository.NewCategoryRepository(pool)
	userRepo := repository.NewUserRepository(pool)
	ctx := context.Background()

	// 1. Create a Test User
	email := fmt.Sprintf("test_verify_%d@example.com", time.Now().Unix())
	log.Printf("Creating test user: %s", email)

	user := &models.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: "hashedpass",
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	if err := userRepo.CreateUser(ctx, user); err != nil {
		log.Fatalf("Failed to create user: %v", err)
	}

	// Create Profile for user (triggers needed for follows?)
	// Basic profile creation
	_, err = pool.Exec(ctx, "INSERT INTO profiles (id, handle, display_name) VALUES ($1, $2, $3)", user.ID, "h"+user.ID.String()[:8], "Test User")
	if err != nil {
		log.Fatalf("Failed to create profile: %v", err)
	}

	// 2. Get a Category
	cats, err := repo.GetAllCategories(ctx)
	if err != nil {
		log.Fatalf("Failed to get categories: %v", err)
	}
	if len(cats) == 0 {
		log.Fatalf("No categories found! Seeder failed?")
	}
	targetCat := cats[0]
	log.Printf("Testing with category: %s (Official: %v)", targetCat.Name, targetCat.OfficialAccountID)

	if targetCat.OfficialAccountID == nil {
		log.Fatalf("Category %s has no official account!", targetCat.Name)
	}

	// 3. Enable Category
	log.Println("Enabling category...")
	err = repo.SetUserCategorySettings(ctx, user.ID.String(), []repository.CategorySettingInput{
		{CategoryID: targetCat.ID, Enabled: true},
	})
	if err != nil {
		log.Fatalf("Failed to set settings: %v", err)
	}

	// 4. Verify Follow
	log.Println("Verifying follow...")
	isFollowing, err := userRepo.IsFollowing(ctx, user.ID.String(), *targetCat.OfficialAccountID)
	if err != nil {
		log.Fatalf("Failed to check follow: %v", err)
	}

	if isFollowing {
		log.Println("SUCCESS: User is following official account!")
	} else {
		log.Fatal("FAILURE: User is NOT following official account.")
	}

	// Cleanup
	pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user.ID)
}
