// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

const mn511BaseURL = "http://127.0.0.1:8787"

// mn511Feature represents a single GeoJSON Feature from the MN511 API.
type mn511Feature struct {
	Type string `json:"type"`
	ID   string `json:"id"`
	Geometry struct {
		Type        string    `json:"type"`
		Coordinates []float64 `json:"coordinates"` // [lon, lat]
	} `json:"geometry"`
	Properties struct {
		Title       string  `json:"title"`
		Category    string  `json:"category"`
		Severity    int     `json:"severity"`
		Priority    int     `json:"priority"`
		Status      string  `json:"status"`
		Source      string  `json:"source"`
		FirstSeenAt string  `json:"first_seen_at"`
		LastSeenAt  string  `json:"last_seen_at"`
		Lat         float64 `json:"lat"`
		Lon         float64 `json:"lon"`
	} `json:"properties"`
}

type mn511Response struct {
	OK       bool           `json:"ok"`
	Count    int            `json:"count"`
	Type     string         `json:"type"`
	Features []mn511Feature `json:"features"`
}

// GetOfficialAlerts fetches live MN511 incidents and returns them in the same
// JSON shape as GetNearbyBeacons so the Flutter client can handle them uniformly.
func (h *PostHandler) GetOfficialAlerts(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	// Convert radius (meters) to a bounding box in degrees.
	// Rough approximation: 1° lat ≈ 111 km, 1° lon ≈ 111 km * cos(lat)
	latDelta := (radius / 1000.0) / 111.0
	lonDelta := (radius / 1000.0) / (111.0 * math.Cos(lat*math.Pi/180.0))

	minLat := lat - latDelta
	maxLat := lat + latDelta
	minLon := long - lonDelta
	maxLon := long + lonDelta

	bbox := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f", minLon, minLat, maxLon, maxLat)
	apiURL := fmt.Sprintf("%s/api/alerts?bbox=%s&status=active", mn511BaseURL, bbox)

	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(apiURL)
	if err != nil {
		log.Error().Err(err).Str("url", apiURL).Msg("mn511: upstream request failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Error().Err(err).Msg("mn511: failed to read response body")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	var mn511Resp mn511Response
	if err := json.Unmarshal(body, &mn511Resp); err != nil {
		log.Error().Err(err).Str("body", string(body)).Msg("mn511: failed to parse response")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	results := make([]gin.H, 0, len(mn511Resp.Features))
	for _, f := range mn511Resp.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}
		fLon := f.Geometry.Coordinates[0]
		fLat := f.Geometry.Coordinates[1]

		// Distance from user (Haversine, meters)
		dist := haversineMeters(lat, long, fLat, fLon)

		// Map MN511 category → Sojorn beacon_type
		beaconType := mn511CategoryToBeaconType(f.Properties.Category)

		// Map MN511 severity (1–10) → Sojorn severity string
		severity := mn511SeverityToString(f.Properties.Severity)

		// Parse timestamps
		createdAt := f.Properties.FirstSeenAt
		if createdAt == "" {
			createdAt = time.Now().UTC().Format(time.RFC3339)
		}

		item := gin.H{
			// Identity
			"id":      f.ID,
			"body":    f.Properties.Title,
			"created_at": createdAt,

			// Beacon flags
			"is_beacon":          true,
			"is_active_beacon":   true,
			"beacon_type":        beaconType,
			"severity":           severity,
			"incident_status":    "active",
			"confidence_score":   1.0,
			"verification_count": 10,
			"vouch_count":        10,
			"report_count":       0,
			"status_color":       "green",

			// Location
			"beacon_lat":      fLat,
			"beacon_long":     fLon,
			"distance_meters": dist,
			"radius":          500,

			// Source attribution
			"author_id":           "00000000-0000-0000-0000-000000000511",
			"author_handle":       "@mn511",
			"author_display_name": "MN 511",
			"is_official":         true,
			"official_source":     "MN 511",

			// No image
			"image_url": nil,
			"tags":      []string{},
		}
		results = append(results, item)
	}

	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// mn511CategoryToBeaconType maps MN511 category strings to Sojorn beacon types.
func mn511CategoryToBeaconType(category string) string {
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

// mn511Camera represents a single entry from the /api/camera-views endpoint.
type mn511Camera struct {
	ID                    string  `json:"id"`
	Title                 string  `json:"title"`
	Category              string  `json:"category"` // VIDEO or IMAGE
	URL                   string  `json:"url"`      // web viewer URL
	ParentRouteDesignator string  `json:"parent_route_designator"`
	Lat                   float64 `json:"lat"`
	Lon                   float64 `json:"lon"`
	LastUpdatedAt         string  `json:"last_updated_at"`
	Sources               []struct {
		Type string `json:"type"`
		Src  string `json:"src"`
	} `json:"sources"`
}

type mn511CameraResponse struct {
	OK      bool           `json:"ok"`
	Count   int            `json:"count"`
	Cameras []mn511Camera  `json:"cameras"`
}

// GetOfficialCameras fetches MN511 traffic cameras within the given radius and
// returns them in the beacon JSON shape with beacon_type "camera".
func (h *PostHandler) GetOfficialCameras(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	latDelta := (radius / 1000.0) / 111.0
	lonDelta := (radius / 1000.0) / (111.0 * math.Cos(lat*math.Pi/180.0))

	bbox := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f",
		long-lonDelta, lat-latDelta, long+lonDelta, lat+latDelta)
	apiURL := fmt.Sprintf("%s/api/camera-views?bbox=%s&limit=300", mn511BaseURL, bbox)

	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(apiURL)
	if err != nil {
		log.Error().Err(err).Str("url", apiURL).Msg("mn511 cameras: upstream request failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Error().Err(err).Msg("mn511 cameras: failed to read response body")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	var camResp mn511CameraResponse
	if err := json.Unmarshal(body, &camResp); err != nil {
		log.Error().Err(err).Str("body", string(body)[:min(200, len(body))]).Msg("mn511 cameras: failed to parse response")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	results := make([]gin.H, 0, len(camResp.Cameras))
	for _, cam := range camResp.Cameras {
		if cam.Lat == 0 || cam.Lon == 0 {
			continue
		}

		// Extract HLS stream URL from sources array.
		streamURL := ""
		for _, s := range cam.Sources {
			if s.Type == "application/x-mpegURL" || s.Src != "" {
				streamURL = s.Src
				break
			}
		}

		createdAt := cam.LastUpdatedAt
		if createdAt == "" {
			createdAt = time.Now().UTC().Format(time.RFC3339)
		}

		displayTitle := cam.Title
		if cam.ParentRouteDesignator != "" {
			displayTitle = cam.ParentRouteDesignator + " — " + cam.Title
		}

		dist := haversineMeters(lat, long, cam.Lat, cam.Lon)

		item := gin.H{
			"id":         cam.ID,
			"body":       displayTitle,
			"created_at": createdAt,

			"is_beacon":          true,
			"is_active_beacon":   true,
			"beacon_type":        "camera",
			"severity":           "low",
			"incident_status":    "active",
			"confidence_score":   1.0,
			"verification_count": 0,
			"vouch_count":        0,
			"report_count":       0,
			"status_color":       "green",

			"beacon_lat":      cam.Lat,
			"beacon_long":     cam.Lon,
			"distance_meters": dist,
			"radius":          50,

			"author_id":           "00000000-0000-0000-0000-000000000511",
			"author_handle":       "@mn511",
			"author_display_name": "MN 511",
			"is_official":         true,
			"official_source":     "MN 511",

			// image_url = web viewer; video_url = HLS stream
			"image_url": cam.URL,
			"video_url": streamURL,
			"tags":      []string{},
		}
		results = append(results, item)
	}

	log.Info().Int("count", len(results)).Msg("mn511 cameras: returned")
	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ─── GeoJSON helper ───────────────────────────────────────────────────────

// mn511GeoFeature represents a generic GeoJSON Point feature returned by the
// MN511 API's signs and weather-station endpoints.
type mn511GeoFeature struct {
	ID       string `json:"id"`
	Geometry struct {
		Coordinates []float64 `json:"coordinates"` // [lon, lat]
	} `json:"geometry"`
	Properties json.RawMessage `json:"properties"`
}

type mn511GeoFC struct {
	OK       bool              `json:"ok"`
	Count    int               `json:"count"`
	Type     string            `json:"type"`
	Features []mn511GeoFeature `json:"features"`
}

// ─── Signs (DMS / Electronic Road Signs) ─────────────────────────────────

type mn511SignProps struct {
	URI             string `json:"uri"`
	Title           string `json:"title"`
	CityReference   string `json:"cityReference"`
	RouteDesignator string `json:"routeDesignator"`
	SignStatus      string `json:"signStatus"` // DISPLAYING_MESSAGE etc.
	Views           []struct {
		ImageURL string `json:"imageUrl"`
		Category string `json:"category"`
	} `json:"views"`
}

// GetOfficialSigns fetches MN DOT electronic road signs (DMS) within the
// given bbox and returns them in the beacon JSON shape with beacon_type "sign".
func (h *PostHandler) GetOfficialSigns(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	latDelta := (radius / 1000.0) / 111.0
	lonDelta := (radius / 1000.0) / (111.0 * math.Cos(lat*math.Pi/180.0))
	bbox := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f", long-lonDelta, lat-latDelta, long+lonDelta, lat+latDelta)

	apiURL := fmt.Sprintf("%s/api/signs?bbox=%s", mn511BaseURL, bbox)
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(apiURL)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var fc mn511GeoFC
	if err := json.Unmarshal(body, &fc); err != nil {
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	results := make([]gin.H, 0, len(fc.Features))
	for _, f := range fc.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}
		fLon := f.Geometry.Coordinates[0]
		fLat := f.Geometry.Coordinates[1]

		var props mn511SignProps
		if err := json.Unmarshal(f.Properties, &props); err != nil {
			continue
		}

		// Only show signs that are actively displaying a message
		if props.SignStatus != "DISPLAYING_MESSAGE" {
			continue
		}

		// Use the first view's GIF image
		var imageURL string
		if len(props.Views) > 0 {
			imageURL = props.Views[0].ImageURL
		}

		displayTitle := props.Title
		if props.RouteDesignator != "" && displayTitle == "" {
			displayTitle = props.RouteDesignator
		}

		dist := haversineMeters(lat, long, fLat, fLon)

		createdAt := time.Now().UTC().Format(time.RFC3339)
		item := gin.H{
			"id":         f.ID,
			"body":       displayTitle,
			"created_at": createdAt,

			"is_beacon":          true,
			"is_active_beacon":   true,
			"beacon_type":        "sign",
			"severity":           "low",
			"incident_status":    "active",
			"confidence_score":   1.0,
			"verification_count": 0,
			"vouch_count":        0,
			"report_count":       0,
			"status_color":       "green",

			"beacon_lat":      fLat,
			"beacon_long":     fLon,
			"distance_meters": dist,
			"radius":          50,

			"author_id":           "00000000-0000-0000-0000-000000000511",
			"author_handle":       "@mn511",
			"author_display_name": "MN 511",
			"is_official":         true,
			"official_source":     "MN 511",

			"image_url": imageURL, // GIF of the sign display
			"tags":      []string{},
		}
		results = append(results, item)
	}

	log.Info().Int("count", len(results)).Msg("mn511 signs: returned")
	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// ─── Weather Stations (RWIS) ─────────────────────────────────────────────

type mn511WeatherField struct {
	FieldName    string `json:"fieldName"`
	DisplayValue string `json:"displayValue"`
	InAlertState bool   `json:"inAlertState"`
	IsTopField   bool   `json:"isTopField"`
}

type mn511WeatherProps struct {
	URI             string                       `json:"uri"`
	Title           string                       `json:"title"`
	Status          string                       `json:"status"` // FREEZING, NORMAL, etc.
	RouteDesignator string                       `json:"routeDesignator"`
	WeatherFields   map[string]mn511WeatherField `json:"weatherFields"`
}

// GetOfficialWeatherStations fetches MN DOT RWIS weather sensor stations and
// returns them in the beacon JSON shape with beacon_type "weather_station".
func (h *PostHandler) GetOfficialWeatherStations(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	latDelta := (radius / 1000.0) / 111.0
	lonDelta := (radius / 1000.0) / (111.0 * math.Cos(lat*math.Pi/180.0))
	bbox := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f", long-lonDelta, lat-latDelta, long+lonDelta, lat+latDelta)

	apiURL := fmt.Sprintf("%s/api/weather-stations?bbox=%s", mn511BaseURL, bbox)
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(apiURL)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var fc mn511GeoFC
	if err := json.Unmarshal(body, &fc); err != nil {
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	results := make([]gin.H, 0, len(fc.Features))
	for _, f := range fc.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}
		fLon := f.Geometry.Coordinates[0]
		fLat := f.Geometry.Coordinates[1]

		var props mn511WeatherProps
		if err := json.Unmarshal(f.Properties, &props); err != nil {
			continue
		}

		// Build a concise summary from top weather fields
		summary := mn511WeatherSummary(props)

		dist := haversineMeters(lat, long, fLat, fLon)
		createdAt := time.Now().UTC().Format(time.RFC3339)

		item := gin.H{
			"id":         f.ID,
			"body":       summary,
			"created_at": createdAt,

			"is_beacon":          true,
			"is_active_beacon":   true,
			"beacon_type":        "weather_station",
			"severity":           mn511WeatherSeverity(props.Status),
			"incident_status":    "active",
			"confidence_score":   1.0,
			"verification_count": 0,
			"vouch_count":        0,
			"report_count":       0,
			"status_color":       "green",

			"beacon_lat":      fLat,
			"beacon_long":     fLon,
			"distance_meters": dist,
			"radius":          200,

			"author_id":           "00000000-0000-0000-0000-000000000511",
			"author_handle":       "@mn511",
			"author_display_name": "MN 511",
			"is_official":         true,
			"official_source":     "MN 511",

			"image_url": nil,
			"tags":      []string{},
		}
		results = append(results, item)
	}

	log.Info().Int("count", len(results)).Msg("mn511 weather: returned")
	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// mn511WeatherSummary builds a concise human-readable summary from top fields.
func mn511WeatherSummary(props mn511WeatherProps) string {
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

// mn511WeatherSeverity maps RWIS status to Sojorn severity.
func mn511WeatherSeverity(status string) string {
	switch status {
	case "FREEZING", "ICY":
		return "high"
	case "SNOWING", "WET", "SLIPPERY":
		return "medium"
	default:
		return "low"
	}
}

// mn511SeverityToString maps MN511 1–10 severity to Sojorn severity strings.
func mn511SeverityToString(s int) string {
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

// haversineMeters returns the great-circle distance in meters between two lat/lon points.
func haversineMeters(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371000.0 // Earth radius in meters
	dLat := (lat2 - lat1) * math.Pi / 180.0
	dLon := (lon2 - lon1) * math.Pi / 180.0
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180.0)*math.Cos(lat2*math.Pi/180.0)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return R * c
}
