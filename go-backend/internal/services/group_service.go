// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

type GroupService struct {
	pool *pgxpool.Pool
}

func NewGroupService(pool *pgxpool.Pool) *GroupService {
	return &GroupService{pool: pool}
}

// CreateGeoGroup creates a new geo-cluster (neighborhood) group at the given coordinates.
func (s *GroupService) CreateGeoGroup(ctx context.Context, name string, lat, long float64, radiusMeters int, createdBy uuid.UUID) (*models.Group, error) {
	var group models.Group
	err := s.pool.QueryRow(ctx, `
		INSERT INTO groups (name, type, privacy, location_center, radius_meters, created_by, member_count)
		VALUES ($1, 'geo', 'public', ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4, $5, 0)
		RETURNING id, name, description, type, privacy, radius_meters, member_count, is_active, category, created_at, updated_at
	`, name, long, lat, radiusMeters, createdBy).Scan(
		&group.ID, &group.Name, &group.Description, &group.Type, &group.Privacy,
		&group.RadiusMeters, &group.MemberCount, &group.IsActive, &group.Category, &group.CreatedAt, &group.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create geo group: %w", err)
	}
	group.Lat = &lat
	group.Long = &long
	group.CreatedBy = &createdBy
	return &group, nil
}

// FindNearestGeoGroup finds the closest geo group to the given coordinates within maxDistance meters.
func (s *GroupService) FindNearestGeoGroup(ctx context.Context, lat, long float64, maxDistanceMeters int) (*models.GroupWithDistance, error) {
	var gwd models.GroupWithDistance
	err := s.pool.QueryRow(ctx, `
		SELECT g.id, g.name, g.description, g.type, g.privacy, g.radius_meters,
		       g.member_count, g.is_active, g.category, g.created_at, g.updated_at,
		       ST_Distance(g.location_center, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography) AS distance_meters
		FROM groups g
		WHERE g.type = 'geo' AND g.is_active = TRUE
		  AND ST_DWithin(g.location_center, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
		ORDER BY distance_meters ASC
		LIMIT 1
	`, long, lat, maxDistanceMeters).Scan(
		&gwd.ID, &gwd.Name, &gwd.Description, &gwd.Type, &gwd.Privacy,
		&gwd.RadiusMeters, &gwd.MemberCount, &gwd.IsActive, &gwd.Category, &gwd.CreatedAt, &gwd.UpdatedAt,
		&gwd.DistanceMeters,
	)
	if err != nil {
		return nil, fmt.Errorf("find nearest geo group: %w", err)
	}
	return &gwd, nil
}

// AutoJoinNearestGeoGroup finds the nearest geo group and adds the user as a member.
// Returns the group (or nil if none found). Idempotent — won't duplicate memberships.
func (s *GroupService) AutoJoinNearestGeoGroup(ctx context.Context, userID uuid.UUID, lat, long float64) (*models.Group, error) {
	gwd, err := s.FindNearestGeoGroup(ctx, lat, long, 50000) // 50km max
	if err != nil {
		return nil, nil // no group found — that's OK
	}

	_, err = s.pool.Exec(ctx, `
		INSERT INTO group_members (group_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (group_id, user_id) DO NOTHING
	`, gwd.ID, userID)
	if err != nil {
		return nil, fmt.Errorf("auto-join geo group: %w", err)
	}

	// Bump member count (best-effort)
	s.pool.Exec(ctx, `
		UPDATE groups SET member_count = (
			SELECT COUNT(*) FROM group_members WHERE group_id = $1
		) WHERE id = $1
	`, gwd.ID)

	return &gwd.Group, nil
}

// GetUserGeoGroup returns the user's current geo group (if any).
func (s *GroupService) GetUserGeoGroup(ctx context.Context, userID uuid.UUID) (*models.Group, error) {
	var group models.Group
	var createdAt, updatedAt time.Time
	err := s.pool.QueryRow(ctx, `
		SELECT g.id, g.name, g.description, g.type, g.privacy, g.radius_meters,
		       g.member_count, g.is_active, g.category, g.created_at, g.updated_at
		FROM groups g
		JOIN group_members gm ON gm.group_id = g.id
		WHERE gm.user_id = $1 AND g.type = 'geo' AND g.is_active = TRUE
		ORDER BY gm.joined_at DESC
		LIMIT 1
	`, userID).Scan(
		&group.ID, &group.Name, &group.Description, &group.Type, &group.Privacy,
		&group.RadiusMeters, &group.MemberCount, &group.IsActive, &group.Category, &createdAt, &updatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("get user geo group: %w", err)
	}
	group.CreatedAt = createdAt
	group.UpdatedAt = updatedAt
	return &group, nil
}

// GetGroupPosts returns posts belonging to a group, optionally filtered by beacon-only.
func (s *GroupService) GetGroupPosts(ctx context.Context, groupID uuid.UUID, beaconsOnly bool, limit, offset int) ([]models.Post, error) {
	var filter string
	if beaconsOnly {
		filter = " AND p.is_beacon = TRUE"
	}

	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT p.id, p.author_id, p.body, p.status, p.is_beacon, p.beacon_type,
		       p.severity, p.incident_status, p.radius, p.created_at, p.group_id
		FROM posts p
		WHERE p.group_id = $1 AND p.status = 'active' AND p.deleted_at IS NULL%s
		ORDER BY p.created_at DESC
		LIMIT $2 OFFSET $3
	`, filter), groupID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("get group posts: %w", err)
	}
	defer rows.Close()

	var posts []models.Post
	for rows.Next() {
		var p models.Post
		if err := rows.Scan(
			&p.ID, &p.AuthorID, &p.Body, &p.Status, &p.IsBeacon, &p.BeaconType,
			&p.Severity, &p.IncidentStatus, &p.Radius, &p.CreatedAt, &p.GroupID,
		); err != nil {
			continue
		}
		posts = append(posts, p)
	}
	return posts, nil
}

// GetGroupByID returns a single group by its ID.
func (s *GroupService) GetGroupByID(ctx context.Context, groupID uuid.UUID) (*models.Group, error) {
	var group models.Group
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, description, type, privacy, radius_meters,
		       member_count, is_active, category, created_at, updated_at
		FROM groups WHERE id = $1
	`, groupID).Scan(
		&group.ID, &group.Name, &group.Description, &group.Type, &group.Privacy,
		&group.RadiusMeters, &group.MemberCount, &group.IsActive, &group.Category, &group.CreatedAt, &group.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("get group: %w", err)
	}
	return &group, nil
}
