// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

// IcedHandler proxies requests to the IcedCoffee public-safety API.
// The upstream already returns Sojorn-compatible beacon JSON, so no
// transformation is needed — we just forward lat/long/radius and relay
// the response verbatim.
type IcedHandler struct {
	baseURL string
	client  *http.Client
}

func NewIcedHandler(baseURL string) *IcedHandler {
	return &IcedHandler{
		baseURL: baseURL,
		client:  &http.Client{Timeout: 8 * time.Second},
	}
}

// GetIcedAlerts proxies GET /api/v1/beacons to the IcedCoffee API.
func (h *IcedHandler) GetIcedAlerts(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	apiURL := fmt.Sprintf("%s/api/v1/beacons?lat=%.6f&long=%.6f&radius=%.0f",
		h.baseURL, lat, long, radius)

	resp, err := h.client.Get(apiURL)
	if err != nil {
		log.Error().Err(err).Str("url", apiURL).Msg("iced: upstream request failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Error().Err(err).Msg("iced: failed to read response body")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	if resp.StatusCode != http.StatusOK {
		log.Error().Int("status", resp.StatusCode).Str("body", string(body)).Msg("iced: upstream returned non-200")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	// Relay the upstream JSON directly — it's already in the right shape.
	c.Data(http.StatusOK, "application/json", body)
}
