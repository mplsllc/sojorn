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
	case "CRASH", "INCIDENT", "WARNING":
		return "safety"
	case "CLOSURE", "LANE_CLOSURE", "CONSTRUCTION", "WEATHER":
		return "hazard"
	default:
		return "hazard"
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
