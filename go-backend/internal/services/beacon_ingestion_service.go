// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

// BeaconIngestionService periodically fetches alerts from external sources
// (MN511, IcedCoffee) and upserts them into the beacon_alerts table.
type BeaconIngestionService struct {
	repo        *repository.BeaconAlertRepository
	mn511Base   string
	icedBase    string
	client      *http.Client
	interval    time.Duration
	stopCh      chan struct{}
	wg          sync.WaitGroup
}

func NewBeaconIngestionService(
	repo *repository.BeaconAlertRepository,
	mn511Base string,
	icedBase string,
) *BeaconIngestionService {
	return &BeaconIngestionService{
		repo:      repo,
		mn511Base: mn511Base,
		icedBase:  icedBase,
		client:    &http.Client{Timeout: 15 * time.Second},
		interval:  2 * time.Minute,
		stopCh:    make(chan struct{}),
	}
}

// Start begins the periodic ingestion loop in a background goroutine.
func (s *BeaconIngestionService) Start() {
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		log.Info().Dur("interval", s.interval).Msg("beacon ingestion: started")

		// Run immediately on startup
		s.runCycle()

		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				s.runCycle()
			case <-s.stopCh:
				log.Info().Msg("beacon ingestion: stopped")
				return
			}
		}
	}()
}

// Stop gracefully stops the ingestion loop.
func (s *BeaconIngestionService) Stop() {
	close(s.stopCh)
	s.wg.Wait()
}

func (s *BeaconIngestionService) runCycle() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	start := time.Now()

	// Expire stale alerts first
	expired, err := s.repo.ExpireStale(ctx)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: expire stale failed")
	} else if expired > 0 {
		log.Info().Int64("count", expired).Msg("beacon ingestion: expired stale alerts")
	}

	// Fetch from all sources in parallel
	var wg sync.WaitGroup
	wg.Add(4)

	go func() {
		defer wg.Done()
		s.ingestMN511Alerts(ctx)
	}()
	go func() {
		defer wg.Done()
		s.ingestMN511Cameras(ctx)
	}()
	go func() {
		defer wg.Done()
		s.ingestMN511Signs(ctx)
	}()
	// Weather stations + IcedCoffee
	go func() {
		defer wg.Done()
		s.ingestMN511Weather(ctx)
	}()

	wg.Wait()

	// IcedCoffee (runs after wg for simplicity, could be parallel)
	s.ingestIced(ctx)

	log.Debug().Dur("duration", time.Since(start)).Msg("beacon ingestion: cycle complete")
}

// ── MN511 Alerts (incidents/crashes) ─────────────────────────────────────

type mn511IngestionFeature struct {
	ID       string `json:"id"`
	Geometry struct {
		Coordinates []float64 `json:"coordinates"`
	} `json:"geometry"`
	Properties struct {
		Title       string  `json:"title"`
		Category    string  `json:"category"`
		Severity    int     `json:"severity"`
		Status      string  `json:"status"`
		FirstSeenAt string  `json:"first_seen_at"`
		Lat         float64 `json:"lat"`
		Lon         float64 `json:"lon"`
	} `json:"properties"`
}

type mn511IngestionResponse struct {
	OK       bool                    `json:"ok"`
	Features []mn511IngestionFeature `json:"features"`
}

func (s *BeaconIngestionService) ingestMN511Alerts(ctx context.Context) {
	// Fetch a wide bounding box covering Minnesota
	apiURL := fmt.Sprintf("%s/api/alerts?bbox=-97.5,43.0,-89.0,49.5&status=active", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 alerts fetch failed")
		return
	}

	var resp mn511IngestionResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 alerts parse failed")
		return
	}

	alerts := make([]*repository.BeaconAlert, 0, len(resp.Features))
	activeIDs := make([]string, 0, len(resp.Features))

	for _, f := range resp.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}
		lon := f.Geometry.Coordinates[0]
		lat := f.Geometry.Coordinates[1]

		createdAt := time.Now().UTC()
		if f.Properties.FirstSeenAt != "" {
			if t, err := time.Parse(time.RFC3339, f.Properties.FirstSeenAt); err == nil {
				createdAt = t
			}
		}

		// Default 6-hour expiry for incidents
		expiresAt := createdAt.Add(6 * time.Hour)

		src := "MN 511"
		handle := "@mn511"
		display := "MN 511"
		authorID := "00000000-0000-0000-0000-000000000511"

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     f.ID,
			Source:         "mn511",
			BeaconType:     mn511CatToType(f.Properties.Category),
			Severity:       mn511SevToString(f.Properties.Severity),
			Title:          f.Properties.Title,
			Body:           f.Properties.Title,
			Lat:            lat,
			Lng:            lon,
			Radius:         500,
			IsOfficial:     true,
			OfficialSource: &src,
			AuthorID:       &authorID,
			AuthorHandle:   &handle,
			AuthorDisplay:  &display,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			VouchCount:     10,
			Tags:           []string{},
			ExpiresAt:      &expiresAt,
			CreatedAt:      createdAt,
		})
		activeIDs = append(activeIDs, f.ID)
	}

	count, _ := s.repo.BulkUpsert(ctx, alerts)
	orphaned, _ := s.repo.CleanOrphaned(ctx, "mn511", activeIDs)
	log.Info().Int("upserted", count).Int64("orphaned", orphaned).Int("upstream", len(resp.Features)).Msg("beacon ingestion: mn511 alerts")
}

// ── MN511 Cameras ────────────────────────────────────────────────────────

type mn511CamIngestion struct {
	ID                    string  `json:"id"`
	Title                 string  `json:"title"`
	Category              string  `json:"category"`
	URL                   string  `json:"url"`
	ParentRouteDesignator string  `json:"parent_route_designator"`
	Lat                   float64 `json:"lat"`
	Lon                   float64 `json:"lon"`
	LastUpdatedAt         string  `json:"last_updated_at"`
	Sources               []struct {
		Type string `json:"type"`
		Src  string `json:"src"`
	} `json:"sources"`
}

type mn511CamIngestionResp struct {
	OK      bool                `json:"ok"`
	Cameras []mn511CamIngestion `json:"cameras"`
}

func (s *BeaconIngestionService) ingestMN511Cameras(ctx context.Context) {
	apiURL := fmt.Sprintf("%s/api/camera-views?bbox=-97.5,43.0,-89.0,49.5&limit=500", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 cameras fetch failed")
		return
	}

	var resp mn511CamIngestionResp
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 cameras parse failed")
		return
	}

	alerts := make([]*repository.BeaconAlert, 0, len(resp.Cameras))
	activeIDs := make([]string, 0, len(resp.Cameras))

	for _, cam := range resp.Cameras {
		if cam.Lat == 0 || cam.Lon == 0 {
			continue
		}

		streamURL := ""
		for _, src := range cam.Sources {
			if src.Type == "application/x-mpegURL" || src.Src != "" {
				streamURL = src.Src
				break
			}
		}

		displayTitle := cam.Title
		if cam.ParentRouteDesignator != "" {
			displayTitle = cam.ParentRouteDesignator + " — " + cam.Title
		}

		src := "MN 511"
		handle := "@mn511"
		display := "MN 511"
		authorID := "00000000-0000-0000-0000-000000000511"

		var imgPtr, vidPtr *string
		if cam.URL != "" {
			imgPtr = &cam.URL
		}
		if streamURL != "" {
			vidPtr = &streamURL
		}

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     cam.ID,
			Source:         "mn511_camera",
			BeaconType:     "camera",
			Severity:       "low",
			Title:          displayTitle,
			Body:           displayTitle,
			Lat:            cam.Lat,
			Lng:            cam.Lon,
			Radius:         50,
			ImageURL:       imgPtr,
			VideoURL:       vidPtr,
			IsOfficial:     true,
			OfficialSource: &src,
			AuthorID:       &authorID,
			AuthorHandle:   &handle,
			AuthorDisplay:  &display,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			Tags:           []string{},
			// No expiry — cameras are permanent, refreshed each cycle
			CreatedAt: time.Now().UTC(),
		})
		activeIDs = append(activeIDs, cam.ID)
	}

	count, _ := s.repo.BulkUpsert(ctx, alerts)
	orphaned, _ := s.repo.CleanOrphaned(ctx, "mn511_camera", activeIDs)
	log.Info().Int("upserted", count).Int64("orphaned", orphaned).Msg("beacon ingestion: mn511 cameras")
}

// ── MN511 Signs ──────────────────────────────────────────────────────────

type mn511SignIngestionProps struct {
	Title           string `json:"title"`
	RouteDesignator string `json:"routeDesignator"`
	SignStatus      string `json:"signStatus"`
	Views           []struct {
		ImageURL string `json:"imageUrl"`
	} `json:"views"`
}

type mn511GeoIngestionFeature struct {
	ID       string `json:"id"`
	Geometry struct {
		Coordinates []float64 `json:"coordinates"`
	} `json:"geometry"`
	Properties json.RawMessage `json:"properties"`
}

type mn511GeoIngestionFC struct {
	OK       bool                       `json:"ok"`
	Features []mn511GeoIngestionFeature `json:"features"`
}

func (s *BeaconIngestionService) ingestMN511Signs(ctx context.Context) {
	apiURL := fmt.Sprintf("%s/api/signs?bbox=-97.5,43.0,-89.0,49.5", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 signs fetch failed")
		return
	}

	var fc mn511GeoIngestionFC
	if err := json.Unmarshal(body, &fc); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 signs parse failed")
		return
	}

	alerts := make([]*repository.BeaconAlert, 0)
	activeIDs := make([]string, 0)

	for _, f := range fc.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}

		var props mn511SignIngestionProps
		if err := json.Unmarshal(f.Properties, &props); err != nil {
			continue
		}
		if props.SignStatus != "DISPLAYING_MESSAGE" {
			continue
		}

		var imgPtr *string
		if len(props.Views) > 0 && props.Views[0].ImageURL != "" {
			imgPtr = &props.Views[0].ImageURL
		}

		displayTitle := props.Title
		if props.RouteDesignator != "" && displayTitle == "" {
			displayTitle = props.RouteDesignator
		}

		lon := f.Geometry.Coordinates[0]
		lat := f.Geometry.Coordinates[1]

		src := "MN 511"
		handle := "@mn511"
		display := "MN 511"
		authorID := "00000000-0000-0000-0000-000000000511"

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     f.ID,
			Source:         "mn511_sign",
			BeaconType:     "sign",
			Severity:       "low",
			Title:          displayTitle,
			Body:           displayTitle,
			Lat:            lat,
			Lng:            lon,
			Radius:         50,
			ImageURL:       imgPtr,
			IsOfficial:     true,
			OfficialSource: &src,
			AuthorID:       &authorID,
			AuthorHandle:   &handle,
			AuthorDisplay:  &display,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			Tags:           []string{},
			CreatedAt:      time.Now().UTC(),
		})
		activeIDs = append(activeIDs, f.ID)
	}

	count, _ := s.repo.BulkUpsert(ctx, alerts)
	orphaned, _ := s.repo.CleanOrphaned(ctx, "mn511_sign", activeIDs)
	log.Info().Int("upserted", count).Int64("orphaned", orphaned).Msg("beacon ingestion: mn511 signs")
}

// ── MN511 Weather Stations ───────────────────────────────────────────────

type mn511WeatherIngestionProps struct {
	Title           string                              `json:"title"`
	Status          string                              `json:"status"`
	RouteDesignator string                              `json:"routeDesignator"`
	WeatherFields   map[string]mn511WeatherIngestionField `json:"weatherFields"`
}

type mn511WeatherIngestionField struct {
	FieldName    string `json:"fieldName"`
	DisplayValue string `json:"displayValue"`
	InAlertState bool   `json:"inAlertState"`
}

func (s *BeaconIngestionService) ingestMN511Weather(ctx context.Context) {
	apiURL := fmt.Sprintf("%s/api/weather-stations?bbox=-97.5,43.0,-89.0,49.5", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 weather fetch failed")
		return
	}

	var fc mn511GeoIngestionFC
	if err := json.Unmarshal(body, &fc); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 weather parse failed")
		return
	}

	alerts := make([]*repository.BeaconAlert, 0)
	activeIDs := make([]string, 0)

	for _, f := range fc.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}

		var props mn511WeatherIngestionProps
		if err := json.Unmarshal(f.Properties, &props); err != nil {
			continue
		}

		summary := weatherIngestionSummary(props)
		lon := f.Geometry.Coordinates[0]
		lat := f.Geometry.Coordinates[1]

		src := "MN 511"
		handle := "@mn511"
		display := "MN 511"
		authorID := "00000000-0000-0000-0000-000000000511"

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     f.ID,
			Source:         "mn511_weather",
			BeaconType:     "weather_station",
			Severity:       weatherIngestionSeverity(props.Status),
			Title:          props.Title,
			Body:           summary,
			Lat:            lat,
			Lng:            lon,
			Radius:         200,
			IsOfficial:     true,
			OfficialSource: &src,
			AuthorID:       &authorID,
			AuthorHandle:   &handle,
			AuthorDisplay:  &display,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			Tags:           []string{},
			CreatedAt:      time.Now().UTC(),
		})
		activeIDs = append(activeIDs, f.ID)
	}

	count, _ := s.repo.BulkUpsert(ctx, alerts)
	orphaned, _ := s.repo.CleanOrphaned(ctx, "mn511_weather", activeIDs)
	log.Info().Int("upserted", count).Int64("orphaned", orphaned).Msg("beacon ingestion: mn511 weather")
}

// ── IcedCoffee ───────────────────────────────────────────────────────────

func (s *BeaconIngestionService) ingestIced(ctx context.Context) {
	// IcedCoffee returns Sojorn-compatible beacon JSON.
	// We use Minneapolis center as the reference point with a wide radius.
	apiURL := fmt.Sprintf("%s/api/v1/beacons?lat=44.9778&long=-93.2650&radius=80000", s.icedBase)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: iced fetch failed")
		return
	}

	var resp struct {
		Beacons []map[string]any `json:"beacons"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: iced parse failed")
		return
	}

	alerts := make([]*repository.BeaconAlert, 0, len(resp.Beacons))
	activeIDs := make([]string, 0, len(resp.Beacons))

	for _, b := range resp.Beacons {
		id := jsonStr(b, "id")
		if id == "" {
			continue
		}

		lat := jsonFloat(b, "beacon_lat")
		lng := jsonFloat(b, "beacon_long")
		if lat == 0 && lng == 0 {
			continue
		}

		beaconType := jsonStr(b, "beacon_type")
		if beaconType == "" {
			beaconType = "hazard"
		}

		severity := jsonStr(b, "severity")
		if severity == "" {
			severity = "medium"
		}

		bodyText := jsonStr(b, "body")
		imgURL := jsonStrPtr(b, "image_url")
		vidURL := jsonStrPtr(b, "video_url")
		officialSource := jsonStrPtr(b, "official_source")
		authorID := jsonStrPtr(b, "author_id")
		authorHandle := jsonStrPtr(b, "author_handle")
		authorDisplay := jsonStrPtr(b, "author_display_name")

		isOfficial := false
		if v, ok := b["is_official"].(bool); ok {
			isOfficial = v
		}

		radius := 500
		if v, ok := b["radius"].(float64); ok {
			radius = int(v)
		}

		// 4-hour default expiry for iced alerts
		expiresAt := time.Now().UTC().Add(4 * time.Hour)

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     id,
			Source:         "iced",
			BeaconType:     beaconType,
			Severity:       severity,
			Body:           bodyText,
			Lat:            lat,
			Lng:            lng,
			Radius:         radius,
			ImageURL:       imgURL,
			VideoURL:       vidURL,
			IsOfficial:     isOfficial,
			OfficialSource: officialSource,
			AuthorID:       authorID,
			AuthorHandle:   authorHandle,
			AuthorDisplay:  authorDisplay,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			Tags:           []string{},
			ExpiresAt:      &expiresAt,
			CreatedAt:      time.Now().UTC(),
		})
		activeIDs = append(activeIDs, id)
	}

	count, _ := s.repo.BulkUpsert(ctx, alerts)
	orphaned, _ := s.repo.CleanOrphaned(ctx, "iced", activeIDs)
	log.Info().Int("upserted", count).Int64("orphaned", orphaned).Msg("beacon ingestion: iced")
}

// ── Helpers ──────────────────────────────────────────────────────────────

func (s *BeaconIngestionService) fetchJSON(url string) ([]byte, error) {
	resp, err := s.client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetch %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch %s: status %d", url, resp.StatusCode)
	}

	return io.ReadAll(resp.Body)
}

func mn511CatToType(category string) string {
	switch category {
	case "CRASH", "INCIDENT", "WARNING", "SURFACE_INCIDENT":
		return "safety"
	case "CLOSURE", "LANE_CLOSURE", "CONSTRUCTION", "WEATHER", "CONDITION", "ROAD":
		return "hazard"
	case "RESTRICTION":
		return "checkpoint"
	default:
		return "hazard"
	}
}

func mn511SevToString(s int) string {
	switch {
	case s >= 8:
		return "critical"
	case s >= 5:
		return "high"
	case s >= 3:
		return "medium"
	default:
		return "low"
	}
}

func weatherIngestionSeverity(status string) string {
	switch status {
	case "FREEZING", "ICY":
		return "high"
	case "SNOWING", "WET", "SLIPPERY":
		return "medium"
	default:
		return "low"
	}
}

func weatherIngestionSummary(props mn511WeatherIngestionProps) string {
	title := props.Title
	if props.RouteDesignator != "" {
		title = props.RouteDesignator + " — " + props.Title
	}

	fields := props.WeatherFields
	parts := []string{title}

	if f, ok := fields["TEMP_AIR_TEMPERATURE"]; ok && f.DisplayValue != "" {
		parts = append(parts, f.DisplayValue)
	}
	if f, ok := fields["PRECIP_SITUATION"]; ok && f.DisplayValue != "" && f.DisplayValue != "No Report" {
		parts = append(parts, f.DisplayValue)
	}
	if f, ok := fields["IA_SURFACE_SITUATION"]; ok && f.DisplayValue != "" && f.DisplayValue != "No Report" {
		parts = append(parts, "Road: "+f.DisplayValue)
	} else if f, ok := fields["PAVEMENT_SURFACE_STATUS"]; ok && f.DisplayValue != "" && f.DisplayValue != "Error" {
		parts = append(parts, "Road: "+f.DisplayValue)
	}

	result := parts[0]
	for i := 1; i < len(parts); i++ {
		if i == 1 {
			result += " | " + parts[i]
		} else {
			result += " · " + parts[i]
		}
	}
	return result
}

func jsonStr(m map[string]any, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func jsonStrPtr(m map[string]any, key string) *string {
	if v, ok := m[key].(string); ok && v != "" {
		return &v
	}
	return nil
}

func jsonFloat(m map[string]any, key string) float64 {
	if v, ok := m[key].(float64); ok {
		return v
	}
	return 0
}

// Suppress unused import warning for math
var _ = math.Pi
