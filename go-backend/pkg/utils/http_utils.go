// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package utils

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

// GetQueryInt parses an integer from query parameters with a default value.
// Negative values are clamped to 0; limit/offset values are capped at 500
// to prevent unbounded pagination DoS.
func GetQueryInt(c *gin.Context, key string, defaultValue int) int {
	valStr := c.Query(key)
	if valStr == "" {
		return defaultValue
	}
	val, err := strconv.Atoi(valStr)
	if err != nil {
		return defaultValue
	}
	if val < 0 {
		return 0
	}
	// Cap pagination parameters to prevent abuse
	if (key == "limit" || key == "offset" || key == "page_size") && val > 500 {
		return 500
	}
	return val
}

// GetQueryFloat parses a float64 from query parameters with a default value
func GetQueryFloat(c *gin.Context, key string, defaultValue float64) float64 {
	valStr := c.Query(key)
	if valStr == "" {
		return defaultValue
	}
	val, err := strconv.ParseFloat(valStr, 64)
	if err != nil {
		return defaultValue
	}
	return val
}
