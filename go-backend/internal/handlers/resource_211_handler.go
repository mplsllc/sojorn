// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

// Resource211Handler proxies to the 211 National Data Platform API with a
// 24-hour lazy cache stored in beacon_alerts (source="211").
// On cache miss: fetches from 211 API, upserts, returns results.
// On cache hit: returns from DB directly.
type Resource211Handler struct {
	repo    *repository.BeaconAlertRepository
	apiBase string
	apiKey  string
	client  *http.Client
}

func NewResource211Handler(repo *repository.BeaconAlertRepository, apiBase, apiKey string) *Resource211Handler {
	return &Resource211Handler{
		repo:    repo,
		apiBase: apiBase,
		apiKey:  apiKey,
		client:  &http.Client{Timeout: 15 * time.Second},
	}
}

// GetResources serves GET /api/v1/beacons/resources?lat=&long=&radius=&category=
func (h *Resource211Handler) GetResources(c *gin.Context) {
	if h.apiKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "211 API not configured", "beacons": []gin.H{}})
		return
	}

	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)
	category := c.Query("category")

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	ctx := c.Request.Context()

	// Check DB cache first.
	cached, err := h.repo.GetCachedSourceAlerts(ctx, "211", lat, long, int(radius), category)
	if err == nil && len(cached) > 0 {
		log.Debug().Int("count", len(cached)).Msg("211 resources: cache hit")
		c.JSON(http.StatusOK, gin.H{"beacons": cached})
		return
	}

	// Cache miss — fetch from 211 API.
	log.Info().Float64("lat", lat).Float64("long", long).Float64("radius", radius).Msg("211 resources: cache miss, fetching from API")
	alerts, err := h.fetch211Resources(ctx, lat, long, radius, category)
	if err != nil {
		log.Error().Err(err).Msg("211 resources: API fetch failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	if len(alerts) > 0 {
		if _, upsertErr := h.repo.BulkUpsert(ctx, alerts); upsertErr != nil {
			log.Warn().Err(upsertErr).Msg("211 resources: upsert failed")
		}
	}

	// Re-query from DB for consistent formatted JSON.
	results, err := h.repo.GetCachedSourceAlerts(ctx, "211", lat, long, int(radius), category)
	if err != nil || len(results) == 0 {
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// ─── 211 API structures ──────────────────────────────────────────────────────

type res211SearchResponse struct {
	TotalRecords int            `json:"TotalRecords"`
	Records      []res211Record `json:"Records"`
}

type res211Record struct {
	ResourceAgencyNum  string          `json:"ResourceAgencyNum"`
	AgencyName         string          `json:"AgencyName"`
	PublicName         string          `json:"PublicName"`
	ServiceName        string          `json:"ServiceName"`
	ServiceDescription string          `json:"ServiceDescription"`
	Latitude           float64         `json:"Latitude"`
	Longitude          float64         `json:"Longitude"`
	PhoneNumbers       []res211Phone   `json:"PhoneNumbers"`
	TaxonomyCodes      []res211TaxCode `json:"TaxonomyCodes"`
	HoursOfOperation   string          `json:"HoursOfOperationDescription"`
	Site               res211Site      `json:"Site"`
	URL                string          `json:"URL"`
}

type res211Phone struct {
	Number string `json:"Number"`
	Type   string `json:"Type"`
}

type res211TaxCode struct {
	Code string `json:"Code"`
	Name string `json:"Name"`
}

type res211Site struct {
	SiteName        string `json:"SiteName"`
	PhysicalAddress struct {
		AddressLine1 string `json:"AddressLine1"`
		City         string `json:"City"`
		State        string `json:"State"`
		ZipCode      string `json:"ZipCode"`
	} `json:"PhysicalAddress"`
}

// taxonomyToTag maps AIRS taxonomy code prefixes → simple tag strings.
var res211TaxonomyToTag = map[string]string{
	"BD": "food",          // Basic Needs
	"BH": "food",          // Food Programs
	"BL": "housing",       // Housing/Shelter
	"LH": "mental_health", // Mental Health Care
	"LR": "substance_use", // Substance Use Disorder
	"JR": "legal",         // Legal Services
	"NL": "utilities",     // Utilities Assistance
	"LK": "medical",       // Medical Care
	"YF": "youth",         // Youth Services
	"DF": "disability",    // Disability Services
	"ND": "financial",     // Financial Assistance
	"PH": "crisis",        // Crisis Intervention
}

func (h *Resource211Handler) fetch211Resources(ctx context.Context, lat, long, radiusMeters float64, category string) ([]*repository.BeaconAlert, error) {
	radiusKm := radiusMeters / 1000.0
	apiURL := fmt.Sprintf("%s/api/search?latitude=%.6f&longitude=%.6f&distance=%.1f&per_page=50",
		h.apiBase, lat, long, radiusKm)
	if category != "" {
		apiURL += "&taxonomy_term=" + category
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, fmt.Errorf("211 build request: %w", err)
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", h.apiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := h.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("211 HTTP: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("211 read body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("211 API returned status %d: %s", resp.StatusCode, string(body))
	}

	var searchResp res211SearchResponse
	if err := json.Unmarshal(body, &searchResp); err != nil {
		return nil, fmt.Errorf("211 parse: %w", err)
	}

	officialSource := "211"
	authorID := "00000000-0000-0000-0000-000000000211"
	authorHandle := "@211"
	authorDisplay := "211 Resources"
	expiresAt := time.Now().Add(24 * time.Hour)

	alerts := make([]*repository.BeaconAlert, 0, len(searchResp.Records))
	for _, r := range searchResp.Records {
		if r.Latitude == 0 && r.Longitude == 0 {
			continue
		}

		// Display name: prefer ServiceName, fall back to PublicName or AgencyName.
		displayName := r.ServiceName
		if displayName == "" {
			displayName = r.PublicName
		}
		if displayName == "" {
			displayName = r.AgencyName
		}

		// Body: description + address + phone + hours.
		var parts []string
		desc := strings.TrimSpace(r.ServiceDescription)
		if desc != "" {
			if utf8.RuneCountInString(desc) > 300 {
				runes := []rune(desc)
				desc = string(runes[:300]) + "…"
			}
			parts = append(parts, desc)
		}
		if addr := res211BuildAddress(r); addr != "" {
			parts = append(parts, addr)
		}
		if phone := res211PrimaryPhone(r.PhoneNumbers); phone != "" {
			parts = append(parts, "📞 "+phone)
		}
		if r.HoursOfOperation != "" {
			parts = append(parts, "🕐 "+r.HoursOfOperation)
		}
		bodyText := strings.Join(parts, "\n")
		if bodyText == "" {
			bodyText = displayName
		}

		// Map taxonomy codes → tags.
		tagSet := map[string]struct{}{}
		for _, tc := range r.TaxonomyCodes {
			prefix := tc.Code
			if len(prefix) >= 2 {
				prefix = prefix[:2]
			}
			if tag, ok := res211TaxonomyToTag[prefix]; ok {
				tagSet[tag] = struct{}{}
			}
		}
		tags := make([]string, 0, len(tagSet))
		for t := range tagSet {
			tags = append(tags, t)
		}
		if len(tags) == 0 {
			tags = []string{"resource"}
		}

		externalID := r.ResourceAgencyNum
		if externalID == "" {
			externalID = fmt.Sprintf("%.6f_%.6f_%s", r.Latitude, r.Longitude, res211SanitizeID(displayName))
		}

		alerts = append(alerts, &repository.BeaconAlert{
			ExternalID:     externalID,
			Source:         "211",
			BeaconType:     "resource",
			Severity:       "low",
			Title:          displayName,
			Body:           bodyText,
			Lat:            r.Latitude,
			Lng:            r.Longitude,
			Radius:         100,
			IsOfficial:     true,
			OfficialSource: &officialSource,
			AuthorID:       &authorID,
			AuthorHandle:   &authorHandle,
			AuthorDisplay:  &authorDisplay,
			Status:         "active",
			IncidentStatus: "active",
			Confidence:     1.0,
			Tags:           tags,
			ExpiresAt:      &expiresAt,
			CreatedAt:      time.Now(),
		})
	}
	return alerts, nil
}

func res211BuildAddress(r res211Record) string {
	pa := r.Site.PhysicalAddress
	var parts []string
	if pa.AddressLine1 != "" {
		parts = append(parts, pa.AddressLine1)
	}
	if pa.City != "" {
		parts = append(parts, pa.City)
	}
	if pa.State != "" {
		parts = append(parts, pa.State)
	}
	if len(parts) == 0 {
		return ""
	}
	return "📍 " + strings.Join(parts, ", ")
}

func res211PrimaryPhone(phones []res211Phone) string {
	for _, p := range phones {
		if p.Number != "" {
			return p.Number
		}
	}
	return ""
}

func res211SanitizeID(s string) string {
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else {
			b.WriteRune('_')
		}
	}
	out := b.String()
	if len(out) > 30 {
		out = out[:30]
	}
	return out
}
