// Copyright (c) 2026 MPLS LLC. All rights reserved.
// Use of this source code is governed by the Business Source License
// included in the LICENSE file.

package services

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// EventIngestionService fetches events from external APIs (Eventbrite, Ticketmaster)
// and imports them into the group_events table for neighborhood groups.
type EventIngestionService struct {
	pool               *pgxpool.Pool
	eventbriteAPIKey   string
	ticketmasterAPIKey string
	httpClient         *http.Client
}

func NewEventIngestionService(pool *pgxpool.Pool, eventbriteKey, ticketmasterKey string) *EventIngestionService {
	return &EventIngestionService{
		pool:               pool,
		eventbriteAPIKey:   eventbriteKey,
		ticketmasterAPIKey: ticketmasterKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// ── External API Response Types ──────────────────────────────────

type ticketmasterResponse struct {
	Embedded struct {
		Events []ticketmasterEvent `json:"events"`
	} `json:"_embedded"`
}

type ticketmasterEvent struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	URL  string `json:"url"`
	Info string `json:"info"`
	Dates struct {
		Start struct {
			DateTime string `json:"dateTime"`
		} `json:"start"`
		End struct {
			DateTime string `json:"dateTime"`
		} `json:"end"`
	} `json:"dates"`
	Embedded struct {
		Venues []struct {
			Name     string `json:"name"`
			Location struct {
				Latitude  string `json:"latitude"`
				Longitude string `json:"longitude"`
			} `json:"location"`
		} `json:"venues"`
	} `json:"_embedded"`
	Images []struct {
		URL    string `json:"url"`
		Width  int    `json:"width"`
		Height int    `json:"height"`
	} `json:"images"`
}

type eventbriteResponse struct {
	Events []eventbriteEvent `json:"events"`
}

type eventbriteEvent struct {
	ID          string `json:"id"`
	Name        struct{ Text string `json:"text"` } `json:"name"`
	Description struct{ Text string `json:"text"` } `json:"description"`
	URL         string `json:"url"`
	Start       struct{ UTC string `json:"utc"` } `json:"start"`
	End         struct{ UTC string `json:"utc"` } `json:"end"`
	Venue       *struct {
		Name    string `json:"name"`
		Address struct {
			Latitude  string `json:"latitude"`
			Longitude string `json:"longitude"`
		} `json:"address"`
	} `json:"venue"`
	Logo *struct {
		URL string `json:"url"`
	} `json:"logo"`
}

// ── Normalized Event ─────────────────────────────────────────────

type externalEvent struct {
	Source       string // "eventbrite" or "ticketmaster"
	ExternalID   string
	ExternalURL  string
	Title        string
	Description  string
	LocationName string
	Lat          *float64
	Long         *float64
	StartsAt     time.Time
	EndsAt       *time.Time
	CoverURL     string
	RawData      json.RawMessage
}

// ── Public API ───────────────────────────────────────────────────

// SyncAll discovers events for all active neighborhoods and imports them.
func (s *EventIngestionService) SyncAll(ctx context.Context) error {
	if s.eventbriteAPIKey == "" && s.ticketmasterAPIKey == "" {
		log.Debug().Msg("[EventIngestion] No API keys configured, skipping sync")
		return nil
	}

	// Find neighborhoods (groups with a center point) that have members
	rows, err := s.pool.Query(ctx, `
		SELECT g.id, g.name, ST_Y(g.center::geometry) AS lat, ST_X(g.center::geometry) AS long
		FROM groups g
		WHERE g.type = 'neighborhood'
		  AND g.center IS NOT NULL
		  AND EXISTS (SELECT 1 FROM group_members gm WHERE gm.group_id = g.id)
		LIMIT 20
	`)
	if err != nil {
		return fmt.Errorf("query neighborhoods: %w", err)
	}
	defer rows.Close()

	type neighborhood struct {
		ID   uuid.UUID
		Name string
		Lat  float64
		Long float64
	}
	var neighborhoods []neighborhood
	for rows.Next() {
		var n neighborhood
		if err := rows.Scan(&n.ID, &n.Name, &n.Lat, &n.Long); err != nil {
			continue
		}
		neighborhoods = append(neighborhoods, n)
	}

	if len(neighborhoods) == 0 {
		log.Debug().Msg("[EventIngestion] No active neighborhoods with coordinates found")
		return nil
	}

	totalImported := 0
	for _, n := range neighborhoods {
		count, err := s.syncNeighborhood(ctx, n.ID, n.Name, n.Lat, n.Long)
		if err != nil {
			log.Warn().Err(err).Str("neighborhood", n.Name).Msg("[EventIngestion] Sync failed for neighborhood")
			continue
		}
		totalImported += count
	}

	log.Info().Int("imported", totalImported).Int("neighborhoods", len(neighborhoods)).Msg("[EventIngestion] Sync complete")

	// Cleanup expired events
	s.cleanupExpired(ctx)

	return nil
}

func (s *EventIngestionService) syncNeighborhood(ctx context.Context, groupID uuid.UUID, name string, lat, long float64) (int, error) {
	var events []externalEvent

	if s.ticketmasterAPIKey != "" {
		tmEvents, err := s.fetchTicketmaster(ctx, lat, long)
		if err != nil {
			log.Warn().Err(err).Str("neighborhood", name).Msg("[EventIngestion] Ticketmaster fetch failed")
		} else {
			events = append(events, tmEvents...)
		}
	}

	if s.eventbriteAPIKey != "" {
		ebEvents, err := s.fetchEventbrite(ctx, lat, long)
		if err != nil {
			log.Warn().Err(err).Str("neighborhood", name).Msg("[EventIngestion] Eventbrite fetch failed")
		} else {
			events = append(events, ebEvents...)
		}
	}

	if len(events) == 0 {
		return 0, nil
	}

	// Get a system user ID for created_by (use the first admin or group creator)
	var creatorID uuid.UUID
	err := s.pool.QueryRow(ctx, `
		SELECT gm.user_id FROM group_members gm
		WHERE gm.group_id = $1
		ORDER BY gm.role DESC, gm.joined_at ASC
		LIMIT 1
	`, groupID).Scan(&creatorID)
	if err != nil {
		return 0, fmt.Errorf("no creator found for group %s: %w", groupID, err)
	}

	imported := 0
	for _, evt := range events {
		ok, err := s.importEvent(ctx, groupID, creatorID, evt)
		if err != nil {
			log.Warn().Err(err).Str("event", evt.Title).Msg("[EventIngestion] Import failed")
			continue
		}
		if ok {
			imported++
		}
	}

	return imported, nil
}

func (s *EventIngestionService) importEvent(ctx context.Context, groupID, creatorID uuid.UUID, evt externalEvent) (bool, error) {
	// Check if already imported (dedup by source + external_id)
	var exists bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM external_events WHERE source = $1 AND external_id = $2)
	`, evt.Source, evt.ExternalID).Scan(&exists)
	if err != nil {
		return false, err
	}
	if exists {
		return false, nil
	}

	// Insert into group_events
	eventID := uuid.New()
	_, err = s.pool.Exec(ctx, `
		INSERT INTO group_events (id, group_id, created_by, title, description, location_name, lat, long, starts_at, ends_at, is_public, cover_image_url, status, source, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true, $11, 'approved', $12, now(), now())
	`, eventID, groupID, creatorID, evt.Title, evt.Description, evt.LocationName, evt.Lat, evt.Long, evt.StartsAt, evt.EndsAt, evt.CoverURL, evt.Source)
	if err != nil {
		return false, fmt.Errorf("insert group_event: %w", err)
	}

	// Track in external_events for dedup
	_, err = s.pool.Exec(ctx, `
		INSERT INTO external_events (id, source, external_id, group_event_id, external_url, raw_data, last_synced_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, now(), now())
		ON CONFLICT (source, external_id) DO UPDATE SET last_synced_at = now()
	`, uuid.New(), evt.Source, evt.ExternalID, eventID, evt.ExternalURL, evt.RawData)
	if err != nil {
		log.Warn().Err(err).Msg("[EventIngestion] Failed to track external event")
	}

	return true, nil
}

func (s *EventIngestionService) cleanupExpired(ctx context.Context) {
	tag, err := s.pool.Exec(ctx, `
		DELETE FROM group_events
		WHERE source != 'user'
		  AND (ends_at IS NOT NULL AND ends_at < now() - INTERVAL '1 day')
		  OR  (ends_at IS NULL AND starts_at < now() - INTERVAL '1 day')
	`)
	if err != nil {
		log.Warn().Err(err).Msg("[EventIngestion] Cleanup failed")
		return
	}
	if tag.RowsAffected() > 0 {
		log.Info().Int64("deleted", tag.RowsAffected()).Msg("[EventIngestion] Cleaned up expired external events")
	}
}

// ── Ticketmaster Discovery API ───────────────────────────────────

func (s *EventIngestionService) fetchTicketmaster(ctx context.Context, lat, long float64) ([]externalEvent, error) {
	u := fmt.Sprintf(
		"https://app.ticketmaster.com/discovery/v2/events.json?latlong=%f,%f&radius=25&unit=miles&size=20&sort=date,asc&apikey=%s",
		lat, long, url.QueryEscape(s.ticketmasterAPIKey),
	)

	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ticketmaster request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ticketmaster returned %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var tmResp ticketmasterResponse
	if err := json.Unmarshal(body, &tmResp); err != nil {
		return nil, fmt.Errorf("parse ticketmaster: %w", err)
	}

	var events []externalEvent
	for _, e := range tmResp.Embedded.Events {
		evt := externalEvent{
			Source:      "ticketmaster",
			ExternalID:  e.ID,
			ExternalURL: e.URL,
			Title:       e.Name,
			Description: e.Info,
		}

		if t, err := time.Parse(time.RFC3339, e.Dates.Start.DateTime); err == nil {
			evt.StartsAt = t
		} else {
			continue // skip events without valid start time
		}
		if e.Dates.End.DateTime != "" {
			if t, err := time.Parse(time.RFC3339, e.Dates.End.DateTime); err == nil {
				evt.EndsAt = &t
			}
		}

		if len(e.Embedded.Venues) > 0 {
			venue := e.Embedded.Venues[0]
			evt.LocationName = venue.Name
			if lat, err := parseFloat(venue.Location.Latitude); err == nil {
				evt.Lat = &lat
			}
			if long, err := parseFloat(venue.Location.Longitude); err == nil {
				evt.Long = &long
			}
		}

		// Pick the widest image
		for _, img := range e.Images {
			if img.Width > 400 {
				evt.CoverURL = img.URL
				break
			}
		}

		rawJSON, _ := json.Marshal(e)
		evt.RawData = rawJSON

		events = append(events, evt)
	}

	log.Debug().Int("count", len(events)).Msg("[EventIngestion] Fetched Ticketmaster events")
	return events, nil
}

// ── Eventbrite API ───────────────────────────────────────────────

func (s *EventIngestionService) fetchEventbrite(ctx context.Context, lat, long float64) ([]externalEvent, error) {
	u := fmt.Sprintf(
		"https://www.eventbriteapi.com/v3/events/search/?location.latitude=%f&location.longitude=%f&location.within=25mi&expand=venue&sort_by=date",
		lat, long,
	)

	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+s.eventbriteAPIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eventbrite request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("eventbrite returned %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var ebResp eventbriteResponse
	if err := json.Unmarshal(body, &ebResp); err != nil {
		return nil, fmt.Errorf("parse eventbrite: %w", err)
	}

	var events []externalEvent
	for _, e := range ebResp.Events {
		evt := externalEvent{
			Source:      "eventbrite",
			ExternalID:  e.ID,
			ExternalURL: e.URL,
			Title:       e.Name.Text,
			Description: truncateText(e.Description.Text, 500),
		}

		if t, err := time.Parse("2006-01-02T15:04:05Z", e.Start.UTC); err == nil {
			evt.StartsAt = t
		} else {
			continue
		}
		if e.End.UTC != "" {
			if t, err := time.Parse("2006-01-02T15:04:05Z", e.End.UTC); err == nil {
				evt.EndsAt = &t
			}
		}

		if e.Venue != nil {
			evt.LocationName = e.Venue.Name
			if lat, err := parseFloat(e.Venue.Address.Latitude); err == nil {
				evt.Lat = &lat
			}
			if long, err := parseFloat(e.Venue.Address.Longitude); err == nil {
				evt.Long = &long
			}
		}

		if e.Logo != nil {
			evt.CoverURL = e.Logo.URL
		}

		rawJSON, _ := json.Marshal(e)
		evt.RawData = rawJSON

		events = append(events, evt)
	}

	log.Debug().Int("count", len(events)).Msg("[EventIngestion] Fetched Eventbrite events")
	return events, nil
}

// ── Helpers ──────────────────────────────────────────────────────

func parseFloat(s string) (float64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("empty")
	}
	var f float64
	_, err := fmt.Sscanf(s, "%f", &f)
	return f, err
}

func truncateText(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
