// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

// Package services — Harmony Score Calculator
//
// This is an original implementation inspired (clean-room) by the trust level
// system design documented in Discourse (GPL-2.0). No code has been copied.
//
// Sojorn's Harmony Score (0–100) is a rolling, activity-based reputation
// signal. It differs from Discourse's trust levels in several key ways:
//
//   1. Beacon contributions (geo-alert accuracy) are a first-class signal.
//   2. Community reciprocity (events attended, follow acceptance) is weighted.
//   3. The score decays passively — we reward consistent presence, not peak activity.
//   4. Negative signals are time-limited: a report 6 months ago matters less.
//
// Tier thresholds (stable — not changed by recalculation):
//   new_user:    0–19    → "Seedling"     🌱
//   sprout:      20–39   → "Sprout"       🪴
//   trusted:     40–64   → "Trusted"      🌿
//   elder:       65–84   → "Elder"        🌾
//   established: 85–100  → "Established" 🌳

package services

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// HarmonyCalculator recalculates Harmony Scores for all active users.
// Run daily via a goroutine launched from main.go.
type HarmonyCalculator struct {
	pool *pgxpool.Pool
}

func NewHarmonyCalculator(pool *pgxpool.Pool) *HarmonyCalculator {
	return &HarmonyCalculator{pool: pool}
}

// ScoreUser recalculates the Harmony Score for a single user and persists it.
// This is the core algorithm — pure SQL, no application-layer loops.
func (hc *HarmonyCalculator) ScoreUser(ctx context.Context, userID string) error {
	// The algorithm runs as a single SQL query that:
	//   1. Counts positive signals from the last 30 days.
	//   2. Counts negative signals (with time-decay weighting).
	//   3. Adds a streak bonus for consecutive daily activity.
	//   4. Clamps to [0, 100] and writes to trust_state.
	//   5. Updates the tier based on fixed thresholds.
	//
	// All window periods are 30 days. Extending to 90 days is a config knob.
	const query = `
		WITH
		-- ── Positive Signals ──────────────────────────────────────────────

		posts_score AS (
			SELECT LEAST(COUNT(*) * 5, 25) AS pts
			FROM public.posts
			WHERE author_id = $1::uuid
			  AND created_at >= NOW() - INTERVAL '30 days'
			  AND deleted_at IS NULL
			  AND status = 'active'
		),

		reactions_received AS (
			SELECT LEAST(COUNT(*) * 2, 20) AS pts
			FROM public.post_reactions pr
			JOIN public.posts p ON pr.post_id = p.id
			WHERE p.author_id = $1::uuid
			  AND pr.user_id != $1::uuid   -- exclude self-reactions
			  AND pr.created_at >= NOW() - INTERVAL '30 days'
		),

		-- Beacon accuracy bonus: beacons created that received net confirms
		beacon_accuracy AS (
			SELECT LEAST(
				COALESCE(SUM(
					CASE WHEN (p.like_count - p.comment_count) >= 2 THEN 3 ELSE 0 END
				), 0), 15) AS pts
			FROM public.posts p
			WHERE p.author_id = $1::uuid
			  AND p.is_beacon = TRUE
			  AND p.created_at >= NOW() - INTERVAL '30 days'
			  AND p.deleted_at IS NULL
		),

		-- Event attendance (RSVP 'going' + event actually started)
		events_attended AS (
			SELECT LEAST(COUNT(*) * 5, 15) AS pts
			FROM public.event_rsvps er
			JOIN public.events ev ON er.event_id = ev.id
			WHERE er.user_id = $1::uuid
			  AND er.status = 'going'
			  AND ev.start_time >= NOW() - INTERVAL '30 days'
			  AND ev.start_time < NOW()    -- event has started
		),

		-- Days active in last 30 days (proxy: days with at least 1 post or reaction)
		activity_streak AS (
			SELECT LEAST(COUNT(DISTINCT activity_day), 30) AS pts
			FROM (
				SELECT DATE(created_at) AS activity_day
				FROM public.posts
				WHERE author_id = $1::uuid
				  AND created_at >= NOW() - INTERVAL '30 days'
				UNION ALL
				SELECT DATE(created_at)
				FROM public.post_reactions
				WHERE user_id = $1::uuid
				  AND created_at >= NOW() - INTERVAL '30 days'
			) days
		),

		-- Accepted mutual follows (reciprocity signal)
		mutual_follows AS (
			SELECT LEAST(COUNT(*) * 10, 20) AS pts
			FROM public.follows f1
			JOIN public.follows f2
			  ON f2.follower_id = f1.following_id
			  AND f2.following_id = f1.follower_id
			WHERE f1.follower_id = $1::uuid
			  AND f1.status = 'accepted'
			  AND f2.status = 'accepted'
			  AND f1.created_at >= NOW() - INTERVAL '30 days'
		),

		-- ── Negative Signals (time-decay: full weight in 30d, half at 60d) ─

		reports_against AS (
			-- Content reports upheld within last 60 days, with time decay
			SELECT COALESCE(SUM(
				CASE
					WHEN al.created_at >= NOW() - INTERVAL '30 days' THEN 15
					ELSE 8  -- half weight for older events
				END
			), 0) AS deduction
			FROM public.abuse_logs al
			WHERE al.blocked_id = $1::uuid
			  AND al.created_at >= NOW() - INTERVAL '60 days'
		),

		-- Blocks received (capped: ignore social disputes, flag persistent bad actors)
		blocks_received AS (
			SELECT LEAST(COUNT(*) * 3, 15) AS deduction
			FROM public.blocks
			WHERE blocked_id = $1::uuid
			  AND created_at >= NOW() - INTERVAL '30 days'
		),

		-- ── Score Composition ─────────────────────────────────────────────

		total AS (
			SELECT
				GREATEST(0, LEAST(
					(SELECT pts FROM posts_score)
					+ (SELECT pts FROM reactions_received)
					+ (SELECT pts FROM beacon_accuracy)
					+ (SELECT pts FROM events_attended)
					+ (SELECT pts FROM activity_streak)
					+ (SELECT pts FROM mutual_follows)
					- (SELECT deduction FROM reports_against)
					- (SELECT deduction FROM blocks_received),
					100
				)) AS raw_score
		)

		-- ── Persist & Tier Update ─────────────────────────────────────────
		UPDATE public.trust_state
		SET
			harmony_score        = (SELECT raw_score FROM total),
			tier = CASE
				WHEN (SELECT raw_score FROM total) >= 85 THEN 'established'
				WHEN (SELECT raw_score FROM total) >= 65 THEN 'elder'
				WHEN (SELECT raw_score FROM total) >= 40 THEN 'trusted'
				WHEN (SELECT raw_score FROM total) >= 20 THEN 'sprout'
				ELSE 'new_user'
			END,
			last_harmony_calc_at = NOW(),
			updated_at           = NOW()
		WHERE user_id = $1::uuid
	`

	_, err := hc.pool.Exec(ctx, query, userID)
	return err
}

// RunForAllActiveUsers recalculates scores for every user active in last 90 days.
// Intended to run as a daily background job.
func (hc *HarmonyCalculator) RunForAllActiveUsers(ctx context.Context) {
	log.Info().Msg("[Harmony] Starting daily recalculation")
	start := time.Now()

	rows, err := hc.pool.Query(ctx, `
		SELECT DISTINCT p.id::text
		FROM public.profiles p
		JOIN public.trust_state ts ON p.id = ts.user_id
		WHERE ts.last_harmony_calc_at < NOW() - INTERVAL '23 hours'
		   OR ts.last_harmony_calc_at IS NULL
	`)
	if err != nil {
		log.Error().Err(err).Msg("[Harmony] Failed to fetch users")
		return
	}
	defer rows.Close()

	var users []string
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err == nil {
			users = append(users, uid)
		}
	}
	rows.Close()

	processed, failed := 0, 0
	for _, uid := range users {
		if err := hc.ScoreUser(ctx, uid); err != nil {
			failed++
		} else {
			processed++
		}
	}

	log.Info().
		Int("processed", processed).
		Int("failed", failed).
		Dur("elapsed", time.Since(start)).
		Msg("[Harmony] Daily recalculation complete")
}

// ScheduleDailyRecalculation launches the harmony calculator on a 24h ticker.
// Call this from main.go after the DB pool is ready.
func (hc *HarmonyCalculator) ScheduleDailyRecalculation(ctx context.Context) {
	// Run once on startup (catches any missed calculations), then every 24h.
	go func() {
		// Small startup delay so the server is fully ready before the first run.
		time.Sleep(2 * time.Minute)
		hc.RunForAllActiveUsers(ctx)

		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				hc.RunForAllActiveUsers(ctx)
			case <-ctx.Done():
				return
			}
		}
	}()
}
