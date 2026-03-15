// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/pkg/utils"
)

// GetAllCameras returns all active cameras statewide.
// Cameras are permanent infrastructure — clients should call this once
// per session and cache the result.
// GET /api/v1/beacons/cameras
func (h *BeaconUnifiedHandler) GetAllCameras(c *gin.Context) {
	results, err := h.repo.GetAllCameras(c.Request.Context())
	if err != nil {
		log.Error().Err(err).Msg("cameras: query failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"beacons": results})
}

// BeaconUnifiedHandler serves the single unified beacon endpoint that
// returns all alert types (external + user-created) in one response.
type BeaconUnifiedHandler struct {
	repo *repository.BeaconAlertRepository
}

func NewBeaconUnifiedHandler(repo *repository.BeaconAlertRepository) *BeaconUnifiedHandler {
	return &BeaconUnifiedHandler{repo: repo}
}

// GetUnifiedBeacons returns all active beacons (external alerts + user beacons)
// within the given radius of the provided lat/long.
// GET /api/v1/beacons/unified?lat=&long=&radius=
func (h *BeaconUnifiedHandler) GetUnifiedBeacons(c *gin.Context) {
	lat := utils.GetQueryFloat(c, "lat", 0)
	long := utils.GetQueryFloat(c, "long", 0)
	radius := utils.GetQueryFloat(c, "radius", 16000)

	if lat == 0 || long == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat and long are required"})
		return
	}

	userID, _ := c.Get("user_id")
	userIDStr := ""
	if userID != nil {
		userIDStr = userID.(string)
	}

	results, err := h.repo.GetNearbyAlerts(c.Request.Context(), lat, long, int(radius), userIDStr)
	if err != nil {
		log.Error().Err(err).Msg("unified beacons: query failed")
		c.JSON(http.StatusOK, gin.H{"beacons": []gin.H{}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"beacons": results})
}
