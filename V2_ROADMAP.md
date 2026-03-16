# Sojorn v2: Beta-Ready Release Plan

## Context
Sojorn has the extension system, self-hosting infra, and feature set done. But to be credible as a beta release (Mastodon-level), it needs the operational maturity layer: security hardening, admin tooling, testing, CI, docs, and polish.

## Current Scorecard

| Area | Now | Target | Gap |
|---|---|---|---|
| Startup validation | 7/10 | 10/10 | JWT_SECRET not validated |
| Health endpoints | 9/10 | 9/10 | Done |
| Test coverage | 2/10 | 6/10 | 4 test files, <2% coverage |
| Error handling | 5/10 | 8/10 | No standard format |
| Rate limiting | 4/10 | 8/10 | Only 2 endpoints protected |
| Security headers | 4/10 | 9/10 | Missing HSTS, CSP, X-Frame |
| Migration tracking | 3/10 | 8/10 | Re-runs everything, no tracking |
| Admin CLI | 3/10 | 7/10 | No create-admin, no reset-password |
| CONTRIBUTING.md | 0/10 | 8/10 | Missing |
| CI/CD | 0/10 | 7/10 | No Forgejo Actions |
| API docs | 0/10 | 6/10 | No OpenAPI |
| First-run UX | 5/10 | 9/10 | Manual SQL for admin |
| Graceful shutdown | 6/10 | 9/10 | No structured shutdown logging or drain |
| Deployment docs | 4/10 | 8/10 | Missing CLI refs, migration recovery, log config |
| Invite/registration control | 3/10 | 8/10 | Config exists but not enforced in backend |
| Federation readiness | 0/10 | 4/10 | No ActivityPub; target: read-only actor/outbox |
| Post editing | 0/10 | 7/10 | No edit support; users expect this now |
| Version introspection | 0/10 | 8/10 | No git SHA / build date exposed |

---

## Phase 1: Security & Startup (quick wins)

### 1.1 Startup validation + log level strategy + graceful shutdown
**File:** `go-backend/cmd/api/main.go`
- Wire zerolog global level from `cfg.LogLevel` early (before any other logs)
  — parse string to zerolog.Level: "debug"→DebugLevel, "info"→InfoLevel, etc.
  — request logger middleware inherits this automatically
- Fatal if JWT_SECRET is empty or < 32 characters (minimum entropy check)
- Warn if SMTP not configured ("email features disabled")
- Warn if R2 not configured ("media uploads disabled")
- Warn if CORS_ORIGINS is `*` in production mode
- Log a startup summary: instance name, env, log level, enabled extensions, configured services
- Structured shutdown: on SIGTERM/SIGINT, log "shutting down gracefully...",
  drain in-flight HTTP requests (srv.Shutdown with 10s timeout already exists),
  log "shutdown complete" with uptime duration

### 1.2 Security headers middleware
**File:** `go-backend/internal/middleware/security.go` (new)
- `Strict-Transport-Security: max-age=63072000; includeSubDomains` (production only)
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- Accept `isProduction bool` parameter — skip HSTS in dev
- Wire into main.go after CORS middleware

### 1.3 Rate limiting (auth + global)
**File:** `go-backend/cmd/api/main.go`
Auth endpoints (tight):
- `POST /auth/register` → 0.5 RPS, burst 3
- `POST /auth/login` → 1 RPS, burst 5
- `POST /auth/forgot-password` → 0.2 RPS, burst 2
- `POST /auth/resend-verification` → 0.2 RPS, burst 2

Global per-IP rate limit (loose, anti-scraping):
- Apply to all `/api/v1/*` routes: 30 RPS, burst 60 per IP
- Feed, search, and user lookup are common scraping targets — this catches bulk enumeration
  without affecting normal usage
- Wire as early middleware (before auth) so unauthenticated scrapers get caught

### 1.4 Structured version endpoint
**File:** `go-backend/cmd/api/main.go` + build flags
- `GET /api/v1/version` → `{"version": "1.0.0", "commit": "abc123f", "built_at": "2026-03-16T..."}`
- Inject git SHA and build timestamp via `-ldflags` at compile time:
  `go build -ldflags="-X main.gitCommit=$(git rev-parse --short HEAD) -X main.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)"`
- Update Dockerfile to pass ldflags
- Makes debugging self-hoster issues dramatically easier ("what version are you running?")

---

## Phase 2: Admin CLI & First-Run

### 2.1 Admin CLI tool
**File:** `go-backend/cmd/admin/main.go` (new)
Subcommands via flag parsing (no cobra — keep lightweight):
- `create-admin --handle X --email X --password X`
  — creates user + profile + sets role=admin
  — **password validation**: minimum 8 chars, reject common passwords (top-100 list)
  — logs success with the handle created
- `reset-password --handle X --password X`
  — same password validation rules
  — resets bcrypt hash directly in DB
  — **handle not found**: return same success message as found (don't leak handle existence)
- `list-extensions` — shows all extensions and their enabled state
- `toggle-extension --id X --enable/--disable` — toggle extension
- `validate-config`
  — checks .env for required fields (DATABASE_URL, JWT_SECRET)
  — validates JWT_SECRET entropy (>= 32 chars)
  — tests DB connection
  — checks optional services (SMTP reachable? R2 endpoint responds?)

Build in Dockerfile alongside api and migrate binaries.

### 2.2 First-run setup flow
**File:** `go-backend/cmd/api/main.go`
- On startup, query `SELECT count(*) FROM profiles WHERE role = 'admin'`
- If 0, log a prominent boxed message:
  ```
  ┌─────────────────────────────────────────────────────────────┐
  │  No admin account found.                                    │
  │  Run: ./admin create-admin --handle yourname \              │
  │       --email you@example.com --password yourpass            │
  └─────────────────────────────────────────────────────────────┘
  ```
- Update DEPLOYMENT.md and README to reference CLI instead of raw SQL

### 2.3 Migration tracking
**File:** `go-backend/cmd/migrate/main.go`
- Create `schema_migrations` table on first run: `(version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ)`
- Before each migration, check if version exists in table
- Run each migration inside a transaction (BEGIN/COMMIT) so partial failures roll back cleanly
  — if a migration fails mid-way, the version is NOT inserted and the transaction is rolled back
  — log the error clearly with the filename so the operator knows which migration failed
- After successful apply, INSERT version + timestamp (inside same transaction)
- Skip already-applied migrations
- Log summary: "3 migrations applied, 2 already up-to-date"
- Document in DEPLOYMENT.md: "If a migration fails partially, fix the SQL issue and re-run migrate"

---

## Phase 3: Error Handling & Observability

### 3.1 Standard error response format
**File:** `go-backend/internal/handlers/errors.go` (new)
```go
type APIError struct {
    Error     string `json:"error"`
    Code      string `json:"code,omitempty"`      // e.g. "auth.invalid_token"
    RequestID string `json:"request_id,omitempty"` // from X-Request-ID
    Details   any    `json:"details,omitempty"`    // validation errors, etc.
}
```
Helper functions: `RespondError(c, status, code, message)`, `RespondValidationError(c, errors)`

Adopt incrementally — new code uses helpers, existing handlers get a grep-able marker:
`// TODO(errors): migrate to RespondError`
Track conversion progress: `grep -r "TODO(errors)" --include="*.go" | wc -l`

### 3.2 Request ID middleware
**File:** `go-backend/internal/middleware/request_id.go` (new)
- Accept incoming `X-Request-ID` header, or generate UUID if absent
- Set as response header `X-Request-ID`
- Store in gin context key `"request_id"`
- Inject into zerolog sub-logger on the context so all handler logs include it
- RespondError automatically pulls request_id from context

### 3.3 Request logging middleware
**File:** `go-backend/internal/middleware/logger.go` (new)
- Log: method, path, status code, latency (ms), request ID, client IP
- Skip `/health`, `/health/live`, `/health/ready` to avoid noise
- Log level strategy:
  — DEBUG: log all requests (useful for dev)
  — INFO: log only 4xx/5xx responses (prod default — keeps logs clean)
  — WARN/ERROR: only log 5xx
- Use zerolog structured fields — no printf

---

## Phase 4: Testing & CI

### 4.1 Integration test framework
**File:** `go-backend/internal/testing/` (extend existing)
- Test database setup/teardown using `testing.M` and a test-specific DB
- JWT token generation helper for authenticated test requests
- Standard fixtures: createTestUser(), createTestPost(), createTestGroup()
- httptest.NewRecorder + gin test router pattern

### 4.2 Critical path tests (~15 tests)
Budget: 90 min (framework setup bleeds into test writing)
- Auth: register, login, refresh token, invalid credentials (4 tests)
- Posts: create, get, delete, feed (4 tests)
- Extensions: enable/disable, RequireEnabled blocks when disabled (2 tests)
- Instance: GET /api/v1/instance shape validation (1 test)
- Health: /health, /health/ready, /health/detailed (1 test)
- Middleware: security headers present (1 test)
- **Rate limit burst test**: real HTTP burst (fire N+1 requests, assert last gets 429) (1 test)
- Admin: admin-only middleware blocks non-admins (1 test)

### 4.3 CI pipeline (Forgejo Actions)
**File:** `.forgejo/workflows/ci.yml` (new)
Forgejo Actions — GitHub Actions-compatible syntax with minor differences.
- Trigger: push to `main`, `goSojorn`; pull_request to `main`
- Jobs:
  - **backend**: setup Go 1.24, `go vet ./...`, `go build ./...`, `go test ./...`
  - **admin**: setup Node 20, `cd admin && npm ci && npm run build`
  - **docker**: build Docker images with explicit `--target` per stage (builder, runtime)
    to catch broken COPY/missing binary in intermediate stages — a final-only build
    can silently pass if the failing step is in an earlier stage

Note: Check go.mod before writing CI YAML — if it has `toolchain go1.25.4` alongside
`go 1.24`, running `go test` on Go 1.24 can cause surprising toolchain download behavior.
Pin CI to the exact toolchain version from go.mod, or strip the toolchain directive.

---

## Phase 5: Documentation

### 5.1 CONTRIBUTING.md
**File:** `CONTRIBUTING.md` (new)
- Development setup (Go 1.24+, Node 20+, PostgreSQL 16+)
- Running locally without Docker (`go run cmd/api/main.go`)
- Running tests (`go test ./...`)
- Code style: `gofmt`, no additional linter config
- How to create a new extension (reference extensions.md)
- PR process: branch from goSojorn, describe changes, ensure CI green
- Bug reports: include instance version, extension state, steps to reproduce

### 5.2 API documentation
**File:** `go-backend/docs/api.md` (new)
- All public endpoints grouped by area (auth, posts, users, feed, etc.)
- Auth flow: register → verify email → login → refresh
- Standard error format with code reference
- Rate limits per endpoint
- Instance discovery: GET /api/v1/instance response schema
- Extension routes marked as toggleable (404 when disabled)
- WebSocket endpoint documentation
Not full OpenAPI — human-readable markdown reference.

### 5.3 Extension development guide
**File:** `go-backend/docs/extensions.md` (new)
- Architecture: Extension interface, Registry, RequireEnabled middleware
- Step-by-step: creating a new extension (with code template)
- Deps fields reference table
- Background job patterns (context cancellation, tickers)
- Route registration patterns (sub-group vs per-route middleware)
- Testing extensions

### 5.4 DEPLOYMENT.md update pass
**File:** `DEPLOYMENT.md` (existing — update)
- Replace raw SQL admin creation with `./admin create-admin` CLI
- Add migration failure recovery section ("If a migration fails partially...")
- Add shutdown/restart behavior notes
- Add rate limit documentation for operators
- Add log level configuration guidance (DEBUG vs INFO vs WARN)

---

## Phase 6: Launch Readiness

### 6.1 Invite-only registration mode
**File:** `go-backend/internal/handlers/auth_handler.go`
- Check `instance_config["registration_mode"]` on register endpoint
- If `"invite"`: require valid `invite_token` param, validate against `invite_tokens` table
- If `"closed"`: reject all registrations with clear message
- If `"open"` (default): current behavior
- Admin panel already has registration_mode in branding settings — just needs backend enforcement
- `invite_tokens` table: `(token TEXT PRIMARY KEY, created_by UUID, used_by UUID, used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ)`
- Admin CLI: `./admin create-invite` generates a single-use token
- Admin panel: section to generate/list/revoke invite links

### 6.2 Instance about page
**File:** `go-backend/internal/handlers/instance_handler.go`
- `GET /api/v1/instance/about` (public, unauthenticated) returning:
  - Instance name, description, rules (from instance_config)
  - Admin contact email
  - User count, post count, active users (last 30 days)
  - Version + commit SHA
  - Uptime
  - Enabled extensions list
- This is what other instance admins and potential users look at to evaluate trust
- Optional: render as HTML at `/about` for browser access (or leave to frontend)

### 6.3 Post editing with edit history
**Files:** `go-backend/internal/handlers/post_handler.go`, `go-backend/internal/models/post.go`
- `post_edits` table: `(id UUID, post_id UUID, content TEXT, edited_at TIMESTAMPTZ)`
- On `PATCH /posts/:id`, save current content to `post_edits` before applying update
- Add `edited_at TIMESTAMPTZ` to posts table (NULL = never edited)
- `GET /posts/:id/edits` returns edit history (public for public posts)
- Flutter/frontend shows "edited" indicator + expandable history

### 6.4 DM controls + searchability
**Files:** `go-backend/internal/models/settings.go`, privacy settings handler
- Add to `PrivacySettings`: `AllowDMsFrom string` (everyone / followers / nobody)
- Add to `PrivacySettings`: `SearchableByHandle bool`, `SearchableByEmail bool`
- Chat handler checks DM permission before allowing conversation creation
- Discover handler respects searchability settings in user search
- Migration: `ALTER TABLE profile_privacy_settings ADD COLUMN ...`

### 6.5 Accessibility notes
Not a backend task per se, but document requirements for frontend contributors:
- Add to CONTRIBUTING.md: accessibility expectations (keyboard nav, ARIA labels, contrast ratios)
- Add to admin panel: basic ARIA labels on interactive elements (forms, buttons, toggles)
- Flag as ongoing concern, not a one-time checkbox

---

## Phase 7: Federation Groundwork (read-only ActivityPub)

### 7.1 Actor objects
**File:** `go-backend/internal/handlers/activitypub_handler.go` (new)
- `GET /.well-known/webfinger?resource=acct:handle@domain` → returns actor URL
- `GET /users/:handle` with `Accept: application/activity+json` → returns Actor object:
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Person",
    "id": "https://instance.com/users/handle",
    "preferredUsername": "handle",
    "name": "Display Name",
    "summary": "Bio",
    "inbox": "https://instance.com/users/handle/inbox",
    "outbox": "https://instance.com/users/handle/outbox",
    "publicKey": { ... }
  }
  ```
- Content negotiation: if request `Accept` header is `application/activity+json`, serve AP;
  otherwise serve normal API response
- This alone makes Sojorn profiles discoverable from Mastodon

### 7.2 Outbox (read-only)
**File:** same handler
- `GET /users/:handle/outbox` → ordered collection of public posts as `Note` objects
- Paginated, most recent first
- Only public posts (respect visibility settings)
- No inbox processing yet — that's full federation (Phase 8+)

### 7.3 Data model considerations
- Ensure profiles have a stable URI (`https://instance.com/users/handle`)
- Add `ap_id TEXT` column to profiles for future remote actor references
- Add `ap_id TEXT` column to posts for future remote post references
- These columns are NULL for local content, populated for federated content later
- **Do this migration now** so the schema is ready when full federation comes

---

## Phase 8: SaaS / Managed Hosting Layer

> Separate codebase/repo for the orchestration layer. The Sojorn core stays open source (AGPL-3.0).
> SaaS layer is proprietary ops tooling that wraps the same docker-compose deployment.

### Business Model
- **Open core**: self-hosted always free, managed cloud paid
- **Tiers**: Solo (1 instance, limited extensions), Community (full extensions, custom domain), Organization (SLA, SSO, priority support)
- **Ghost model**: same codebase, hosted tier is just ops + convenience

### 8.1 Multi-tenancy: One instance per customer (Option A)
- Isolated DB + isolated container per customer — true data isolation
- Use Dokku or Coolify for lightweight instance orchestration
- Provisioning script: `create-instance --domain X --plan Y` → spins up containers, runs migrate, runs create-admin
- Target: under 2 minutes from payment to usable instance

### 8.2 Billing
- Stripe subscription with plan-based extension gating (maps directly to existing extension system)
- Customer portal for plan changes, invoices, cancellation
- Grace period + automatic data export on cancellation
- Webhook handler: `invoice.paid` → ensure instance running, `customer.subscription.deleted` → start grace period

### 8.3 Managed Onboarding
- Sign up → choose subdomain (`community.sojorn.com` or custom domain) → instance spins up → admin CLI auto-runs → welcome email
- Custom domain: CNAME instructions + automatic TLS via Caddy or Cloudflare

### 8.4 Customer Operations
- Centralized logging across all instances (log aggregation, not log sharing)
- Automated daily backups with per-customer restore
- Upgrade pipeline: new version → staged rollout → health check → proceed or rollback
- Public status page (uptime, incident history)

### 8.5 Positioning & Wedge
- **Primary**: privacy-first ("your community, your data, no ad networks")
- **Secondary**: federation-ready (ActivityPub differentiates from Circle/Mighty Networks)
- **Verticals**: local journalism orgs, activist/advocacy groups, creator fandoms, small DAOs
- **Against Discord/Slack**: ownership and portability ("export everything and self-host anytime")

### 8.6 Trust & Legal
- ToS and Privacy Policy covering customer data handling
- DPA (Data Processing Agreement) for EU customers — required for GDPR
- Clear data residency statement
- Security practices Trust page (SOC 2 is overkill at launch, but document what you do)

---

## Execution Order

| # | Task | Est. | Commit after? |
|---|---|---|---|
| 1 | Startup validation + log level + shutdown (1.1) | 20 min | Yes |
| 2 | Security headers (1.2) | 15 min | — |
| 3 | Rate limiting — auth + global (1.3) | 15 min | — |
| 4 | Version endpoint (1.4) | 15 min | Yes (with 2, 3) |
| 5 | Admin CLI (2.1) | 45 min | Yes |
| 6 | Migration tracking (2.3) | 30 min | — |
| 7 | First-run message (2.2) | 10 min | Yes (with 6) |
| 8 | Request ID + request logging (3.2, 3.3) | 30 min | — |
| 9 | Standard error helpers (3.1) | 20 min | Yes (with 8) |
| 10 | CI pipeline (4.3) | 20 min | Yes |
| 11 | Test framework + critical path tests (4.1, 4.2) | 90 min | Yes |
| 12 | CONTRIBUTING.md (5.1) | 30 min | — |
| 13 | API docs (5.2) | 45 min | — |
| 14 | Extension dev guide (5.3) | 30 min | — |
| 15 | DEPLOYMENT.md update (5.4) | 20 min | Yes (with 12, 13, 14) |
| 16 | Invite-only mode (6.1) | 30 min | Yes |
| 17 | Instance about page (6.2) | 20 min | — |
| 18 | Post editing + history (6.3) | 45 min | Yes (with 17) |
| 19 | DM controls + searchability (6.4) | 30 min | Yes |
| 20 | AP data model migration (7.3) | 10 min | — |
| 21 | WebFinger + Actor objects (7.1) | 45 min | — |
| 22 | Read-only Outbox (7.2) | 30 min | Yes (with 20, 21) |

**Phase 8 (SaaS) is post-Phase 7. Prerequisites: account deletion, data export, and invite mode all working.**

| # | Task | Est. | Commit after? |
|---|---|---|---|
| 23 | Instance provisioning script (8.1) | — | Separate repo |
| 24 | Stripe billing integration (8.2) | — | Separate repo |
| 25 | Managed onboarding flow (8.3) | — | Separate repo |

---

## Verification
- Server starts with no .env → fatal "JWT_SECRET is required"
- Server starts with JWT_SECRET=abc → fatal "JWT_SECRET must be at least 32 characters"
- Server starts with minimal .env → warns about missing SMTP/R2, prints startup summary with log level
- SIGTERM → logs "shutting down gracefully...", drains requests, logs "shutdown complete" with uptime
- `curl -I localhost:8080/health` → includes X-Content-Type-Options, X-Frame-Options, Referrer-Policy
- `./admin create-admin --handle test --email test@test.com --password short` → rejects (too short)
- `./admin create-admin --handle test --email test@test.com --password SecurePass123` → creates account
- `docker compose down -v && docker compose up` → migrations tracked, second `up` skips already-applied
- Migration partial failure → transaction rolls back, version NOT recorded, clear error logged
- `go test ./...` → 15+ tests pass
- Rate limit test: burst 6 requests to /auth/login → 6th gets 429
- Forgejo CI runs on push → green (vet + build + test + admin build + docker build)
- CONTRIBUTING.md, API docs, extension guide, updated DEPLOYMENT.md all exist and are accurate
- All responses include `X-Request-ID` header
- Error responses follow `{"error": "...", "code": "...", "request_id": "..."}` format
- `grep -r "TODO(errors)" --include="*.go" | wc -l` tracks unconverted handlers
- `GET /api/v1/version` → returns `{"version": "...", "commit": "abc123f", "built_at": "..."}`
- Global rate limit: 61st request in 1 second from same IP → 429
- Registration with `registration_mode=invite` and no token → rejected
- Registration with valid invite token → succeeds, token marked used
- `./admin create-invite` → prints single-use invite URL
- `GET /api/v1/instance/about` → returns user count, version, rules, admin contact
- `PATCH /posts/:id` with body change → `edited_at` set, old content in `post_edits`
- `GET /posts/:id/edits` → returns edit history array
- DM to user with `AllowDMsFrom=followers` from non-follower → 403
- `GET /.well-known/webfinger?resource=acct:handle@domain` → valid WebFinger response
- `curl -H "Accept: application/activity+json" /users/handle` → valid AP Actor JSON
- `GET /users/handle/outbox` → ordered collection of public posts as AP Notes
