package handlers

import (
	"fmt"
	"io"
	"net/http"
	"net/url"

	"github.com/gin-gonic/gin"
)

// AudioHandler proxies Funkwhale audio library requests so the Flutter app
// doesn't need CORS credentials or direct Funkwhale access.
type AudioHandler struct {
	funkwhaleBase string // e.g. "http://localhost:5001" — empty = not yet deployed
}

func NewAudioHandler(funkwhaleBase string) *AudioHandler {
	return &AudioHandler{funkwhaleBase: funkwhaleBase}
}

// SearchAudioLibrary proxies GET /audio/library?q=&page= to Funkwhale /api/v1/tracks/
func (h *AudioHandler) SearchAudioLibrary(c *gin.Context) {
	if h.funkwhaleBase == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":  "audio library not yet configured — Funkwhale deployment pending",
			"tracks": []any{},
			"count":  0,
		})
		return
	}

	q := url.QueryEscape(c.DefaultQuery("q", ""))
	page := url.QueryEscape(c.DefaultQuery("page", "1"))

	target := fmt.Sprintf("%s/api/v1/tracks/?q=%s&page=%s&playable=true", h.funkwhaleBase, q, page)
	resp, err := http.Get(target) //nolint:gosec
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "audio library unavailable"})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	c.Data(resp.StatusCode, "application/json", body)
}

// GetAudioTrackListen proxies the audio stream for a track.
// Flutter uses this URL in ffmpeg_kit as the audio input.
func (h *AudioHandler) GetAudioTrackListen(c *gin.Context) {
	if h.funkwhaleBase == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "audio library not yet configured"})
		return
	}

	trackID := c.Param("trackId")
	target := fmt.Sprintf("%s/api/v1/listen/%s/", h.funkwhaleBase, url.PathEscape(trackID))

	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, target, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "audio stream unavailable"})
		return
	}
	defer resp.Body.Close()

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "audio/mpeg"
	}
	c.DataFromReader(resp.StatusCode, resp.ContentLength, contentType, resp.Body, nil)
}
