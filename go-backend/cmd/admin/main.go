// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"golang.org/x/crypto/bcrypt"
)

// commonPasswords is a hardcoded list of the top-20 most common passwords.
var commonPasswords = map[string]struct{}{
	"password":    {},
	"12345678":    {},
	"qwerty":      {},
	"abc123":      {},
	"monkey":      {},
	"1234567":     {},
	"letmein":     {},
	"trustno1":    {},
	"dragon":      {},
	"baseball":    {},
	"iloveyou":    {},
	"master":      {},
	"sunshine":    {},
	"ashley":      {},
	"michael":     {},
	"shadow":      {},
	"123123":      {},
	"654321":      {},
	"superman":    {},
	"qazwsx":      {},
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "create-admin":
		cmdCreateAdmin(os.Args[2:])
	case "create-invite":
		cmdCreateInvite(os.Args[2:])
	case "reset-password":
		cmdResetPassword(os.Args[2:])
	case "list-extensions":
		cmdListExtensions(os.Args[2:])
	case "toggle-extension":
		cmdToggleExtension(os.Args[2:])
	case "validate-config":
		cmdValidateConfig(os.Args[2:])
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage: admin <command> [flags]

Commands:
  create-admin     Create an admin user account
  create-invite    Generate an invite token for registration
  reset-password   Reset a user's password
  list-extensions  List all registered extensions
  toggle-extension Enable or disable an extension
  validate-config  Check configuration and connectivity
`)
}

// ---------- create-admin ----------

func cmdCreateAdmin(args []string) {
	fs := flag.NewFlagSet("create-admin", flag.ExitOnError)
	handle := fs.String("handle", "", "Handle for the admin user (required)")
	email := fs.String("email", "", "Email address (required)")
	password := fs.String("password", "", "Password (required, min 8 chars)")
	fs.Parse(args)

	if *handle == "" || *email == "" || *password == "" {
		fmt.Fprintln(os.Stderr, "Error: --handle, --email, and --password are all required")
		fs.Usage()
		os.Exit(1)
	}

	if err := validatePassword(*password); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(*password), 10)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error hashing password: %v\n", err)
		os.Exit(1)
	}

	pool := mustConnect()
	defer pool.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	userID := uuid.New()
	now := time.Now().UTC()

	tx, err := pool.Begin(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error starting transaction: %v\n", err)
		os.Exit(1)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO public.users (id, email, encrypted_password, status, mfa_enabled, created_at, updated_at)
		VALUES ($1, $2, $3, 'active', false, $4, $4)
	`, userID, *email, string(hashedBytes), now)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") {
			fmt.Fprintln(os.Stderr, "Error: a user with that email already exists")
		} else {
			fmt.Fprintf(os.Stderr, "Error creating user: %v\n", err)
		}
		os.Exit(1)
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO public.profiles (id, handle, display_name, role, is_verified, is_official, has_completed_onboarding)
		VALUES ($1, $2, $3, 'admin', true, true, true)
	`, userID, *handle, *handle)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") {
			fmt.Fprintln(os.Stderr, "Error: a user with that handle already exists")
		} else {
			fmt.Fprintf(os.Stderr, "Error creating profile: %v\n", err)
		}
		os.Exit(1)
	}

	if err := tx.Commit(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error committing transaction: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Admin account created: @%s\n", *handle)
}

// ---------- create-invite ----------

func cmdCreateInvite(args []string) {
	fs := flag.NewFlagSet("create-invite", flag.ExitOnError)
	expiresIn := fs.String("expires", "", "Optional expiry duration (e.g. 24h, 7d). Empty = no expiry")
	fs.Parse(args)

	pool := mustConnect()
	defer pool.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var expiresAt *time.Time
	if *expiresIn != "" {
		dur := *expiresIn
		// Support "d" suffix for days
		if strings.HasSuffix(dur, "d") {
			days := dur[:len(dur)-1]
			var n int
			if _, err := fmt.Sscanf(days, "%d", &n); err != nil {
				fmt.Fprintf(os.Stderr, "Error: invalid duration %q\n", *expiresIn)
				os.Exit(1)
			}
			t := time.Now().Add(time.Duration(n) * 24 * time.Hour)
			expiresAt = &t
		} else {
			d, err := time.ParseDuration(dur)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: invalid duration %q: %v\n", *expiresIn, err)
				os.Exit(1)
			}
			t := time.Now().Add(d)
			expiresAt = &t
		}
	}

	var token string
	err := pool.QueryRow(ctx,
		`INSERT INTO invite_tokens (expires_at) VALUES ($1) RETURNING token`,
		expiresAt).Scan(&token)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating invite token: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Invite token: %s\n", token)
	if expiresAt != nil {
		fmt.Printf("Expires at:   %s\n", expiresAt.Format(time.RFC3339))
	} else {
		fmt.Println("Expires at:   never")
	}
}

// ---------- reset-password ----------

func cmdResetPassword(args []string) {
	fs := flag.NewFlagSet("reset-password", flag.ExitOnError)
	handle := fs.String("handle", "", "Handle of the user (required)")
	password := fs.String("password", "", "New password (required, min 8 chars)")
	fs.Parse(args)

	if *handle == "" || *password == "" {
		fmt.Fprintln(os.Stderr, "Error: --handle and --password are both required")
		fs.Usage()
		os.Exit(1)
	}

	if err := validatePassword(*password); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(*password), 10)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error hashing password: %v\n", err)
		os.Exit(1)
	}

	pool := mustConnect()
	defer pool.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err = pool.Exec(ctx, `
		UPDATE public.users SET encrypted_password = $1, updated_at = NOW()
		WHERE id = (SELECT id FROM public.profiles WHERE handle = $2)
	`, string(hashedBytes), *handle)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error updating password: %v\n", err)
		os.Exit(1)
	}

	// Always print success regardless of whether handle exists (don't leak info)
	fmt.Println("Password updated successfully")
}

// ---------- list-extensions ----------

func cmdListExtensions(args []string) {
	fs := flag.NewFlagSet("list-extensions", flag.ExitOnError)
	fs.Parse(args)

	pool := mustConnect()
	defer pool.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	rows, err := pool.Query(ctx, `SELECT id, name, enabled FROM instance_extensions ORDER BY id`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error querying extensions: %v\n", err)
		os.Exit(1)
	}
	defer rows.Close()

	found := false
	for rows.Next() {
		var id, name string
		var enabled bool
		if err := rows.Scan(&id, &name, &enabled); err != nil {
			fmt.Fprintf(os.Stderr, "Error scanning row: %v\n", err)
			os.Exit(1)
		}
		status := "disabled"
		if enabled {
			status = "enabled"
		}
		fmt.Printf("[%s]  %s — %s\n", status, id, name)
		found = true
	}
	if !found {
		fmt.Println("No extensions registered.")
	}
}

// ---------- toggle-extension ----------

func cmdToggleExtension(args []string) {
	fs := flag.NewFlagSet("toggle-extension", flag.ExitOnError)
	id := fs.String("id", "", "Extension ID (required)")
	enable := fs.Bool("enable", false, "Enable the extension")
	disable := fs.Bool("disable", false, "Disable the extension")
	fs.Parse(args)

	if *id == "" {
		fmt.Fprintln(os.Stderr, "Error: --id is required")
		fs.Usage()
		os.Exit(1)
	}

	if *enable == *disable {
		fmt.Fprintln(os.Stderr, "Error: specify exactly one of --enable or --disable")
		fs.Usage()
		os.Exit(1)
	}

	enabled := *enable

	pool := mustConnect()
	defer pool.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	tag := "enabled_at"
	if !enabled {
		tag = "disabled_at"
	}

	_, err := pool.Exec(ctx, fmt.Sprintf(
		`UPDATE instance_extensions SET enabled = $1, %s = NOW() WHERE id = $2`, tag),
		enabled, *id)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error updating extension: %v\n", err)
		os.Exit(1)
	}

	action := "disabled"
	if enabled {
		action = "enabled"
	}
	fmt.Printf("Extension %q %s\n", *id, action)
}

// ---------- validate-config ----------

func cmdValidateConfig(args []string) {
	fs := flag.NewFlagSet("validate-config", flag.ExitOnError)
	fs.Parse(args)

	cfg := config.LoadConfig()
	allOK := true

	// DATABASE_URL
	if cfg.DatabaseURL == "" {
		fmt.Println("Database URL: NOT SET")
		allOK = false
	} else {
		fmt.Print("Database: ")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
		if err != nil {
			fmt.Printf("FAILED (%v)\n", err)
			allOK = false
		} else {
			if err := pool.Ping(ctx); err != nil {
				fmt.Printf("FAILED (%v)\n", err)
				allOK = false
			} else {
				fmt.Println("OK")
			}
			pool.Close()
		}
		cancel()
	}

	// JWT_SECRET
	if cfg.JWTSecret == "" {
		fmt.Println("JWT Secret: NOT SET")
		allOK = false
	} else if len(cfg.JWTSecret) < 32 {
		fmt.Printf("JWT Secret: TOO SHORT (%d chars, need >= 32)\n", len(cfg.JWTSecret))
		allOK = false
	} else {
		fmt.Println("JWT Secret: OK")
	}

	// SMTP
	if cfg.SMTPHost == "" {
		fmt.Println("SMTP: not configured (optional)")
	} else {
		addr := fmt.Sprintf("%s:%d", cfg.SMTPHost, cfg.SMTPPort)
		fmt.Printf("SMTP (%s): ", addr)
		conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			fmt.Printf("FAILED (%v)\n", err)
		} else {
			conn.Close()
			fmt.Println("OK")
		}
	}

	// Optional services summary
	fmt.Println()
	fmt.Println("Optional services:")
	printConfigured("  R2 Storage", cfg.R2AccountID != "")
	printConfigured("  Firebase Push", cfg.FirebaseCredentialsFile != "")
	printConfigured("  AI Gateway", cfg.AIGatewayURL != "")
	printConfigured("  SightEngine Moderation", cfg.SightEngineUser != "")
	printConfigured("  Ollama", cfg.OllamaURL != "http://localhost:11434" && cfg.OllamaURL != "")
	printConfigured("  Eventbrite", cfg.EventbriteAPIKey != "")
	printConfigured("  Ticketmaster", cfg.TicketmasterAPIKey != "")

	if !allOK {
		os.Exit(1)
	}
}

// ---------- helpers ----------

func printConfigured(label string, configured bool) {
	if configured {
		fmt.Printf("%s: configured\n", label)
	} else {
		fmt.Printf("%s: not configured\n", label)
	}
}

func validatePassword(pw string) error {
	if len(pw) < 8 {
		return fmt.Errorf("password must be at least 8 characters")
	}
	if _, found := commonPasswords[strings.ToLower(pw)]; found {
		return fmt.Errorf("password is too common; choose a stronger one")
	}
	return nil
}

func mustConnect() *pgxpool.Pool {
	cfg := config.LoadConfig()
	if cfg.DatabaseURL == "" {
		fmt.Fprintln(os.Stderr, "Error: DATABASE_URL is not set")
		os.Exit(1)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
		os.Exit(1)
	}

	if err := pool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error pinging database: %v\n", err)
		os.Exit(1)
	}

	return pool
}
