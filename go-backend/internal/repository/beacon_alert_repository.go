// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// BeaconAlert represents a row in the beacon_alerts table.
type BeaconAlert struct {
	ID             string
	ExternalID     string
	Source         string // "mn511", "mn511_camera", "mn511_sign", "mn511_weather", "iced"
	BeaconType     string
	Severity       string
	Title          string
	Body           string
	Lat            float64
	Lng            float64
	Radius         int
	ImageURL       *string
	VideoURL       *string
	IsOfficial     bool
	OfficialSource *string
	AuthorID       *string
	AuthorHandle   *string
	AuthorDisplay  *string
	Status         string
	IncidentStatus string
	Confidence     float64
	VouchCount     int
	ReportCount    int
	Tags           []string
	ExpiresAt      *time.Time
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

type BeaconAlertRepository struct {
	pool *pgxpool.Pool
}

func NewBeaconAlertRepository(pool *pgxpool.Pool) *BeaconAlertRepository {
	return &BeaconAlertRepository{pool: pool}
}

// UpsertAlert inserts or updates a beacon alert by (source, external_id).
func (r *BeaconAlertRepository) UpsertAlert(ctx context.Context, a *BeaconAlert) error {
	query := `
		INSERT INTO beacon_alerts (
			external_id, source, beacon_type, severity, title, body,
			lat, lng, radius, image_url, video_url,
			is_official, official_source, author_id, author_handle, author_display,
			status, incident_status, confidence, vouch_count, report_count,
			tags, expires_at, created_at
		) VALUES (
			$1, $2, $3, $4, $5, $6,
			$7, $8, $9, $10, $11,
			$12, $13, $14, $15, $16,
			$17, $18, $19, $20, $21,
			$22, $23, $24
		)
		ON CONFLICT (source, external_id) DO UPDATE SET
			beacon_type = EXCLUDED.beacon_type,
			severity = EXCLUDED.severity,
			title = EXCLUDED.title,
			body = EXCLUDED.body,
			lat = EXCLUDED.lat,
			lng = EXCLUDED.lng,
			radius = EXCLUDED.radius,
			image_url = EXCLUDED.image_url,
			video_url = EXCLUDED.video_url,
			status = EXCLUDED.status,
			incident_status = EXCLUDED.incident_status,
			confidence = EXCLUDED.confidence,
			vouch_count = EXCLUDED.vouch_count,
			report_count = EXCLUDED.report_count,
			tags = EXCLUDED.tags,
			expires_at = EXCLUDED.expires_at
	`
	_, err := r.pool.Exec(ctx, query,
		a.ExternalID, a.Source, a.BeaconType, a.Severity, a.Title, a.Body,
		a.Lat, a.Lng, a.Radius, a.ImageURL, a.VideoURL,
		a.IsOfficial, a.OfficialSource, a.AuthorID, a.AuthorHandle, a.AuthorDisplay,
		a.Status, a.IncidentStatus, a.Confidence, a.VouchCount, a.ReportCount,
		a.Tags, a.ExpiresAt, a.CreatedAt,
	)
	return err
}

// BulkUpsert inserts/updates multiple alerts efficiently.
func (r *BeaconAlertRepository) BulkUpsert(ctx context.Context, alerts []*BeaconAlert) (int, error) {
	if len(alerts) == 0 {
		return 0, nil
	}

	count := 0
	for _, a := range alerts {
		if err := r.UpsertAlert(ctx, a); err != nil {
			log.Error().Err(err).Str("source", a.Source).Str("external_id", a.ExternalID).Msg("beacon_alerts: upsert failed")
			continue
		}
		count++
	}
	return count, nil
}

// ExpireStale marks alerts as 'expired' when their expires_at has passed.
func (r *BeaconAlertRepository) ExpireStale(ctx context.Context) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE beacon_alerts
		SET status = 'expired'
		WHERE expires_at < NOW() AND status = 'active'
	`)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// CleanOrphaned removes alerts from a source that are no longer in the upstream feed.
// activeIDs is the set of external_ids that were present in the latest fetch.
func (r *BeaconAlertRepository) CleanOrphaned(ctx context.Context, source string, activeIDs []string) (int64, error) {
	if len(activeIDs) == 0 {
		// No active IDs means upstream returned nothing — mark all from this source as expired
		tag, err := r.pool.Exec(ctx, `
			UPDATE beacon_alerts SET status = 'expired'
			WHERE source = $1 AND status = 'active'
		`, source)
		if err != nil {
			return 0, err
		}
		return tag.RowsAffected(), nil
	}

	tag, err := r.pool.Exec(ctx, `
		UPDATE beacon_alerts SET status = 'expired'
		WHERE source = $1 AND status = 'active'
		  AND external_id != ALL($2)
	`, source, activeIDs)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// GetNearbyAlerts returns all active, non-expired alerts within radius meters of (lat, lng).
// Also includes user-created beacons from the posts table.
func (r *BeaconAlertRepository) GetNearbyAlerts(ctx context.Context, lat, lng float64, radius int, userID string) ([]map[string]any, error) {
	// Query 1: External alerts from beacon_alerts table
	externalQuery := `
		SELECT
			id, external_id, source, beacon_type, severity, title, body,
			lat, lng, radius, image_url, video_url,
			is_official, official_source, author_id, author_handle, author_display,
			status, incident_status, confidence, vouch_count, report_count,
			tags, expires_at, created_at,
			ST_Distance(location, ST_SetSRID(ST_Point($2, $1), 4326)::geography) AS distance_meters
		FROM beacon_alerts
		WHERE status = 'active'
		  AND (expires_at IS NULL OR expires_at > NOW())
		  AND ST_DWithin(location, ST_SetSRID(ST_Point($2, $1), 4326)::geography, $3)
		ORDER BY created_at DESC
	`

	rows, err := r.pool.Query(ctx, externalQuery, lat, lng, radius)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var (
			id, externalID, source, beaconType, severity, title, body string
			aLat, aLng                                                float64
			aRadius                                                   int
			imageURL, videoURL                                        *string
			isOfficial                                                bool
			officialSource, authorID, authorHandle, authorDisplay     *string
			status, incidentStatus                                    string
			confidence                                                float64
			vouchCount, reportCount                                   int
			tags                                                      []string
			expiresAt                                                 *time.Time
			createdAt                                                 time.Time
			distanceMeters                                            float64
		)

		if err := rows.Scan(
			&id, &externalID, &source, &beaconType, &severity, &title, &body,
			&aLat, &aLng, &aRadius, &imageURL, &videoURL,
			&isOfficial, &officialSource, &authorID, &authorHandle, &authorDisplay,
			&status, &incidentStatus, &confidence, &vouchCount, &reportCount,
			&tags, &expiresAt, &createdAt, &distanceMeters,
		); err != nil {
			log.Error().Err(err).Msg("beacon_alerts: scan failed")
			continue
		}

		item := map[string]any{
			"id":                 id,
			"body":              body,
			"created_at":        createdAt.Format(time.RFC3339),
			"is_beacon":         true,
			"is_active_beacon":  true,
			"beacon_type":       beaconType,
			"severity":          severity,
			"incident_status":   incidentStatus,
			"confidence_score":  confidence,
			"verification_count": vouchCount,
			"vouch_count":       vouchCount,
			"report_count":      reportCount,
			"status_color":      "green",
			"beacon_lat":        aLat,
			"beacon_long":       aLng,
			"distance_meters":   distanceMeters,
			"radius":            aRadius,
			"is_official":       isOfficial,
			"tags":              tags,
		}

		if officialSource != nil {
			item["official_source"] = *officialSource
		}
		if authorID != nil {
			item["author_id"] = *authorID
		} else {
			item["author_id"] = "00000000-0000-0000-0000-000000000000"
		}
		if authorHandle != nil {
			item["author_handle"] = *authorHandle
		} else {
			item["author_handle"] = "Anonymous"
		}
		if authorDisplay != nil {
			item["author_display_name"] = *authorDisplay
		} else {
			item["author_display_name"] = "Anonymous"
		}
		if imageURL != nil {
			item["image_url"] = *imageURL
		}
		if videoURL != nil {
			item["video_url"] = *videoURL
		}
		if expiresAt != nil {
			item["expires_at"] = expiresAt.Format(time.RFC3339)
		}

		results = append(results, item)
	}

	// Query 2: User-created beacons from the posts table
	userQuery := `
		SELECT
			p.id, p.body, COALESCE(p.image_url, ''), p.tags, p.created_at,
			p.beacon_type, p.confidence_score, p.is_active_beacon,
			COALESCE(p.is_priority, FALSE) as is_priority,
			ST_Y(p.location::geometry) as lat, ST_X(p.location::geometry) as long,
			COALESCE(p.severity, 'medium') as severity,
			COALESCE(p.incident_status, 'active') as incident_status,
			COALESCE(p.radius, 500) as radius,
			COALESCE((SELECT COUNT(*) FROM public.beacon_vouches bv WHERE bv.beacon_id = p.id), 0) as vouch_count,
			COALESCE((SELECT COUNT(*) FROM public.beacon_reports br WHERE br.beacon_id = p.id), 0) as report_count,
			ST_Distance(p.location::geography, ST_SetSRID(ST_Point($2, $1), 4326)::geography) AS distance_meters,
			p.expires_at,
			CASE
				WHEN EXISTS (SELECT 1 FROM public.beacon_vouches WHERE beacon_id = p.id AND user_id = $4::uuid) THEN 'vouch'
				WHEN EXISTS (SELECT 1 FROM public.beacon_reports WHERE beacon_id = p.id AND user_id = $4::uuid) THEN 'report'
				ELSE NULL
			END as my_vote
		FROM public.posts p
		WHERE p.is_beacon = true
		  AND ST_DWithin(p.location, ST_SetSRID(ST_Point($2, $1), 4326)::geography, $3)
		  AND p.status = 'active'
		  AND COALESCE(p.incident_status, 'active') = 'active'
		  AND (p.expires_at IS NULL OR p.expires_at > NOW())
		ORDER BY p.is_priority DESC, p.created_at DESC
	`

	userRows, err := r.pool.Query(ctx, userQuery, lat, lng, radius, userID)
	if err != nil {
		log.Error().Err(err).Msg("beacon_alerts: user beacons query failed")
		// Return external results even if user query fails
		if results == nil {
			results = []map[string]any{}
		}
		return results, nil
	}
	defer userRows.Close()

	for userRows.Next() {
		var (
			pID, pBody, pImageURL                    string
			pTags                                    []string
			pCreatedAt                               time.Time
			pBeaconType                              *string
			pConfidence                              *float64
			pIsActive                                *bool
			pIsPriority                              bool
			pLat, pLng                               float64
			pSeverity, pIncidentStatus               string
			pRadius                                  int
			pVouchCount, pReportCount                int
			pDistanceMeters                          float64
			pExpiresAt                               *time.Time
			pMyVote                                  *string
		)

		if err := userRows.Scan(
			&pID, &pBody, &pImageURL, &pTags, &pCreatedAt,
			&pBeaconType, &pConfidence, &pIsActive, &pIsPriority,
			&pLat, &pLng, &pSeverity, &pIncidentStatus, &pRadius,
			&pVouchCount, &pReportCount, &pDistanceMeters, &pExpiresAt, &pMyVote,
		); err != nil {
			log.Error().Err(err).Msg("beacon_alerts: user beacon scan failed")
			continue
		}

		bt := "hazard"
		if pBeaconType != nil {
			bt = *pBeaconType
		}
		conf := 0.5
		if pConfidence != nil {
			conf = *pConfidence
		}

		item := map[string]any{
			"id":                 pID,
			"body":              pBody,
			"created_at":        pCreatedAt.Format(time.RFC3339),
			"is_beacon":         true,
			"is_active_beacon":  pIsActive != nil && *pIsActive,
			"beacon_type":       bt,
			"severity":          pSeverity,
			"incident_status":   pIncidentStatus,
			"confidence_score":  conf,
			"verification_count": pVouchCount,
			"vouch_count":       pVouchCount,
			"report_count":      pReportCount,
			"status_color":      "green",
			"beacon_lat":        pLat,
			"beacon_long":       pLng,
			"distance_meters":   pDistanceMeters,
			"radius":            pRadius,
			"is_official":       false,
			"is_priority":       pIsPriority,
			"author_id":         "00000000-0000-0000-0000-000000000000",
			"author_handle":     "Anonymous",
			"author_display_name": "Anonymous",
			"image_url":         pImageURL,
			"tags":              pTags,
		}
		if pExpiresAt != nil {
			item["expires_at"] = pExpiresAt.Format(time.RFC3339)
		}
		if pMyVote != nil {
			item["my_vote"] = *pMyVote
		}

		results = append(results, item)
	}

	if results == nil {
		results = []map[string]any{}
	}
	return results, nil
}
