// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// allowedOrigins is the whitelist of origins permitted to send credentialed requests.
var allowedOrigins = map[string]bool{
	"https://admin.sojorn.net": true,
	"https://sojorn.net":       true,
	"https://www.sojorn.net":   true,
	"https://api.sojorn.net":   true,
	"http://localhost:3000":     true, // Next.js admin dev
	"http://localhost:3002":     true, // Next.js admin dev (alt port)
	"http://localhost:8080":     true, // Go backend dev
}

// CORS returns a middleware that handles Cross-Origin Resource Sharing (CORS)
func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		if origin != "" && allowedOrigins[origin] {
			// Trusted origin: allow credentials (cookies)
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		} else if origin != "" {
			// Untrusted origin: allow requests but NOT credentials
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
		} else {
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		}

		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With, X-Signature, X-Timestamp, X-Request-ID, X-Rate-Limit-Remaining, X-Rate-Limit-Reset")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")
		c.Writer.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
