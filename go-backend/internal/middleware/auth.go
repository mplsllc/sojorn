// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

func ParseToken(tokenString string, jwtSecret string) (string, jwt.MapClaims, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(jwtSecret), nil
	})

	if err != nil || !token.Valid {
		return "", nil, fmt.Errorf("invalid token: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", nil, fmt.Errorf("invalid token claims")
	}

	userID, ok := claims["sub"].(string)
	if !ok {
		return "", nil, fmt.Errorf("token missing user ID")
	}

	return userID, claims, nil
}

func AuthMiddleware(jwtSecret string, pool ...*pgxpool.Pool) gin.HandlerFunc {
	var dbPool *pgxpool.Pool
	if len(pool) > 0 {
		dbPool = pool[0]
	}

	return func(c *gin.Context) {
		var tokenString string

		// Try Authorization header first (used by Flutter app and API clients)
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || parts[0] != "Bearer" {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header must be Bearer token"})
				c.Abort()
				return
			}
			tokenString = parts[1]
		} else {
			// Fallback: read from HttpOnly cookie (used by admin panel)
			cookie, err := c.Cookie("admin_token")
			if err != nil || cookie == "" {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
				c.Abort()
				return
			}
			tokenString = cookie
		}

		userID, claims, err := ParseToken(tokenString, jwtSecret)
		if err != nil {
			log.Error().Err(err).Msg("Invalid token")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			c.Abort()
			return
		}

		// Check ban/suspend status from DB (immediate enforcement)
		if dbPool != nil {
			var status string
			var suspendedUntil *time.Time
			err := dbPool.QueryRow(context.Background(),
				`SELECT status, suspended_until FROM users WHERE id = $1::uuid`, userID,
			).Scan(&status, &suspendedUntil)
			if err == nil {
				if status == "banned" {
					c.JSON(http.StatusForbidden, gin.H{"error": "This account has been permanently suspended.", "code": "banned"})
					c.Abort()
					return
				}
				if status == "suspended" {
					if suspendedUntil != nil && time.Now().After(*suspendedUntil) {
						// Suspension expired — reactivate and restore jailed content
						dbPool.Exec(context.Background(),
							`UPDATE users SET status = 'active', suspended_until = NULL WHERE id = $1::uuid`, userID)
						dbPool.Exec(context.Background(),
							`UPDATE posts SET status = 'active' WHERE author_id = $1::uuid AND status = 'jailed'`, userID)
						dbPool.Exec(context.Background(),
							`UPDATE comments SET status = 'active' WHERE author_id = $1::uuid AND status = 'jailed'`, userID)
					} else {
						c.JSON(http.StatusForbidden, gin.H{"error": "Your account is temporarily suspended.", "code": "suspended"})
						c.Abort()
						return
					}
				}
			}
		}

		// Store user ID and claims in context
		c.Set("user_id", userID)
		c.Set("claims", claims)

		c.Next()
	}
}
