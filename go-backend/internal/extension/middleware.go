// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package extension

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// RequireEnabled returns middleware that blocks requests when an extension
// is disabled. This allows runtime toggling without a server restart.
func RequireEnabled(reg *Registry, extID string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !reg.IsEnabled(extID) {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "feature not available on this instance",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}
