// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package extension

import (
	"context"

	"github.com/gin-gonic/gin"
)

// Extension is the contract every toggleable feature implements.
// Extensions are compiled into the binary and registered at startup.
// They can be enabled/disabled at runtime from the admin panel.
type Extension interface {
	// ID returns a unique slug: "quips", "beacons", "groups", etc.
	ID() string
	// Name returns a human-readable name for admin display.
	Name() string
	// Description returns a one-liner for the admin panel.
	Description() string
	// Dependencies returns IDs of extensions this one requires.
	Dependencies() []string
	// Init is called once at startup with shared dependencies.
	Init(ctx context.Context, deps *Deps) error
	// RegisterRoutes mounts routes on the authorized and admin groups.
	// Extensions should wrap their groups with RequireEnabled middleware.
	RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup)
	// BackgroundJobs starts long-running goroutines. Context is cancelled on shutdown.
	BackgroundJobs(ctx context.Context)
}

// Info holds metadata about a registered extension and its current state.
type Info struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Description  string   `json:"description"`
	Dependencies []string `json:"dependencies"`
	Enabled      bool     `json:"enabled"`
}
