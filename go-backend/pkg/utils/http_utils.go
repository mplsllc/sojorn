// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package utils

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

// GetQueryInt parses an integer from query parameters with a default value
func GetQueryInt(c *gin.Context, key string, defaultValue int) int {
	valStr := c.Query(key)
	if valStr == "" {
		return defaultValue
	}
	val, err := strconv.Atoi(valStr)
	if err != nil {
		return defaultValue
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
