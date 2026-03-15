// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ContentFilter provides hard blocklist checking and strike tracking.
// Layer 0: Instant rejection for obvious slurs — post never saves.
type ContentFilter struct {
	pool     *pgxpool.Pool
	patterns []*blockedPattern
}

type blockedPattern struct {
	regex    *regexp.Regexp
	category string // "slur", "threat", etc.
	severity string // "hard" = instant block, "soft" = warning
}

// ContentCheckResult is returned by CheckContent.
type ContentCheckResult struct {
	Blocked  bool   `json:"blocked"`
	Category string `json:"category,omitempty"`
	Message  string `json:"message,omitempty"`
}

func NewContentFilter(pool *pgxpool.Pool) *ContentFilter {
	cf := &ContentFilter{pool: pool}
	cf.buildPatterns()
	return cf
}

// buildPatterns compiles regex patterns for slur detection.
// Uses word-boundary-aware patterns that catch common evasion tactics:
//   - Spacing (n i g g e r)
//   - Leetspeak (n1gg3r)
//   - Repeated chars (niggger)
//   - Partial masking (n*gger, n**ga)
func (cf *ContentFilter) buildPatterns() {
	type entry struct {
		pattern  string
		category string
		severity string
	}

	// Hard-blocked slurs — these NEVER get posted.
	// Patterns use (?i) for case-insensitive and flexible char matching.
	entries := []entry{
		// N-word and variants (no \b — catches concatenated slurs)
		{`(?i)n[i1!|l][gq9][gq9]+[e3a@]?[r0d]?s?`, "slur", "hard"},
		{`(?i)n[i1!|l][gq9]+[aA@]`, "slur", "hard"},
		{`(?i)n\s*[i1!]\s*[gq9]\s*[gq9]\s*[e3a]?\s*[r0]?`, "slur", "hard"},

		// F-word (homophobic slur) and variants
		{`(?i)f[a@4][gq9][gq9]?[o0]?[t7]?s?`, "slur", "hard"},
		{`(?i)f\s*[a@4]\s*[gq9]\s*[gq9]?\s*[o0]?\s*[t7]?`, "slur", "hard"},

		// K-word (anti-Jewish slur)
		{`(?i)k[i1][k]+[e3]?s?`, "slur", "hard"},

		// C-word (racial slur against Asian people)
		{`(?i)ch[i1]n[k]+s?`, "slur", "hard"},

		// S-word (anti-Hispanic slur)
		{`(?i)sp[i1][ck]+s?`, "slur", "hard"},

		// W-word (racial slur)
		{`(?i)w[e3][t7]b[a@]ck+s?`, "slur", "hard"},

		// R-word (ableist slur)
		{`(?i)r[e3]t[a@]rd+s?`, "slur", "hard"},

		// T-word (transphobic slur)
		{`(?i)tr[a@4]nn[yie]+s?`, "slur", "hard"},

		// Direct death/violence threats
		{`(?i)(i('?m| am) go(ing|nna)|i('?ll| will)) (to )?(kill|murder|shoot|stab|rape)`, "threat", "hard"},
		{`(?i)(kill|murder|shoot|stab|rape) (you|them|him|her|all)`, "threat", "hard"},
	}

	cf.patterns = make([]*blockedPattern, 0, len(entries))
	for _, e := range entries {
		re, err := regexp.Compile(e.pattern)
		if err != nil {
			fmt.Printf("Content filter: failed to compile pattern %q: %v\n", e.pattern, err)
			continue
		}
		cf.patterns = append(cf.patterns, &blockedPattern{
			regex:    re,
			category: e.category,
			severity: e.severity,
		})
	}

	fmt.Printf("Content filter: loaded %d patterns\n", len(cf.patterns))
}

// CheckContent scans text against the hard blocklist.
// Returns immediately on first match — no need to check all patterns.
func (cf *ContentFilter) CheckContent(text string) *ContentCheckResult {
	if text == "" {
		return &ContentCheckResult{Blocked: false}
	}

	// Normalize: collapse whitespace, strip zero-width chars
	normalized := normalizeText(text)

	for _, p := range cf.patterns {
		if p.severity == "hard" && p.regex.MatchString(normalized) {
			return &ContentCheckResult{
				Blocked:  true,
				Category: p.category,
				Message:  "This content contains language that isn't allowed on Sojorn. Please revise your post.",
			}
		}
	}

	return &ContentCheckResult{Blocked: false}
}

// RecordStrike records a content violation strike against a user.
// Strike escalation:
//
//	1-2 strikes: warning (post blocked, user informed)
//	3 strikes:   24-hour posting suspension
//	5 strikes:   7-day suspension
//	7+ strikes:  permanent ban
func (cf *ContentFilter) RecordStrike(ctx context.Context, userID uuid.UUID, category, content string) (int, string, error) {
	return cf.RecordStrikeWithIP(ctx, userID, category, content, "")
}

// RecordStrikeWithIP records a strike and logs the IP address for ban evasion prevention.
func (cf *ContentFilter) RecordStrikeWithIP(ctx context.Context, userID uuid.UUID, category, content, clientIP string) (int, string, error) {
	// Insert strike
	_, err := cf.pool.Exec(ctx, `
		INSERT INTO content_strikes (user_id, category, content_snippet, created_at)
		VALUES ($1, $2, $3, NOW())
	`, userID, category, truncate(content, 100))
	if err != nil {
		return 0, "", fmt.Errorf("failed to record strike: %w", err)
	}

	// Count recent strikes (last 30 days)
	var count int
	err = cf.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM content_strikes
		WHERE user_id = $1 AND created_at > NOW() - INTERVAL '30 days'
	`, userID).Scan(&count)
	if err != nil {
		return 0, "", fmt.Errorf("failed to count strikes: %w", err)
	}

	// Determine consequence
	consequence := "warning"
	switch {
	case count >= 7:
		consequence = "ban"
		cf.pool.Exec(ctx, `UPDATE users SET status = 'banned' WHERE id = $1`, userID)
		// Revoke ALL refresh tokens immediately so the user is logged out
		cf.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1`, userID)
		// Jail all their content
		cf.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		cf.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		// Log IP for ban evasion prevention
		if clientIP != "" {
			cf.pool.Exec(ctx, `
				INSERT INTO banned_ips (ip_address, user_id, reason, banned_at)
				VALUES ($1, $2, $3, NOW())
			`, clientIP, userID, fmt.Sprintf("auto-ban: %d strikes in 30 days", count))
		}
		// Audit trail
		cf.pool.Exec(ctx, `INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by) VALUES ($1, 'active', 'banned', $2, NULL)`,
			userID, fmt.Sprintf("auto-ban: %d strikes in 30 days", count))
		fmt.Printf("Content filter: user %s BANNED (%d strikes), IP %s logged\n", userID, count, clientIP)
	case count >= 5:
		consequence = "suspend_7d"
		suspendUntil := time.Now().Add(7 * 24 * time.Hour)
		cf.pool.Exec(ctx, `UPDATE users SET status = 'suspended', suspended_until = $2 WHERE id = $1`, userID, suspendUntil)
		cf.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		cf.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		// Audit trail
		cf.pool.Exec(ctx, `INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by) VALUES ($1, 'active', 'suspended', $2, NULL)`,
			userID, fmt.Sprintf("auto-suspend 7d: %d strikes in 30 days", count))
		fmt.Printf("Content filter: user %s suspended 7 days (%d strikes)\n", userID, count)
	case count >= 3:
		consequence = "suspend_24h"
		suspendUntil := time.Now().Add(24 * time.Hour)
		cf.pool.Exec(ctx, `UPDATE users SET status = 'suspended', suspended_until = $2 WHERE id = $1`, userID, suspendUntil)
		cf.pool.Exec(ctx, `UPDATE posts SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		cf.pool.Exec(ctx, `UPDATE comments SET status = 'jailed' WHERE author_id = $1 AND status = 'active' AND deleted_at IS NULL`, userID)
		// Audit trail
		cf.pool.Exec(ctx, `INSERT INTO user_status_history (user_id, old_status, new_status, reason, changed_by) VALUES ($1, 'active', 'suspended', $2, NULL)`,
			userID, fmt.Sprintf("auto-suspend 24h: %d strikes in 30 days", count))
		fmt.Printf("Content filter: user %s suspended 24h (%d strikes)\n", userID, count)
	default:
		fmt.Printf("Content filter: user %s warning (%d strikes)\n", userID, count)
	}

	return count, consequence, nil
}

// GetUserStrikes returns the number of recent strikes for a user.
func (cf *ContentFilter) GetUserStrikes(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := cf.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM content_strikes
		WHERE user_id = $1 AND created_at > NOW() - INTERVAL '30 days'
	`, userID).Scan(&count)
	return count, err
}

// normalizeText strips common evasion characters and collapses spacing.
func normalizeText(text string) string {
	// Remove zero-width characters
	text = strings.ReplaceAll(text, "\u200b", "") // zero-width space
	text = strings.ReplaceAll(text, "\u200c", "") // zero-width non-joiner
	text = strings.ReplaceAll(text, "\u200d", "") // zero-width joiner
	text = strings.ReplaceAll(text, "\ufeff", "") // BOM

	// Remove common separator characters used to evade filters
	for _, ch := range []string{".", "-", "_", "*", "|"} {
		text = strings.ReplaceAll(text, ch, "")
	}

	return text
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen]
}
