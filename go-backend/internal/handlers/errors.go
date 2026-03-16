// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"github.com/gin-gonic/gin"
)

// RespondError sends a standardized error response.
func RespondError(c *gin.Context, status int, code string, message string) {
	requestID, _ := c.Get("request_id")
	c.JSON(status, gin.H{
		"error":      message,
		"code":       code,
		"request_id": requestID,
	})
}

// RespondValidationError sends a 400 with field-level validation errors.
func RespondValidationError(c *gin.Context, errors map[string]string) {
	requestID, _ := c.Get("request_id")
	c.JSON(400, gin.H{
		"error":      "Validation failed",
		"code":       "validation.failed",
		"request_id": requestID,
		"details":    errors,
	})
}
