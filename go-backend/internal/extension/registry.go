// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package extension

import (
	"context"
	"fmt"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// Registry manages all compiled-in extensions and their enabled state.
type Registry struct {
	mu         sync.RWMutex
	extensions map[string]Extension
	order      []string
	enabled    map[string]bool
	db         *pgxpool.Pool
}

// NewRegistry creates a registry backed by the given database pool.
func NewRegistry(db *pgxpool.Pool) *Registry {
	return &Registry{
		extensions: make(map[string]Extension),
		enabled:    make(map[string]bool),
		db:         db,
	}
}

// Register adds an extension to the registry. Called at startup before Init.
func (r *Registry) Register(ext Extension) {
	r.mu.Lock()
	defer r.mu.Unlock()
	id := ext.ID()
	if _, exists := r.extensions[id]; exists {
		log.Warn().Str("extension", id).Msg("Extension already registered, skipping")
		return
	}
	r.extensions[id] = ext
	r.order = append(r.order, id)
}

// LoadEnabledState reads the instance_extensions table and populates the
// enabled map. Extensions not in the DB are inserted as disabled.
func (r *Registry) LoadEnabledState(ctx context.Context) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Ensure every registered extension has a row in the DB.
	for _, id := range r.order {
		ext := r.extensions[id]
		_, err := r.db.Exec(ctx, `
			INSERT INTO instance_extensions (id, name, description)
			VALUES ($1, $2, $3)
			ON CONFLICT (id) DO UPDATE SET name = $2, description = $3`,
			id, ext.Name(), ext.Description())
		if err != nil {
			return fmt.Errorf("upsert extension %s: %w", id, err)
		}
	}

	rows, err := r.db.Query(ctx, `SELECT id, enabled FROM instance_extensions`)
	if err != nil {
		return fmt.Errorf("load extensions: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id string
		var enabled bool
		if err := rows.Scan(&id, &enabled); err != nil {
			return err
		}
		r.enabled[id] = enabled
	}
	return rows.Err()
}

// IsEnabled returns whether the given extension is currently enabled.
func (r *Registry) IsEnabled(id string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.enabled[id]
}

// SetEnabled toggles an extension on or off, validating dependencies.
func (r *Registry) SetEnabled(ctx context.Context, id string, enabled bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	ext, exists := r.extensions[id]
	if !exists {
		return fmt.Errorf("unknown extension: %s", id)
	}

	if enabled {
		// Check that all dependencies are enabled.
		for _, dep := range ext.Dependencies() {
			if !r.enabled[dep] {
				return fmt.Errorf("cannot enable %s: dependency %s is disabled", id, dep)
			}
		}
	} else {
		// Check that no enabled extension depends on this one.
		for _, otherID := range r.order {
			if otherID == id {
				continue
			}
			other := r.extensions[otherID]
			if !r.enabled[otherID] {
				continue
			}
			for _, dep := range other.Dependencies() {
				if dep == id {
					return fmt.Errorf("cannot disable %s: %s depends on it", id, otherID)
				}
			}
		}
	}

	tag := "enabled_at"
	if !enabled {
		tag = "disabled_at"
	}
	_, err := r.db.Exec(ctx, fmt.Sprintf(
		`UPDATE instance_extensions SET enabled = $1, %s = NOW() WHERE id = $2`, tag),
		enabled, id)
	if err != nil {
		return err
	}

	r.enabled[id] = enabled
	log.Info().Str("extension", id).Bool("enabled", enabled).Msg("Extension toggled")
	return nil
}

// All returns info for every registered extension.
func (r *Registry) All() []Info {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]Info, 0, len(r.order))
	for _, id := range r.order {
		ext := r.extensions[id]
		deps := ext.Dependencies()
		if deps == nil {
			deps = []string{}
		}
		result = append(result, Info{
			ID:           id,
			Name:         ext.Name(),
			Description:  ext.Description(),
			Dependencies: deps,
			Enabled:      r.enabled[id],
		})
	}
	return result
}

// EnabledMap returns a map of extension ID → enabled for the instance endpoint.
func (r *Registry) EnabledMap() map[string]bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	m := make(map[string]bool, len(r.order))
	for _, id := range r.order {
		m[id] = r.enabled[id]
	}
	return m
}

// InitAll initializes every extension and registers routes + background jobs
// for enabled ones.
func (r *Registry) InitAll(ctx context.Context, deps *Deps, authorized *gin.RouterGroup, admin *gin.RouterGroup) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for _, id := range r.order {
		ext := r.extensions[id]
		if err := ext.Init(ctx, deps); err != nil {
			log.Warn().Err(err).Str("extension", id).Msg("Extension init failed")
			continue
		}
		// Always register routes (middleware handles enabled check at request time).
		ext.RegisterRoutes(authorized, admin)
		// Only start background jobs for enabled extensions.
		if r.enabled[id] {
			ext.BackgroundJobs(ctx)
			log.Info().Str("extension", id).Msg("Extension started")
		} else {
			log.Info().Str("extension", id).Msg("Extension registered (disabled)")
		}
	}
	return nil
}
