package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type BeaconSearchHandler struct {
	pool *pgxpool.Pool
}

func NewBeaconSearchHandler(pool *pgxpool.Pool) *BeaconSearchHandler {
	return &BeaconSearchHandler{pool: pool}
}

// Search performs a combined search across beacons, board entries, and public groups.
// Private capsules and private social groups are never returned.
// GET /api/v1/beacon/search?q=&lat=&long=&radius=&type=all|beacons|board|groups
func (h *BeaconSearchHandler) Search(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	query := c.Query("q")
	searchType := c.DefaultQuery("type", "all")
	limitStr := c.DefaultQuery("limit", "20")
	limit, _ := strconv.Atoi(limitStr)
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	// Optional geo params for proximity sorting
	latStr := c.Query("lat")
	longStr := c.Query("long")
	radiusStr := c.DefaultQuery("radius", "50000")
	var lat, long float64
	var hasGeo bool
	if latStr != "" && longStr != "" {
		lat, _ = strconv.ParseFloat(latStr, 64)
		long, _ = strconv.ParseFloat(longStr, 64)
		hasGeo = true
	}
	radius, _ := strconv.Atoi(radiusStr)
	if radius <= 0 || radius > 100000 {
		radius = 50000
	}

	result := gin.H{}

	// ── Beacons (posts with is_beacon = true) ──────────────────────────
	if searchType == "all" || searchType == "beacons" {
		beacons := h.searchBeacons(c, userID, query, lat, long, radius, hasGeo, limit)
		result["beacons"] = beacons
	}

	// ── Board entries ──────────────────────────────────────────────────
	if searchType == "all" || searchType == "board" {
		entries := h.searchBoard(c, userID, query, lat, long, radius, hasGeo, limit)
		result["board_entries"] = entries
	}

	// ── Public groups (not encrypted, not private) ─────────────────────
	if searchType == "all" || searchType == "groups" {
		groups := h.searchPublicGroups(c, query, limit)
		result["groups"] = groups
	}

	c.JSON(http.StatusOK, result)
}

func (h *BeaconSearchHandler) searchBeacons(c *gin.Context, userID uuid.UUID, query string, lat, long float64, radius int, hasGeo bool, limit int) []gin.H {
	var rows_result []gin.H
	ctx := c.Request.Context()

	baseQuery := `
		SELECT p.id, LEFT(p.body, 200) as body, p.category,
		       p.latitude, p.longitude, p.created_at,
		       COALESCE(p.image_url, '') as image_url,
		       pr.handle, pr.display_name, COALESCE(pr.avatar_url, '')
		FROM posts p
		JOIN profiles pr ON p.author_id = pr.id
		WHERE p.is_beacon = TRUE AND p.deleted_at IS NULL
	`
	args := []any{}
	argIdx := 1

	if query != "" {
		baseQuery += ` AND p.body ILIKE '%' || $` + strconv.Itoa(argIdx) + ` || '%'`
		args = append(args, query)
		argIdx++
	}

	if hasGeo {
		baseQuery += ` AND ST_DWithin(
			ST_SetSRID(ST_Point(p.longitude, p.latitude), 4326)::geography,
			ST_SetSRID(ST_Point($` + strconv.Itoa(argIdx) + `, $` + strconv.Itoa(argIdx+1) + `), 4326)::geography,
			$` + strconv.Itoa(argIdx+2) + `)`
		args = append(args, long, lat, radius)
		argIdx += 3
		baseQuery += ` ORDER BY ST_Distance(
			ST_SetSRID(ST_Point(p.longitude, p.latitude), 4326)::geography,
			ST_SetSRID(ST_Point($` + strconv.Itoa(argIdx) + `, $` + strconv.Itoa(argIdx+1) + `), 4326)::geography) ASC`
		args = append(args, long, lat)
		argIdx += 2
	} else {
		baseQuery += ` ORDER BY p.created_at DESC`
	}

	baseQuery += ` LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := h.pool.Query(ctx, baseQuery, args...)
	if err != nil {
		return []gin.H{}
	}
	defer rows.Close()

	for rows.Next() {
		var id uuid.UUID
		var body, category, imageURL, handle, displayName, avatarURL string
		var eLat, eLong float64
		var createdAt time.Time
		if err := rows.Scan(&id, &body, &category, &eLat, &eLong, &createdAt,
			&imageURL, &handle, &displayName, &avatarURL); err != nil {
			continue
		}
		rows_result = append(rows_result, gin.H{
			"id": id, "body": body, "category": category,
			"lat": eLat, "long": eLong, "created_at": createdAt,
			"image_url": imageURL, "result_type": "beacon",
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
		})
	}
	if rows_result == nil {
		rows_result = []gin.H{}
	}
	return rows_result
}

func (h *BeaconSearchHandler) searchBoard(c *gin.Context, userID uuid.UUID, query string, lat, long float64, radius int, hasGeo bool, limit int) []gin.H {
	var results []gin.H
	ctx := c.Request.Context()

	baseQuery := `
		SELECT e.id, e.body, COALESCE(e.image_url, ''), e.topic,
		       e.lat, e.long, e.upvotes, e.reply_count, e.is_pinned, e.created_at,
		       pr.handle, pr.display_name, COALESCE(pr.avatar_url, ''),
		       EXISTS(SELECT 1 FROM board_votes bv WHERE bv.user_id = $1 AND bv.entry_id = e.id) AS has_voted
		FROM board_entries e
		JOIN profiles pr ON e.author_id = pr.id
		WHERE e.is_active = TRUE
	`
	args := []any{userID}
	argIdx := 2

	if query != "" {
		baseQuery += ` AND e.body ILIKE '%' || $` + strconv.Itoa(argIdx) + ` || '%'`
		args = append(args, query)
		argIdx++
	}

	if hasGeo {
		baseQuery += ` AND ST_DWithin(e.location, ST_SetSRID(ST_Point($` + strconv.Itoa(argIdx) + `, $` + strconv.Itoa(argIdx+1) + `), 4326)::geography, $` + strconv.Itoa(argIdx+2) + `)`
		args = append(args, long, lat, radius)
		argIdx += 3
	}

	baseQuery += ` ORDER BY e.is_pinned DESC, e.created_at DESC LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := h.pool.Query(ctx, baseQuery, args...)
	if err != nil {
		return []gin.H{}
	}
	defer rows.Close()

	for rows.Next() {
		var id uuid.UUID
		var body, imageURL, topic, handle, displayName, avatarURL string
		var eLat, eLong float64
		var upvotes, replyCount int
		var isPinned, hasVoted bool
		var createdAt time.Time
		if err := rows.Scan(&id, &body, &imageURL, &topic,
			&eLat, &eLong, &upvotes, &replyCount, &isPinned, &createdAt,
			&handle, &displayName, &avatarURL, &hasVoted); err != nil {
			continue
		}
		results = append(results, gin.H{
			"id": id, "body": body, "image_url": imageURL, "topic": topic,
			"lat": eLat, "long": eLong, "upvotes": upvotes, "reply_count": replyCount,
			"is_pinned": isPinned, "created_at": createdAt, "result_type": "board",
			"author_handle": handle, "author_display_name": displayName, "author_avatar_url": avatarURL,
			"has_voted": hasVoted,
		})
	}
	if results == nil {
		results = []gin.H{}
	}
	return results
}

func (h *BeaconSearchHandler) searchPublicGroups(c *gin.Context, query string, limit int) []gin.H {
	var results []gin.H
	ctx := c.Request.Context()

	// Only return public, non-encrypted groups
	baseQuery := `
		SELECT g.id, g.name, g.description, g.type,
		       COALESCE(g.avatar_url, '') as avatar_url,
		       g.member_count, g.created_at
		FROM groups g
		WHERE g.is_active = TRUE
		  AND g.is_encrypted = FALSE
		  AND g.privacy = 'public'
		  AND g.type NOT IN ('private_capsule', 'private_social')
	`
	args := []any{}
	argIdx := 1

	if query != "" {
		baseQuery += ` AND (g.name ILIKE '%' || $` + strconv.Itoa(argIdx) + ` || '%' OR g.description ILIKE '%' || $` + strconv.Itoa(argIdx) + ` || '%')`
		args = append(args, query)
		argIdx++
	}

	baseQuery += ` ORDER BY g.member_count DESC, g.created_at DESC LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := h.pool.Query(ctx, baseQuery, args...)
	if err != nil {
		return []gin.H{}
	}
	defer rows.Close()

	for rows.Next() {
		var id uuid.UUID
		var name, description, groupType, avatarURL string
		var memberCount int
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &description, &groupType, &avatarURL, &memberCount, &createdAt); err != nil {
			continue
		}
		results = append(results, gin.H{
			"id": id, "name": name, "description": description,
			"type": groupType, "avatar_url": avatarURL,
			"member_count": memberCount, "created_at": createdAt,
			"result_type": "group",
		})
	}
	if results == nil {
		results = []gin.H{}
	}
	return results
}
