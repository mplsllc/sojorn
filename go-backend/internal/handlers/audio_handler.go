// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"

	"github.com/gin-gonic/gin"
)

// AudioHandler proxies Freesound API requests so the Flutter app doesn't need
// direct API key access and we maintain a consistent audio library interface.
type AudioHandler struct {
	freesoundKey string // Freesound.org API key
}

func NewAudioHandler(freesoundKey string) *AudioHandler {
	return &AudioHandler{freesoundKey: freesoundKey}
}

// freesoundSearchResult is the raw response from Freesound text search.
type freesoundSearchResult struct {
	Count    int              `json:"count"`
	Next     *string          `json:"next"`
	Previous *string          `json:"previous"`
	Results  []freesoundSound `json:"results"`
}

type freesoundSound struct {
	ID       int               `json:"id"`
	Name     string            `json:"name"`
	Tags     []string          `json:"tags"`
	Duration float64           `json:"duration"`
	Username string            `json:"username"`
	License  string            `json:"license"`
	Previews map[string]string `json:"previews"`
}

// normalizedTrack is the shape Flutter expects.
type normalizedTrack struct {
	ID        string   `json:"id"`
	Title     string   `json:"title"`
	Artist    string   `json:"artist"`
	Duration  float64  `json:"duration"`
	ListenURL string   `json:"listen_url"`
	Tags      []string `json:"tags"`
	License   string   `json:"license"`
}

// SearchAudioLibrary proxies GET /audio/library?q=&page=&tags= to Freesound text search.
func (h *AudioHandler) SearchAudioLibrary(c *gin.Context) {
	if h.freesoundKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":  "audio library not yet configured — set FREESOUND_API_KEY",
			"tracks": []any{},
			"count":  0,
		})
		return
	}

	q := c.DefaultQuery("q", "")
	page := c.DefaultQuery("page", "1")
	tags := c.DefaultQuery("tags", "")

	// Build Freesound search URL
	params := url.Values{
		"query":     {q},
		"page":      {page},
		"page_size": {"20"},
		"fields":    {"id,name,tags,duration,previews,username,license"},
		"token":     {h.freesoundKey},
	}
	if tags != "" {
		params.Set("filter", fmt.Sprintf("tag:%s", tags))
	}

	target := fmt.Sprintf("https://freesound.org/apiv2/search/text/?%s", params.Encode())
	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, target, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "audio library unavailable"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		c.JSON(resp.StatusCode, gin.H{"error": "freesound error", "detail": string(body)})
		return
	}

	var fsResult freesoundSearchResult
	if err := json.NewDecoder(resp.Body).Decode(&fsResult); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse audio results"})
		return
	}

	// Normalize to the shape Flutter expects
	tracks := make([]normalizedTrack, 0, len(fsResult.Results))
	for _, s := range fsResult.Results {
		tracks = append(tracks, normalizedTrack{
			ID:        fmt.Sprintf("%d", s.ID),
			Title:     s.Name,
			Artist:    s.Username,
			Duration:  s.Duration,
			ListenURL: fmt.Sprintf("/api/v1/audio/library/%d/listen", s.ID),
			Tags:      s.Tags,
			License:   s.License,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"tracks": tracks,
		"count":  fsResult.Count,
	})
}

// GetAudioTrackListen proxies the audio preview stream for a Freesound sound.
// Flutter uses this URL in ffmpeg_kit as the audio input.
func (h *AudioHandler) GetAudioTrackListen(c *gin.Context) {
	if h.freesoundKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "audio library not yet configured"})
		return
	}

	trackID := c.Param("trackId")

	// First, fetch the sound details to get the preview URL
	detailURL := fmt.Sprintf("https://freesound.org/apiv2/sounds/%s/?fields=id,name,previews&token=%s",
		url.PathEscape(trackID), h.freesoundKey)

	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, detailURL, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "audio stream unavailable"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.JSON(resp.StatusCode, gin.H{"error": "sound not found"})
		return
	}

	var sound freesoundSound
	if err := json.NewDecoder(resp.Body).Decode(&sound); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse sound data"})
		return
	}

	// Get the best preview URL (prefer HQ MP3)
	previewURL := sound.Previews["preview-hq-mp3"]
	if previewURL == "" {
		previewURL = sound.Previews["preview-lq-mp3"]
	}
	if previewURL == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no preview available for this sound"})
		return
	}

	// Proxy the audio stream
	audioReq, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, previewURL, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create stream request"})
		return
	}

	audioResp, err := http.DefaultClient.Do(audioReq)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "audio stream unavailable"})
		return
	}
	defer audioResp.Body.Close()

	contentType := audioResp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "audio/mpeg"
	}
	c.DataFromReader(audioResp.StatusCode, audioResp.ContentLength, contentType, audioResp.Body, nil)
}
