// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// RequestLogger logs incoming HTTP requests using zerolog structured fields.
//
// Log-level strategy (based on the global zerolog level):
//
//	Debug  → log every request
//	Info   → log only status >= 400
//	Warn+  → log only status >= 500
//
// Health-check paths (/health, /health/live, /health/ready) are always skipped
// to avoid noisy output from load-balancer probes.
func RequestLogger() gin.HandlerFunc {
	skipPaths := map[string]struct{}{
		"/health":       {},
		"/health/live":  {},
		"/health/ready": {},
	}

	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		// Skip health-check endpoints unconditionally.
		if _, skip := skipPaths[c.Request.URL.Path]; skip {
			return
		}

		status := c.Writer.Status()
		globalLevel := zerolog.GlobalLevel()

		// Apply log-level filtering strategy.
		switch {
		case globalLevel >= zerolog.WarnLevel && status < 500:
			return
		case globalLevel >= zerolog.InfoLevel && status < 400:
			return
		}

		latency := time.Since(start)
		requestID, _ := c.Get("request_id")

		event := log.Info()
		if status >= 500 {
			event = log.Error()
		} else if status >= 400 {
			event = log.Warn()
		}

		event.
			Str("method", c.Request.Method).
			Str("path", c.Request.URL.Path).
			Int("status", status).
			Float64("latency_ms", float64(latency.Nanoseconds())/1e6).
			Str("client_ip", c.ClientIP()).
			Interface("request_id", requestID).
			Msg("request")
	}
}
