// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package repository

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

func TestCreatePost_TransactionRollback(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}

	authorIDStr := os.Getenv("TEST_AUTHOR_ID")
	if authorIDStr == "" {
		t.Skip("TEST_AUTHOR_ID not set")
	}

	authorID, err := uuid.Parse(authorIDStr)
	if err != nil {
		t.Fatalf("invalid TEST_AUTHOR_ID: %v", err)
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}
	defer pool.Close()

	var exists bool
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id = $1)`, authorID).Scan(&exists); err != nil {
		t.Fatalf("failed to verify author profile: %v", err)
	}
	if !exists {
		t.Skip("TEST_AUTHOR_ID not found in profiles")
	}

	triggerBase := strings.ReplaceAll(uuid.NewString(), "-", "")
	triggerName := fmt.Sprintf("test_fail_post_metrics_%s", triggerBase)
	funcName := fmt.Sprintf("test_fail_post_metrics_fn_%s", triggerBase)

	createFunction := fmt.Sprintf(`
        CREATE OR REPLACE FUNCTION %s() RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION 'post_metrics insert blocked';
        END;
        $$ LANGUAGE plpgsql;
    `, funcName)

	if _, err := pool.Exec(ctx, createFunction); err != nil {
		t.Skipf("skipping: failed to create trigger function: %v", err)
	}

	createTrigger := fmt.Sprintf(`
        CREATE TRIGGER %s BEFORE INSERT ON public.post_metrics
        FOR EACH ROW EXECUTE FUNCTION %s();
    `, triggerName, funcName)

	if _, err := pool.Exec(ctx, createTrigger); err != nil {
		_ = pool.Exec(ctx, fmt.Sprintf(`DROP FUNCTION IF EXISTS %s()`, funcName))
		t.Skipf("skipping: failed to create trigger: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, fmt.Sprintf(`DROP TRIGGER IF EXISTS %s ON public.post_metrics`, triggerName))
		_, _ = pool.Exec(ctx, fmt.Sprintf(`DROP FUNCTION IF EXISTS %s()`, funcName))
	})

	repo := NewPostRepository(pool)
	post := &models.Post{
		AuthorID:       authorID,
		Body:           "rollback test",
		Status:         "active",
		BodyFormat:     "plain",
		Tags:           []string{},
		IsBeacon:       false,
		Confidence:     0.5,
		IsActiveBeacon: false,
		AllowChain:     true,
		Visibility:     "public",
	}

	err = repo.CreatePost(ctx, post)
	if err == nil {
		t.Fatalf("expected CreatePost to fail due to trigger, got nil")
	}

	var count int
	if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM public.posts WHERE id = $1`, post.ID).Scan(&count); err != nil {
		t.Fatalf("failed to verify rollback: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected post rollback, found %d rows", count)
	}
}
