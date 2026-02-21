// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// AdminMiddleware checks that the authenticated user has role = 'admin' in profiles.
// Must be placed AFTER AuthMiddleware so that "user_id" is already in context.
func AdminMiddleware(pool *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID, exists := c.Get("user_id")
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
			c.Abort()
			return
		}

		var role string
		err := pool.QueryRow(c.Request.Context(),
			`SELECT COALESCE(role, 'user') FROM public.profiles WHERE id = $1::uuid`, userID).Scan(&role)
		if err != nil {
			log.Error().Err(err).Str("user_id", userID.(string)).Msg("Failed to check admin role")
			c.JSON(http.StatusForbidden, gin.H{"error": "Access denied"})
			c.Abort()
			return
		}

		if role != "admin" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Admin access required"})
			c.Abort()
			return
		}

		c.Set("is_admin", true)
		c.Next()
	}
}
