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
)

// OverpassService queries the OpenStreetMap Overpass API to reverse-geocode
// neighborhood information from coordinates.
type OverpassService struct {
	client  *http.Client
	baseURL string
}

func NewOverpassService() *OverpassService {
	return &OverpassService{
		client: &http.Client{
			Timeout: 15 * time.Second,
		},
		baseURL: "https://overpass-api.de/api/interpreter",
	}
}

// NeighborhoodResult holds the parsed result from the Overpass API.
type NeighborhoodResult struct {
	Name    string  // neighborhood name
	City    string  // city / town / village
	State   string  // state or province
	Country string  // country code (ISO 3166-1 alpha-2)
	Lat     float64 // center lat of the neighborhood area (or query point)
	Lng     float64 // center lng
}

// DetectNeighborhood queries Overpass for the neighborhood at the given point.
// It tries multiple OSM tags in priority order:
//  1. addr:neighbourhood / neighbourhood (admin_level ~10)
//  2. suburb (admin_level ~9)
//  3. city_district / quarter
//
// Returns nil if no neighborhood could be determined.
func (s *OverpassService) DetectNeighborhood(ctx context.Context, lat, lng float64) (*NeighborhoodResult, error) {
	// Overpass QL: find the smallest administrative area containing the point
	// that represents a neighborhood, suburb, or quarter.
	query := fmt.Sprintf(`
[out:json][timeout:10];
is_in(%f,%f)->.a;
(
  area.a["boundary"="administrative"]["admin_level"~"^(9|10|11)$"];
  area.a["place"~"^(neighbourhood|suburb|quarter)$"];
);
out tags center 1;

`, lat, lng)

	form := url.Values{}
	form.Set("data", query)

	req, err := http.NewRequestWithContext(ctx, "POST", s.baseURL, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, fmt.Errorf("overpass request build: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("overpass request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("overpass returned %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	var result overpassResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("overpass decode: %w", err)
	}

	if len(result.Elements) == 0 {
		return nil, nil // no neighborhood found
	}

	// Pick the best element: prefer the one with the highest admin_level (most specific)
	best := pickBestElement(result.Elements)
	if best == nil {
		return nil, nil
	}

	nr := &NeighborhoodResult{
		Lat: lat,
		Lng: lng,
	}

	nr.Name = firstNonEmpty(best.Tags["name:en"], best.Tags["name"], best.Tags["alt_name"])
	if nr.Name == "" {
		return nil, nil // unusable without a name
	}

	// Use center coordinates if available, otherwise use the query point
	if best.Center.Lat != 0 && best.Center.Lon != 0 {
		nr.Lat = best.Center.Lat
		nr.Lng = best.Center.Lon
	}

	return nr, nil
}

// ReverseGeocodeCity uses Nominatim to get city/state/country for a point.
// Called after Overpass to fill in the broader location context.
func (s *OverpassService) ReverseGeocodeCity(ctx context.Context, lat, lng float64) (city, state, country, zipCode string, err error) {
	reqURL := fmt.Sprintf(
		"https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=%f&lon=%f&zoom=10&addressdetails=1",
		lat, lng,
	)

	req, err := http.NewRequestWithContext(ctx, "GET", reqURL, nil)
	if err != nil {
		return "", "", "", "", fmt.Errorf("nominatim request build: %w", err)
	}
	req.Header.Set("User-Agent", "SojornApp/1.0 (neighborhood-detect)")

	resp, err := s.client.Do(req)
	if err != nil {
		return "", "", "", "", fmt.Errorf("nominatim request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", "", "", "", fmt.Errorf("nominatim returned %d", resp.StatusCode)
	}

	var nr nominatimResponse
	if err := json.NewDecoder(resp.Body).Decode(&nr); err != nil {
		return "", "", "", "", fmt.Errorf("nominatim decode: %w", err)
	}

	city = firstNonEmpty(nr.Address.City, nr.Address.Town, nr.Address.Village, nr.Address.Municipality, nr.Address.County)
	state = nr.Address.State
	country = nr.Address.CountryCode
	zipCode = nr.Address.PostCode

	if country != "" {
		country = strings.ToUpper(country)
	}

	return city, state, country, zipCode, nil
}

// ─── Internal types ──────────────────────────────────────────

type overpassResponse struct {
	Elements []overpassElement `json:"elements"`
}

type overpassElement struct {
	Type   string            `json:"type"`
	ID     int64             `json:"id"`
	Tags   map[string]string `json:"tags"`
	Center struct {
		Lat float64 `json:"lat"`
		Lon float64 `json:"lon"`
	} `json:"center"`
}

type nominatimResponse struct {
	Address struct {
		City         string `json:"city"`
		Town         string `json:"town"`
		Village      string `json:"village"`
		Municipality string `json:"municipality"`
		County       string `json:"county"`
		State        string `json:"state"`
		PostCode     string `json:"postcode"`
		CountryCode  string `json:"country_code"`
	} `json:"address"`
}

func pickBestElement(elements []overpassElement) *overpassElement {
	var best *overpassElement
	bestLevel := 0
	for i := range elements {
		el := &elements[i]
		name := firstNonEmpty(el.Tags["name:en"], el.Tags["name"])
		if name == "" {
			continue
		}

		level := 0
		al := el.Tags["admin_level"]
		switch al {
		case "11":
			level = 3
		case "10":
			level = 2
		case "9":
			level = 1
		}

		place := el.Tags["place"]
		switch place {
		case "neighbourhood":
			if level < 3 {
				level = 3
			}
		case "quarter":
			if level < 2 {
				level = 2
			}
		case "suburb":
			if level < 1 {
				level = 1
			}
		}

		if level > bestLevel || best == nil {
			best = el
			bestLevel = level
		}
	}
	return best
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
