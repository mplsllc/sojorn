# Sojorn Extension Development Guide

This guide explains how to build a new extension for Sojorn. Extensions are the primary way to add toggleable features that instance administrators can enable or disable at runtime from the admin panel.

## Architecture Overview

Sojorn's feature set is modular. Core functionality (auth, posts, feeds, profiles) lives in the main router, but optional features -- beacons, groups, capsules, chat, events, discover, reposts, audio, official accounts, and moderation -- are implemented as extensions.

### How It Works

1. **Extensions are compiled into the binary.** There is no plugin system or dynamic loading. Every extension ships with the server.
2. **A Registry manages all extensions.** At startup, `main.go` creates a `Registry`, registers each extension, and calls `InitAll` to wire them up.
3. **Enabled state lives in the database.** The `instance_extensions` table stores whether each extension is on or off. The registry loads this state at startup.
4. **Runtime toggling via middleware.** Routes are always registered, but each extension group is wrapped with `RequireEnabled` middleware. When an extension is disabled, its routes return `404 {"error": "feature not available on this instance"}` without touching any business logic.
5. **Admin panel controls.** Administrators toggle extensions via `PUT /api/v1/admin/extensions/:id`. The registry validates dependency constraints (you cannot disable an extension that another enabled extension depends on) and updates the database.

### The Registry

The `Registry` (defined in `internal/extension/registry.go`) provides:

- `Register(ext)` -- add an extension at startup
- `LoadEnabledState(ctx)` -- read `instance_extensions` from the DB and sync the enabled map
- `IsEnabled(id)` -- check if an extension is on (used by middleware)
- `SetEnabled(ctx, id, enabled)` -- toggle with dependency validation
- `InitAll(ctx, deps, authorized, admin)` -- initialize all extensions, register routes, and start background jobs for enabled ones
- `All()` -- return metadata for every extension (used by the admin panel)

---

## The Extension Interface

Every extension implements this interface from `internal/extension/extension.go`:

```go
type Extension interface {
    ID() string
    Name() string
    Description() string
    Dependencies() []string
    Init(ctx context.Context, deps *Deps) error
    RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup)
    BackgroundJobs(ctx context.Context)
}
```

### Method Reference

| Method | Purpose |
|--------|---------|
| `ID()` | Returns a unique slug (e.g., `"beacons"`, `"chat"`). Used as the database key and in dependency declarations. |
| `Name()` | Human-readable name displayed in the admin panel (e.g., `"Community Beacons"`). |
| `Description()` | One-line description for the admin panel (e.g., `"Safety alerts and crowd-verified reports"`). |
| `Dependencies()` | Returns IDs of extensions this one requires. Return `nil` for no dependencies. The registry prevents enabling an extension whose dependencies are disabled, and prevents disabling an extension that others depend on. |
| `Init(ctx, deps)` | Called once at startup. Use this to create handlers, repositories, and any internal state using the shared `Deps`. |
| `RegisterRoutes(authorized, admin)` | Mount HTTP routes on the authorized (user-facing) and admin router groups. Always wrap route groups with `RequireEnabled` middleware. |
| `BackgroundJobs(ctx)` | Start long-running goroutines. The context is cancelled on server shutdown. Only called for extensions that are enabled at startup. |

---

## Deps Reference

The `Deps` struct (defined in `internal/extension/deps.go`) provides shared dependencies so extensions do not need 15+ constructor parameters:

| Field | Type | Purpose |
|-------|------|---------|
| `DB` | `*pgxpool.Pool` | PostgreSQL connection pool for queries and transactions |
| `Config` | `*config.Config` | Server configuration (env vars, feature flags, secrets) |
| `Hub` | `*realtime.Hub` | WebSocket hub for broadcasting real-time events to connected clients |
| `S3Client` | `*s3.Client` | S3-compatible client for R2/media storage (may be nil if not configured) |
| `AssetService` | `*services.AssetService` | URL signing and CDN domain resolution for media assets |
| `NotificationService` | `*services.NotificationService` | Create and deliver in-app notifications |
| `ModerationService` | `*services.ModerationService` | Content moderation database operations (flags, strikes, bans) |
| `ContentFilter` | `*services.ContentFilter` | Hard blocklist and strike system for prohibited content |
| `ContentModerator` | `*services.ContentModerator` | Multi-stage moderation cascade (local AI, SightEngine, fail-open) |
| `FeedService` | `*services.FeedService` | Feed assembly, pagination, and algorithmic ranking |
| `PushService` | `*services.PushService` | Firebase push notifications (may be nil if not configured) |
| `EmailService` | `*services.EmailService` | Transactional email sending via SMTP |
| `LocalAIService` | `*services.LocalAIService` | On-server AI gateway (Ollama) for text analysis (may be nil) |
| `LinkPreviewService` | `*services.LinkPreviewService` | Fetch and cache Open Graph metadata for URLs |
| `SightEngineService` | `*services.SightEngineService` | Third-party image/video moderation API (may be nil) |

Services marked "may be nil" depend on optional configuration. Check for nil before using them.

---

## Step-by-Step: Creating a New Extension

This walkthrough creates a hypothetical "Polls" extension.

### 1. Create the package

```
go-backend/internal/extensions/polls/
    polls.go
```

### 2. Implement the Extension interface

```go
// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

package polls

import (
    "context"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/rs/zerolog/log"
    "gitlab.com/patrickbritton3/sojorn/go-backend/internal/extension"
)

// Ext implements extension.Extension for the Polls feature.
type Ext struct {
    registry *extension.Registry
    db       *pgxpool.Pool
}

// New creates a new Polls extension. The registry reference is needed for
// the RequireEnabled middleware.
func New(registry *extension.Registry) *Ext {
    return &Ext{registry: registry}
}

func (e *Ext) ID() string            { return "polls" }
func (e *Ext) Name() string          { return "Polls" }
func (e *Ext) Description() string   { return "Create and vote on community polls" }
func (e *Ext) Dependencies() []string { return nil } // or []string{"groups"} if it depends on groups

func (e *Ext) Init(_ context.Context, deps *extension.Deps) error {
    e.db = deps.DB
    // Initialize your handlers, repositories, and services here.
    // Example:
    //   e.handler = NewPollHandler(deps.DB, deps.NotificationService)
    return nil
}

func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
    // --- User-facing routes ---
    polls := authorized.Group("/polls")
    polls.Use(extension.RequireEnabled(e.registry, e.ID()))
    {
        polls.GET("", e.listPolls)
        polls.POST("", e.createPoll)
        polls.GET("/:id", e.getPoll)
        polls.POST("/:id/vote", e.vote)
        polls.DELETE("/:id", e.deletePoll)
    }

    // --- Admin routes ---
    adminPolls := admin.Group("/polls")
    adminPolls.Use(extension.RequireEnabled(e.registry, e.ID()))
    {
        adminPolls.GET("", e.adminListPolls)
        adminPolls.DELETE("/:id", e.adminDeletePoll)
    }
}

func (e *Ext) BackgroundJobs(ctx context.Context) {
    // Close expired polls every 5 minutes.
    go func() {
        ticker := time.NewTicker(5 * time.Minute)
        defer ticker.Stop()
        for {
            select {
            case <-ctx.Done():
                log.Info().Msg("[Polls] Background job stopped")
                return
            case <-ticker.C:
                if err := e.closeExpiredPolls(context.Background()); err != nil {
                    log.Error().Err(err).Msg("[Polls] Failed to close expired polls")
                }
            }
        }
    }()
}

// Handler methods (stubs for the template)
func (e *Ext) listPolls(c *gin.Context)      { /* ... */ }
func (e *Ext) createPoll(c *gin.Context)     { /* ... */ }
func (e *Ext) getPoll(c *gin.Context)        { /* ... */ }
func (e *Ext) vote(c *gin.Context)           { /* ... */ }
func (e *Ext) deletePoll(c *gin.Context)     { /* ... */ }
func (e *Ext) adminListPolls(c *gin.Context) { /* ... */ }
func (e *Ext) adminDeletePoll(c *gin.Context){ /* ... */ }
func (e *Ext) closeExpiredPolls(_ context.Context) error { return nil }
```

### 3. Register in main.go

Open `go-backend/cmd/api/main.go` and add:

```go
import ext_polls "gitlab.com/patrickbritton3/sojorn/go-backend/internal/extensions/polls"
```

Then in the extension registration block:

```go
extRegistry.Register(ext_polls.New(extRegistry))
```

### 4. Create the database migration

Add a migration file in `go-backend/migrations/` (e.g., `000042_create_polls.up.sql`) with your tables. Migrations run automatically on startup.

### 5. Done

Start the server. Your extension appears in the admin panel under Extensions, defaulting to disabled. Toggle it on to activate the routes and background jobs.

---

## Route Registration Patterns

### Sub-group with RequireEnabled (recommended)

Wrap an entire route group so all routes in the extension are gated by a single middleware instance:

```go
func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
    g := authorized.Group("/polls")
    g.Use(extension.RequireEnabled(e.registry, e.ID()))
    {
        g.GET("", e.list)
        g.POST("", e.create)
    }
}
```

This is the standard pattern used by all existing extensions. When the extension is disabled, every route in the group returns 404.

### Per-route middleware (rare)

If you need some routes to be available even when the extension is disabled (e.g., a read-only fallback), apply the middleware to individual routes:

```go
func (e *Ext) RegisterRoutes(authorized *gin.RouterGroup, admin *gin.RouterGroup) {
    g := authorized.Group("/polls")
    g.GET("/info", e.info) // always available
    g.POST("", extension.RequireEnabled(e.registry, e.ID()), e.create) // only when enabled
}
```

---

## Background Job Patterns

### Ticker-based periodic work

Most background jobs follow the ticker pattern with context cancellation for graceful shutdown:

```go
func (e *Ext) BackgroundJobs(ctx context.Context) {
    go func() {
        ticker := time.NewTicker(15 * time.Minute)
        defer ticker.Stop()
        for {
            select {
            case <-ctx.Done():
                return
            case <-ticker.C:
                e.doWork(context.Background())
            }
        }
    }()
}
```

### Key points

- **Always listen on `ctx.Done()`.** The context is cancelled when the server receives SIGTERM. Your goroutine must exit promptly to avoid delaying shutdown.
- **Use `context.Background()` for the actual work.** The background context from `BackgroundJobs` is a cancellation signal, not a request context. Create a fresh context (with an optional timeout) for each unit of work.
- **Log errors but do not crash.** Background jobs should log errors and continue on the next tick. Use `log.Error()` from zerolog.
- **Only enabled extensions get BackgroundJobs called.** The registry skips `BackgroundJobs` for disabled extensions at startup. If an extension is toggled off at runtime, the background goroutine keeps running but should check `registry.IsEnabled()` before doing expensive work if needed.

### Multiple goroutines

If your extension needs multiple independent background tasks, start multiple goroutines:

```go
func (e *Ext) BackgroundJobs(ctx context.Context) {
    go e.syncExternalData(ctx)
    go e.cleanupExpired(ctx)
    go e.sendDigestEmails(ctx)
}
```

---

## Testing Extensions

### Unit testing handlers

Test your handlers in isolation by constructing the `Ext` struct with a test database pool:

```go
func TestCreatePoll(t *testing.T) {
    db := setupTestDB(t) // your test helper that returns a *pgxpool.Pool
    ext := &Ext{db: db}

    router := gin.New()
    router.POST("/polls", ext.createPoll)

    req := httptest.NewRequest("POST", "/polls", strings.NewReader(`{"question":"Favorite color?"}`))
    req.Header.Set("Content-Type", "application/json")
    w := httptest.NewRecorder()
    router.ServeHTTP(w, req)

    assert.Equal(t, 200, w.Code)
}
```

### Testing the RequireEnabled middleware

Verify that routes return 404 when the extension is disabled:

```go
func TestPollsDisabled(t *testing.T) {
    db := setupTestDB(t)
    registry := extension.NewRegistry(db)
    ext := New(registry)
    ext.Init(context.Background(), &extension.Deps{DB: db})

    router := gin.New()
    authorized := router.Group("/api/v1")
    admin := router.Group("/api/v1/admin")
    ext.RegisterRoutes(authorized, admin)

    req := httptest.NewRequest("GET", "/api/v1/polls", nil)
    w := httptest.NewRecorder()
    router.ServeHTTP(w, req)

    assert.Equal(t, 404, w.Code)
}
```

### Integration tests

Run the full test suite from the repository root:

```bash
cd go-backend && go test ./...
```

---

## Registering in main.go -- Checklist

When your extension is ready to merge:

1. Add the import in `cmd/api/main.go`:
   ```go
   ext_polls "gitlab.com/patrickbritton3/sojorn/go-backend/internal/extensions/polls"
   ```

2. Register it after the existing extensions:
   ```go
   extRegistry.Register(ext_polls.New(extRegistry))
   ```

3. Add a database migration for any new tables.

4. Update the Extensions table in `DEPLOYMENT.md` with your extension's name and description.

5. The extension will appear in the admin panel automatically. It defaults to disabled until an admin enables it.
