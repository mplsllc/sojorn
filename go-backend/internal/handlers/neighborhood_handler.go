// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
)

// NeighborhoodHandler manages neighborhood detection, on-demand creation,
// and user auto-join.
type NeighborhoodHandler struct {
	pool     *pgxpool.Pool
	overpass *services.OverpassService
}

func NewNeighborhoodHandler(pool *pgxpool.Pool) *NeighborhoodHandler {
	return &NeighborhoodHandler{
		pool:     pool,
		overpass: services.NewOverpassService(),
	}
}

// Detect finds (or creates) the neighborhood for the given coordinates,
// creates a group on-demand if needed, and auto-joins the user.
//
// GET /neighborhoods/detect?lat=...&long=...
func (h *NeighborhoodHandler) Detect(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	lat, err := strconv.ParseFloat(c.Query("lat"), 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat required"})
		return
	}
	lng, err := strconv.ParseFloat(c.Query("long"), 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "long required"})
		return
	}

	ctx := c.Request.Context()

	// ── Step 1: Check if we already have a cached neighborhood seed nearby ──
	seed, err := h.findNearbySeed(ctx, lat, lng, 1500) // 1.5km search radius
	if err != nil {
		log.Printf("[Neighborhood] DB lookup error: %v", err)
	}

	// ── Step 2: If no cached seed, query Overpass API ───────────────────────
	if seed == nil {
		seed, err = h.detectViaOverpass(ctx, lat, lng)
		if err != nil {
			log.Printf("[Neighborhood] Overpass error: %v", err)
			// Fall back to a generic neighborhood name from Nominatim
			seed, err = h.fallbackGeneric(ctx, lat, lng)
			if err != nil {
				log.Printf("[Neighborhood] Fallback error: %v", err)
				c.JSON(http.StatusNotFound, gin.H{"error": "could not determine neighborhood"})
				return
			}
		}
	}

	if seed == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no neighborhood found for this location"})
		return
	}

	// ── Step 3: Ensure the seed has an associated group ─────────────────────
	isNew := false
	if seed.GroupID == nil {
		groupID, err := h.createNeighborhoodGroup(ctx, seed)
		if err != nil {
			log.Printf("[Neighborhood] Create group error: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create neighborhood group"})
			return
		}
		seed.GroupID = &groupID
		isNew = true
	}

	// ── Step 4: Auto-join user to the group ─────────────────────────────────
	justJoined, err := h.autoJoin(ctx, *seed.GroupID, userID)
	if err != nil {
		log.Printf("[Neighborhood] Auto-join error: %v", err)
	}

	// ── Step 5: Fetch group details for response ────────────────────────────
	var groupName string
	var memberCount int
	h.pool.QueryRow(ctx, `SELECT name, member_count FROM groups WHERE id = $1`, *seed.GroupID).Scan(&groupName, &memberCount)

	var boardPostCount int
	_ = h.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM board_entries
		WHERE is_active = TRUE
		  AND ST_DWithin(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
	`, seed.Lng, seed.Lat, seed.RadiusMeters).Scan(&boardPostCount)

	var groupPostCount int
	_ = h.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM group_posts
		WHERE group_id = $1 AND is_deleted = FALSE
	`, *seed.GroupID).Scan(&groupPostCount)

	c.JSON(http.StatusOK, gin.H{
		"neighborhood": gin.H{
			"id":            seed.ID,
			"name":          seed.Name,
			"city":          seed.City,
			"state":         seed.State,
			"zip_code":      seed.ZipCode,
			"country":       seed.Country,
			"lat":           seed.Lat,
			"lng":           seed.Lng,
			"radius_meters": seed.RadiusMeters,
		},
		"group_id":         seed.GroupID,
		"group_name":       groupName,
		"member_count":     memberCount,
		"board_post_count": boardPostCount,
		"group_post_count": groupPostCount,
		"is_new":           isNew,
		"just_joined":      justJoined,
	})
}

// GetCurrent returns the user's current neighborhood (most recent join).
// GET /neighborhoods/current
func (h *NeighborhoodHandler) GetCurrent(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	ctx := c.Request.Context()

	var seedID, groupID uuid.UUID
	var name, city, state, zipCode, country, groupName string
	var lat, lng float64
	var radiusMeters, memberCount int
	err = h.pool.QueryRow(ctx, `
		SELECT ns.id, ns.name, ns.city, ns.state, COALESCE(ns.zip_code, ''), ns.country, ns.lat, ns.lng, ns.radius_meters,
		       g.id, g.name, g.member_count
		FROM neighborhood_seeds ns
		JOIN groups g ON g.id = ns.group_id
		JOIN group_members gm ON gm.group_id = g.id
		WHERE gm.user_id = $1 AND g.type = 'neighborhood' AND g.is_active = TRUE
		ORDER BY gm.joined_at DESC
		LIMIT 1
	`, userID).Scan(&seedID, &name, &city, &state, &zipCode, &country, &lat, &lng, &radiusMeters,
		&groupID, &groupName, &memberCount)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no neighborhood found"})
		return
	}

	var boardPostCount int
	_ = h.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM board_entries
		WHERE is_active = TRUE
		  AND ST_DWithin(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
	`, lng, lat, radiusMeters).Scan(&boardPostCount)

	var groupPostCount int
	_ = h.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM group_posts
		WHERE group_id = $1 AND is_deleted = FALSE
	`, groupID).Scan(&groupPostCount)

	c.JSON(http.StatusOK, gin.H{
		"neighborhood": gin.H{
			"id":            seedID,
			"name":          name,
			"city":          city,
			"state":         state,
			"zip_code":      zipCode,
			"country":       country,
			"lat":           lat,
			"lng":           lng,
			"radius_meters": radiusMeters,
		},
		"group_id":         groupID,
		"group_name":       groupName,
		"member_count":     memberCount,
		"board_post_count": boardPostCount,
		"group_post_count": groupPostCount,
	})
}

// ─── Internal helpers ─────────────────────────────────────────────────────

// findNearbySeed checks if we already have a cached neighborhood within range.
func (h *NeighborhoodHandler) findNearbySeed(ctx context.Context, lat, lng float64, radiusMeters int) (*seedRow, error) {
	var s seedRow
	err := h.pool.QueryRow(ctx, `
		SELECT id, name, city, state, COALESCE(zip_code, ''), country, lat, lng, radius_meters, group_id
		FROM neighborhood_seeds
		WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
		ORDER BY ST_Distance(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography) ASC
		LIMIT 1
	`, lng, lat, radiusMeters).Scan(
		&s.ID, &s.Name, &s.City, &s.State, &s.ZipCode, &s.Country, &s.Lat, &s.Lng, &s.RadiusMeters, &s.GroupID,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// detectViaOverpass queries the Overpass API and caches the result.
func (h *NeighborhoodHandler) detectViaOverpass(ctx context.Context, lat, lng float64) (*seedRow, error) {
	nr, err := h.overpass.DetectNeighborhood(ctx, lat, lng)
	if err != nil {
		return nil, err
	}
	if nr == nil {
		return nil, nil
	}

	// Get city/state/country from Nominatim
	city, state, country, zipCode, err := h.overpass.ReverseGeocodeCity(ctx, nr.Lat, nr.Lng)
	if err != nil {
		log.Printf("[Neighborhood] Nominatim fallback error: %v", err)
		// Continue with empty city/state — we still have the neighborhood name
	}
	if country == "" {
		country = "US"
	}

	// Cache the seed in the database
	return h.upsertSeed(ctx, nr.Name, city, state, zipCode, country, nr.Lat, nr.Lng, 1500)
}

// fallbackGeneric uses Nominatim alone to create a generic neighborhood
// when Overpass returns nothing (rural areas, etc).
func (h *NeighborhoodHandler) fallbackGeneric(ctx context.Context, lat, lng float64) (*seedRow, error) {
	city, state, country, zipCode, err := h.overpass.ReverseGeocodeCity(ctx, lat, lng)
	if err != nil {
		return nil, err
	}
	if city == "" {
		return nil, fmt.Errorf("no city found")
	}

	// Use the city name as the neighborhood name for rural/suburban areas
	name := city + " Area"
	return h.upsertSeed(ctx, name, city, state, zipCode, country, lat, lng, 5000)
}

// upsertSeed inserts or returns an existing seed.
func (h *NeighborhoodHandler) upsertSeed(ctx context.Context, name, city, state, zipCode, country string, lat, lng float64, radius int) (*seedRow, error) {
	var s seedRow
	err := h.pool.QueryRow(ctx, `
		INSERT INTO neighborhood_seeds (name, city, state, zip_code, country, lat, lng, radius_meters)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (name, city, state) DO UPDATE SET
			zip_code = EXCLUDED.zip_code,
			country = EXCLUDED.country
		RETURNING id, name, city, state, COALESCE(zip_code, ''), country, lat, lng, radius_meters, group_id
	`, name, city, state, zipCode, country, lat, lng, radius).Scan(
		&s.ID, &s.Name, &s.City, &s.State, &s.ZipCode, &s.Country, &s.Lat, &s.Lng, &s.RadiusMeters, &s.GroupID,
	)
	if err != nil {
		return nil, fmt.Errorf("upsert seed: %w", err)
	}
	return &s, nil
}

// createNeighborhoodGroup creates an open (non-encrypted) group for a neighborhood seed.
func (h *NeighborhoodHandler) createNeighborhoodGroup(ctx context.Context, seed *seedRow) (uuid.UUID, error) {
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)

	groupName := fmt.Sprintf("%s — %s", seed.Name, seed.City)
	description := fmt.Sprintf("Neighborhood board for %s in %s, %s", seed.Name, seed.City, seed.State)

	var groupID uuid.UUID
	var createdAt time.Time
	err = tx.QueryRow(ctx, `
		INSERT INTO groups (name, description, type, privacy, is_encrypted, member_count, key_version, category,
		                    location_center, radius_meters)
		VALUES ($1, $2, 'neighborhood', 'public', FALSE, 0, 0, 'general',
		        ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5)
		RETURNING id, created_at
	`, groupName, description, seed.Lng, seed.Lat, seed.RadiusMeters).Scan(&groupID, &createdAt)
	if err != nil {
		return uuid.Nil, fmt.Errorf("create group: %w", err)
	}

	// Link the seed to the group
	_, err = tx.Exec(ctx, `UPDATE neighborhood_seeds SET group_id = $1 WHERE id = $2`, groupID, seed.ID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("link seed: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, err
	}

	return groupID, nil
}

// autoJoin adds a user to the neighborhood group. Returns true if they were newly added.
func (h *NeighborhoodHandler) autoJoin(ctx context.Context, groupID, userID uuid.UUID) (bool, error) {
	tag, err := h.pool.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (group_id, user_id) DO NOTHING
	`, groupID, userID)
	if err != nil {
		return false, err
	}

	justJoined := tag.RowsAffected() > 0
	if justJoined {
		// Update member count
		h.pool.Exec(ctx, `
			UPDATE groups SET member_count = (
				SELECT COUNT(*) FROM group_members WHERE group_id = $1
			) WHERE id = $1
		`, groupID)
	}

	return justJoined, nil
}

// SearchByZip returns neighborhood seeds matching a ZIP code.
// GET /neighborhoods/search?zip=55408
func (h *NeighborhoodHandler) SearchByZip(c *gin.Context) {
	zip := c.Query("zip")
	if zip == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "zip parameter required"})
		return
	}

	ctx := c.Request.Context()

	rows, err := h.pool.Query(ctx, `
		SELECT id, name, city, state, COALESCE(zip_code, ''), country, lat, lng, radius_meters
		FROM neighborhood_seeds
		WHERE zip_code = $1
		ORDER BY name
	`, zip)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
		return
	}
	defer rows.Close()

	var seeds []gin.H
	for rows.Next() {
		var id uuid.UUID
		var name, city, state, zipCode, country string
		var lat, lng float64
		var radius int
		if err := rows.Scan(&id, &name, &city, &state, &zipCode, &country, &lat, &lng, &radius); err != nil {
			continue
		}
		seeds = append(seeds, gin.H{
			"id":            id,
			"name":          name,
			"city":          city,
			"state":         state,
			"zip_code":      zipCode,
			"country":       country,
			"lat":           lat,
			"lng":           lng,
			"radius_meters": radius,
		})
	}

	// If exact ZIP match returned nothing, try prefix match (e.g. "554" -> multiple ZIPs)
	if len(seeds) == 0 && len(zip) >= 3 {
		rows2, err := h.pool.Query(ctx, `
			SELECT id, name, city, state, COALESCE(zip_code, ''), country, lat, lng, radius_meters
			FROM neighborhood_seeds
			WHERE zip_code LIKE $1
			ORDER BY name
			LIMIT 20
		`, zip+"%")
		if err == nil {
			defer rows2.Close()
			for rows2.Next() {
				var id uuid.UUID
				var name, city, state, zipCode, country string
				var lat, lng float64
				var radius int
				if err := rows2.Scan(&id, &name, &city, &state, &zipCode, &country, &lat, &lng, &radius); err != nil {
					continue
				}
				seeds = append(seeds, gin.H{
					"id":            id,
					"name":          name,
					"city":          city,
					"state":         state,
					"zip_code":      zipCode,
					"country":       country,
					"lat":           lat,
					"lng":           lng,
					"radius_meters": radius,
				})
			}
		}
	}

	if seeds == nil {
		seeds = []gin.H{}
	}

	c.JSON(http.StatusOK, gin.H{"neighborhoods": seeds})
}

// Choose lets a user explicitly pick their home neighborhood.
// Enforces a 30-day cooldown between changes.
// POST /neighborhoods/choose  { "neighborhood_id": "uuid" }
func (h *NeighborhoodHandler) Choose(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var body struct {
		NeighborhoodID string `json:"neighborhood_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "neighborhood_id required"})
		return
	}

	neighborhoodID, err := uuid.Parse(body.NeighborhoodID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid neighborhood_id"})
		return
	}

	ctx := c.Request.Context()

	// Check 30-day cooldown
	var changedAt *time.Time
	err = h.pool.QueryRow(ctx, `
		SELECT neighborhood_changed_at FROM profiles WHERE id = $1
	`, userID).Scan(&changedAt)
	if err != nil && err != pgx.ErrNoRows {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check cooldown"})
		return
	}

	if changedAt != nil {
		nextAllowed := changedAt.Add(30 * 24 * time.Hour) // exactly 30 days
		if time.Now().Before(nextAllowed) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":           "You can only change your neighborhood once every 30 days",
				"changed_at":      changedAt.Format(time.RFC3339),
				"next_allowed_at": nextAllowed.Format(time.RFC3339),
			})
			return
		}
	}

	// Verify the neighborhood seed exists
	var seed seedRow
	err = h.pool.QueryRow(ctx, `
		SELECT id, name, city, state, COALESCE(zip_code, ''), country, lat, lng, radius_meters, group_id
		FROM neighborhood_seeds
		WHERE id = $1
	`, neighborhoodID).Scan(
		&seed.ID, &seed.Name, &seed.City, &seed.State, &seed.ZipCode, &seed.Country,
		&seed.Lat, &seed.Lng, &seed.RadiusMeters, &seed.GroupID,
	)
	if err == pgx.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "neighborhood not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to look up neighborhood"})
		return
	}

	// Ensure the seed has a group
	if seed.GroupID == nil {
		groupID, err := h.createNeighborhoodGroup(ctx, &seed)
		if err != nil {
			log.Printf("[Neighborhood] Create group error: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create neighborhood group"})
			return
		}
		seed.GroupID = &groupID
	}

	// Auto-join user to the new neighborhood group
	_, _ = h.autoJoin(ctx, *seed.GroupID, userID)

	// Update the user's home neighborhood and record the change timestamp
	now := time.Now()
	_, err = h.pool.Exec(ctx, `
		UPDATE profiles
		SET home_neighborhood_id = $1, neighborhood_changed_at = $2, neighborhood_onboarded = TRUE
		WHERE id = $3
	`, neighborhoodID, now, userID)
	if err != nil {
		log.Printf("[Neighborhood] Update profile error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save neighborhood choice"})
		return
	}

	// Get group details
	var groupName string
	var memberCount int
	h.pool.QueryRow(ctx, `SELECT name, member_count FROM groups WHERE id = $1`, *seed.GroupID).Scan(&groupName, &memberCount)

	c.JSON(http.StatusOK, gin.H{
		"neighborhood": gin.H{
			"id":            seed.ID,
			"name":          seed.Name,
			"city":          seed.City,
			"state":         seed.State,
			"zip_code":      seed.ZipCode,
			"country":       seed.Country,
			"lat":           seed.Lat,
			"lng":           seed.Lng,
			"radius_meters": seed.RadiusMeters,
		},
		"group_id":     seed.GroupID,
		"group_name":   groupName,
		"member_count": memberCount,
		"changed_at":   now.Format(time.RFC3339),
	})
}

// GetMyNeighborhood returns the user's chosen home neighborhood and onboarding status.
// GET /neighborhoods/mine
func (h *NeighborhoodHandler) GetMyNeighborhood(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	ctx := c.Request.Context()

	// First check onboarded flag (always available even without a home neighborhood)
	var onboarded bool
	_ = h.pool.QueryRow(ctx, `SELECT COALESCE(neighborhood_onboarded, FALSE) FROM profiles WHERE id = $1`, userID).Scan(&onboarded)

	var seedID uuid.UUID
	var name, city, state, zipCode, country string
	var lat, lng float64
	var radiusMeters int
	var groupID *uuid.UUID
	var changedAt *time.Time

	err = h.pool.QueryRow(ctx, `
		SELECT ns.id, ns.name, ns.city, ns.state, COALESCE(ns.zip_code, ''), ns.country,
		       ns.lat, ns.lng, ns.radius_meters, ns.group_id,
		       p.neighborhood_changed_at
		FROM profiles p
		JOIN neighborhood_seeds ns ON ns.id = p.home_neighborhood_id
		WHERE p.id = $1
	`, userID).Scan(
		&seedID, &name, &city, &state, &zipCode, &country,
		&lat, &lng, &radiusMeters, &groupID, &changedAt,
	)
	if err == pgx.ErrNoRows {
		// No home neighborhood set — return onboarded status only
		c.JSON(http.StatusOK, gin.H{"onboarded": onboarded})
		return
	}
	if err != nil {
		log.Printf("[Neighborhood] GetMyNeighborhood error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch neighborhood"})
		return
	}

	result := gin.H{
		"onboarded": onboarded,
		"neighborhood": gin.H{
			"id":            seedID,
			"name":          name,
			"city":          city,
			"state":         state,
			"zip_code":      zipCode,
			"country":       country,
			"lat":           lat,
			"lng":           lng,
			"radius_meters": radiusMeters,
		},
	}

	// If the seed has no group yet, create one now (lazy creation)
	if groupID == nil {
		seed := &seedRow{
			ID:           seedID,
			Name:         name,
			City:         city,
			State:        state,
			ZipCode:      zipCode,
			Country:      country,
			Lat:          lat,
			Lng:          lng,
			RadiusMeters: radiusMeters,
		}
		newGroupID, createErr := h.createNeighborhoodGroup(ctx, seed)
		if createErr != nil {
			log.Printf("[Neighborhood] GetMyNeighborhood lazy group creation error: %v", createErr)
		} else {
			groupID = &newGroupID
		}
	}

	// Always auto-join the user to their neighborhood group (idempotent — ON CONFLICT DO NOTHING)
	if groupID != nil {
		if _, joinErr := h.autoJoin(ctx, *groupID, userID); joinErr != nil {
			log.Printf("[Neighborhood] GetMyNeighborhood auto-join error: %v", joinErr)
		}
	}

	if groupID != nil {
		var groupName string
		var memberCount int
		var bannerUrl *string
		var groupDescription *string
		h.pool.QueryRow(ctx, `SELECT name, member_count, banner_url, description FROM groups WHERE id = $1`, *groupID).Scan(&groupName, &memberCount, &bannerUrl, &groupDescription)
		result["group_id"] = groupID
		result["group_name"] = groupName
		result["member_count"] = memberCount

		// Also nest group_id, banner_url, and description inside neighborhood for Flutter convenience
		if neigh, ok := result["neighborhood"].(gin.H); ok {
			neigh["group_id"] = groupID
			if bannerUrl != nil {
				neigh["banner_url"] = *bannerUrl
			}
			if groupDescription != nil {
				neigh["description"] = *groupDescription
			}
		}

		// Active now count (users with recent activity, excluding private profiles)
		var activeNow int
		_ = h.pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM group_members gm
			JOIN profiles p ON p.id = gm.user_id
			LEFT JOIN profile_privacy_settings ps ON ps.user_id = gm.user_id
			WHERE gm.group_id = $1
			  AND p.last_active_at > NOW() - INTERVAL '15 minutes'
			  AND (ps.show_activity_status IS NULL OR ps.show_activity_status = true)
			  AND (ps.is_private_profile IS NULL OR ps.is_private_profile = false)
		`, *groupID).Scan(&activeNow)
		result["active_now"] = activeNow

		// User's role in the neighborhood group
		var role string
		err := h.pool.QueryRow(ctx, `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`, *groupID, userID).Scan(&role)
		if err == nil {
			result["role"] = role
		}
	}

	if changedAt != nil {
		result["changed_at"] = changedAt.Format(time.RFC3339)
		nextAllowed := changedAt.Add(30 * 24 * time.Hour) // exactly 30 days
		result["next_change_allowed_at"] = nextAllowed.Format(time.RFC3339)
		result["can_change"] = time.Now().After(nextAllowed)
	} else {
		result["can_change"] = true
	}

	c.JSON(http.StatusOK, result)
}

// seedRow is an internal struct for scanning neighborhood_seeds rows.
type seedRow struct {
	ID           uuid.UUID
	Name         string
	City         string
	State        string
	ZipCode      string
	Country      string
	Lat          float64
	Lng          float64
	RadiusMeters int
	GroupID      *uuid.UUID
}
