// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

func main() {
	// Try to load .env, but don't fail if missing (env vars might be set manually)
	_ = godotenv.Load("../../.env")

	// Get DB URL from env
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		log.Fatal("DATABASE_URL is required")
	}

	fmt.Println("Connecting to DB...")
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping DB: %v", err)
	}
	fmt.Println("Connected!")

	queries := []string{
		"ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false;",
		"ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT false;",
		"ALTER TABLE public.follows ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'accepted';",
		// Fix constraint if missing
		`DO $$ 
		BEGIN 
			IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'follows_status_check') THEN 
				ALTER TABLE public.follows 
				ADD CONSTRAINT follows_status_check CHECK (status IN ('pending', 'accepted')); 
			END IF; 
		END $$;`,
	}

	for _, q := range queries {
		fmt.Printf("Running: %s...\n", q)
		_, err := db.Exec(q)
		if err != nil {
			fmt.Printf("Error (might be okay if exists): %v\n", err)
		} else {
			fmt.Println("Success.")
		}
	}
	fmt.Println("Done.")
}
