// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
)

// internalError logs the real error server-side and returns a generic message to the client.
// The msg parameter is returned directly to the client — it must be a human-readable string
// we authored, never anything derived from err.
func internalError(c *gin.Context, msg string, err error) {
	log.Error().Err(err).Str("path", c.Request.URL.Path).Msg(msg)
	c.JSON(http.StatusInternalServerError, gin.H{"error": msg})
}
