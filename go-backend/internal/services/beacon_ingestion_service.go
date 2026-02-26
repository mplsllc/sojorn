// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

// BeaconIngestionService periodically fetches alerts from external sources
// (MN511, IcedCoffee) and upserts them into the beacon_alerts table.
type BeaconIngestionService struct {
	repo         *repository.BeaconAlertRepository
	mn511Base    string
	icedBase     string
	s3Client     *s3.Client  // optional — used to cache sign images in R2
	r2Bucket     string
	r2ImgDomain  string
	client       *http.Client
	interval     time.Duration
	stopCh       chan struct{}
	wg           sync.WaitGroup
	manualSyncCh chan string // admin-triggered sync: "" = all, or specific source name
}

func NewBeaconIngestionService(
	repo *repository.BeaconAlertRepository,
	mn511Base string,
	icedBase string,
	s3Client *s3.Client,
	r2Bucket string,
	r2ImgDomain string,
) *BeaconIngestionService {
	return &BeaconIngestionService{
		repo:         repo,
		mn511Base:    mn511Base,
		icedBase:     icedBase,
		s3Client:     s3Client,
		r2Bucket:     r2Bucket,
		r2ImgDomain:  r2ImgDomain,
		client:       &http.Client{Timeout: 15 * time.Second},
		interval:     2 * time.Minute,
		stopCh:       make(chan struct{}),
		manualSyncCh: make(chan string, 1),
	}
}

// TriggerSync triggers a manual sync from the admin panel.
// Pass "" to sync all sources, or a specific source name.
func (s *BeaconIngestionService) TriggerSync(source string) {
	select {
	case s.manualSyncCh <- source:
	default:
		// Already a sync pending
	}
}

// GetFeedStatuses returns the current feed configurations from the database.
func (s *BeaconIngestionService) GetFeedStatuses(ctx context.Context) ([]repository.FeedConfig, error) {
	return s.repo.GetFeedConfigs(ctx)
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
			case source := <-s.manualSyncCh:
				if source == "" {
					log.Info().Msg("beacon ingestion: manual sync (all sources)")
					s.runCycle()
				} else {
					log.Info().Str("source", source).Msg("beacon ingestion: manual sync (single source)")
					ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
					s.runSingleSource(ctx, source)
					cancel()
				}
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
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	start := time.Now()

	// Expire stale external alerts (beacon_alerts table)
	expired, err := s.repo.ExpireStale(ctx)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: expire stale failed")
	} else if expired > 0 {
		log.Info().Int64("count", expired).Msg("beacon ingestion: expired stale alerts")
	}

	// Expire old user beacons in the posts table.
	// Any beacon older than 4 hours with no explicit expires_at is considered stale.
	// This catches beacons created before the default-TTL fix and any client-side omissions.
	expiredPosts, err := s.repo.ExpireStaleUserBeacons(ctx)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: expire stale user beacons failed")
	} else if expiredPosts > 0 {
		log.Info().Int64("count", expiredPosts).Msg("beacon ingestion: expired stale user beacons")
	}

	// Load feed configs to check which feeds are enabled
	enabledMap := s.loadFeedEnabledMap(ctx)

	// Fetch from all enabled sources in parallel
	var wg sync.WaitGroup

	type sourceFunc struct {
		name string
		fn   func(context.Context) (int, error)
	}
	sources := []sourceFunc{
		{"mn511", s.ingestMN511Alerts},
		{"mn511_camera", s.ingestMN511Cameras},
		{"mn511_sign", s.ingestMN511Signs},
		{"mn511_weather", s.ingestMN511Weather},
		{"iced", s.ingestIced},
	}

	for _, src := range sources {
		if !enabledMap[src.name] {
			continue
		}
		wg.Add(1)
		go func(name string, fn func(context.Context) (int, error)) {
			defer wg.Done()
			count, err := fn(ctx)
			var errStr *string
			if err != nil {
				s := err.Error()
				errStr = &s
			}
			_ = s.repo.UpdateFeedSyncStatus(ctx, name, errStr, count)
		}(src.name, src.fn)
	}

	wg.Wait()
	log.Debug().Dur("duration", time.Since(start)).Msg("beacon ingestion: cycle complete")
}

// runSingleSource runs ingestion for a single source by name.
func (s *BeaconIngestionService) runSingleSource(ctx context.Context, source string) {
	var fn func(context.Context) (int, error)
	switch source {
	case "mn511":
		fn = s.ingestMN511Alerts
	case "mn511_camera":
		fn = s.ingestMN511Cameras
	case "mn511_sign":
		fn = s.ingestMN511Signs
	case "mn511_weather":
		fn = s.ingestMN511Weather
	case "iced":
		fn = s.ingestIced
	default:
		log.Warn().Str("source", source).Msg("beacon ingestion: unknown source for manual sync")
		return
	}
	count, err := fn(ctx)
	var errStr *string
	if err != nil {
		s := err.Error()
		errStr = &s
	}
	_ = s.repo.UpdateFeedSyncStatus(ctx, source, errStr, count)
}

// loadFeedEnabledMap returns a map of source -> enabled. Defaults to true if DB is unreachable.
func (s *BeaconIngestionService) loadFeedEnabledMap(ctx context.Context) map[string]bool {
	configs, err := s.repo.GetFeedConfigs(ctx)
	if err != nil {
		log.Warn().Err(err).Msg("beacon ingestion: failed to load feed configs, running all")
		return map[string]bool{"mn511": true, "mn511_camera": true, "mn511_sign": true, "mn511_weather": true, "iced": true}
	}
	m := make(map[string]bool, len(configs))
	for _, c := range configs {
		m[c.Source] = c.Enabled
	}
	return m
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

func (s *BeaconIngestionService) ingestMN511Alerts(ctx context.Context) (int, error) {
	// Fetch a wide bounding box covering Minnesota
	apiURL := fmt.Sprintf("%s/api/alerts?bbox=-97.5,43.0,-89.0,49.5&status=active", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 alerts fetch failed")
		return 0, err
	}

	var resp mn511IngestionResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 alerts parse failed")
		return 0, err
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
			CreatedAt:      createdAt,
		})
		activeIDs = append(activeIDs, f.ID)
	}

	count, upsertErr := s.repo.BulkUpsert(ctx, alerts)
	if upsertErr != nil {
		log.Error().Err(upsertErr).Msg("beacon ingestion: mn511 alerts upsert failed — skipping orphan cleanup")
		return count, upsertErr
	}
	removed, _ := s.repo.CleanOrphaned(ctx, "mn511", activeIDs)
	log.Info().Int("upserted", count).Int64("removed", removed).Int("upstream", len(resp.Features)).Msg("beacon ingestion: mn511 alerts")
	return count, nil
}

// ── MN511 Cameras ────────────────────────────────────────────────────────

type mn511CamIngestion struct {
	ID                    string  `json:"id"`
	URI                   string  `json:"uri"`
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

// ingestMN511Cameras upserts MN511 camera views into beacon_alerts.
// Cameras are permanent infrastructure — fetched once, stored forever.
// The MN511 proxy keeps historical snapshots (IDs like camera/447254/4136196501
// where the first component is a snapshot ID that changes each scrape cycle).
// We extract the stable camera ID (second component) as external_id to deduplicate.
func (s *BeaconIngestionService) ingestMN511Cameras(ctx context.Context) (int, error) {
	existing, err := s.repo.CountBySource(ctx, "mn511_camera")
	if err == nil && existing >= 3000 {
		log.Debug().Int("existing", existing).Msg("beacon ingestion: mn511 cameras — skip (already populated)")
		return 0, nil
	}

	// The proxy's SQLite stores ~9000+ rows (historical snapshots).
	// Fetch all with a high limit, then deduplicate by stable camera ID.
	apiURL := fmt.Sprintf("%s/api/camera-views?bbox=-97.5,43.5,-89.5,49.5&limit=10000", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 cameras fetch failed")
		return 0, err
	}

	var resp mn511CamIngestionResp
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 cameras parse failed")
		return 0, err
	}

	log.Info().Int("returned", len(resp.Cameras)).Int("existing", existing).Msg("beacon ingestion: mn511 cameras fetched")

	src := "MN 511"
	handle := "@mn511"
	display := "MN 511"
	authorID := "00000000-0000-0000-0000-000000000511"

	// Deduplicate by stable camera ID (second component of "camera/SNAPSHOT/STABLE").
	// The proxy returns newest first (ORDER BY last_updated_at DESC), so the first
	// occurrence of each stable ID is the most recent data.
	seen := make(map[string]bool)
	var allAlerts []*repository.BeaconAlert

	for _, cam := range resp.Cameras {
		if cam.Lat == 0 || cam.Lon == 0 {
			continue
		}

		// Extract stable camera ID: "camera/447254/4136196501" → "4136196501"
		stableID := cam.ID
		parts := strings.Split(cam.ID, "/")
		if len(parts) == 3 {
			stableID = parts[2]
		}

		if seen[stableID] {
			continue
		}
		seen[stableID] = true

		streamURL := ""
		for _, s := range cam.Sources {
			if s.Type == "application/x-mpegURL" || s.Src != "" {
				streamURL = s.Src
				break
			}
		}

		displayTitle := cam.Title
		if cam.ParentRouteDesignator != "" {
			displayTitle = cam.ParentRouteDesignator + " — " + cam.Title
		}

		var imgPtr, vidPtr *string
		if cam.URL != "" {
			imgPtr = &cam.URL
		}
		if streamURL != "" {
			vidPtr = &streamURL
		}

		allAlerts = append(allAlerts, &repository.BeaconAlert{
			ExternalID:     stableID,
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
			CreatedAt:      time.Now().UTC(),
		})
	}

	if len(allAlerts) == 0 {
		return 0, nil
	}

	count, upsertErr := s.repo.BulkUpsert(ctx, allAlerts)
	if upsertErr != nil {
		log.Error().Err(upsertErr).Msg("beacon ingestion: mn511 cameras upsert failed")
		return count, upsertErr
	}
	log.Info().Int("upserted", count).Int("unique_cameras", len(seen)).Int("fetched", len(resp.Cameras)).Msg("beacon ingestion: mn511 cameras complete")
	return count, nil
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

func (s *BeaconIngestionService) ingestMN511Signs(ctx context.Context) (int, error) {
	apiURL := fmt.Sprintf("%s/api/signs?bbox=-97.5,43.0,-89.0,49.5", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 signs fetch failed")
		return 0, err
	}

	var fc mn511GeoIngestionFC
	if err := json.Unmarshal(body, &fc); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 signs parse failed")
		return 0, err
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

		// Cache sign image in R2 so the app loads from CDN instead of MN511 each time.
		var imgPtr *string
		if len(props.Views) > 0 && props.Views[0].ImageURL != "" {
			r2URL := s.cacheSignImage(ctx, f.ID, props.Views[0].ImageURL)
			if r2URL != "" {
				imgPtr = &r2URL
			} else {
				imgPtr = &props.Views[0].ImageURL // fallback to original URL
			}
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

	count, upsertErr := s.repo.BulkUpsert(ctx, alerts)
	if upsertErr != nil {
		log.Error().Err(upsertErr).Msg("beacon ingestion: mn511 signs upsert failed — skipping orphan cleanup")
		return count, upsertErr
	}
	removed, _ := s.repo.CleanOrphaned(ctx, "mn511_sign", activeIDs)
	log.Info().Int("upserted", count).Int64("removed", removed).Msg("beacon ingestion: mn511 signs")
	return count, nil
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

func (s *BeaconIngestionService) ingestMN511Weather(ctx context.Context) (int, error) {
	apiURL := fmt.Sprintf("%s/api/weather-stations?bbox=-97.5,43.0,-89.0,49.5", s.mn511Base)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 weather fetch failed")
		return 0, err
	}

	var fc mn511GeoIngestionFC
	if err := json.Unmarshal(body, &fc); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: mn511 weather parse failed")
		return 0, err
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

	count, upsertErr := s.repo.BulkUpsert(ctx, alerts)
	if upsertErr != nil {
		log.Error().Err(upsertErr).Msg("beacon ingestion: mn511 weather upsert failed — skipping orphan cleanup")
		return count, upsertErr
	}
	removed, _ := s.repo.CleanOrphaned(ctx, "mn511_weather", activeIDs)
	log.Info().Int("upserted", count).Int64("removed", removed).Msg("beacon ingestion: mn511 weather")
	return count, nil
}

// ── IcedCoffee ───────────────────────────────────────────────────────────

func (s *BeaconIngestionService) ingestIced(ctx context.Context) (int, error) {
	// IcedCoffee returns Sojorn-compatible beacon JSON.
	// We use Minneapolis center as the reference point with a wide radius.
	apiURL := fmt.Sprintf("%s/api/v1/beacons?lat=44.9778&long=-93.2650&radius=80000", s.icedBase)
	body, err := s.fetchJSON(apiURL)
	if err != nil {
		log.Error().Err(err).Msg("beacon ingestion: iced fetch failed")
		return 0, err
	}

	var resp struct {
		Beacons []map[string]any `json:"beacons"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		log.Error().Err(err).Msg("beacon ingestion: iced parse failed")
		return 0, err
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
			CreatedAt:      time.Now().UTC(),
		})
		activeIDs = append(activeIDs, id)
	}

	count, upsertErr := s.repo.BulkUpsert(ctx, alerts)
	if upsertErr != nil {
		log.Error().Err(upsertErr).Msg("beacon ingestion: iced upsert failed — skipping orphan cleanup")
		return count, upsertErr
	}
	removed, _ := s.repo.CleanOrphaned(ctx, "iced", activeIDs)
	log.Info().Int("upserted", count).Int64("removed", removed).Msg("beacon ingestion: iced")
	return count, nil
}

// ── Sign image cache ─────────────────────────────────────────────────────

// cacheSignImage downloads the MN511 sign GIF and stores it in R2 so the
// Flutter app loads from CDN instead of hitting MN511 on every request.
// Returns the R2 public URL, or "" if caching is unavailable/failed.
func (s *BeaconIngestionService) cacheSignImage(ctx context.Context, signID, mnURL string) string {
	if s.s3Client == nil || s.r2Bucket == "" || mnURL == "" {
		return ""
	}

	// Fetch the image from MN511.
	resp, err := s.client.Get(mnURL)
	if err != nil || resp.StatusCode != 200 {
		return ""
	}
	defer resp.Body.Close()

	imgBytes, err := io.ReadAll(resp.Body)
	if err != nil || len(imgBytes) == 0 {
		return ""
	}

	// Key: signs/{signID}/{contentHash}.gif — same message = same key = no re-upload.
	hash := fmt.Sprintf("%x", md5.Sum(imgBytes))
	key := fmt.Sprintf("signs/%s/%s.gif", signID, hash[:8])

	contentType := "image/gif"
	_, err = s.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &s.r2Bucket,
		Key:         &key,
		Body:        bytes.NewReader(imgBytes),
		ContentType: &contentType,
	})
	if err != nil {
		log.Warn().Err(err).Str("sign", signID).Msg("beacon ingestion: sign image R2 upload failed")
		return ""
	}

	if s.r2ImgDomain != "" {
		return fmt.Sprintf("https://%s/%s", s.r2ImgDomain, key)
	}
	return ""
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
