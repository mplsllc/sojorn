# Sojorn — Self-Hosting Guide

Sojorn is a self-hosted, extensible social network. This guide covers everything you need to run your own instance.

## Quick Start (Docker Compose)

```bash
git clone https://github.com/your-org/sojorn.git
cd sojorn

# Configure
cp go-backend/.env.example .env
# Edit .env — at minimum set JWT_SECRET:
#   JWT_SECRET=$(openssl rand -hex 32)

# Launch
docker compose up -d

# API:   http://localhost:8080
# Admin: http://localhost:3002
```

## Prerequisites

**Docker method:** Docker and Docker Compose v2+

**Manual method:**
- Go 1.25+
- Node.js 20+
- PostgreSQL 16+
- (Optional) Ollama for AI moderation
- (Optional) Cloudflare R2 or S3-compatible storage for media

## Environment Variables

Copy `go-backend/.env.example` and configure:

### Required

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | Auth signing key — generate with `openssl rand -hex 32` |

### Instance Identity

| Variable | Default | Description |
|---|---|---|
| `INSTANCE_NAME` | Sojorn | Name shown in the app |
| `API_BASE_URL` | http://localhost:8080 | Public API URL |
| `APP_BASE_URL` | http://localhost:3000 | Public frontend URL |
| `CORS_ORIGINS` | * | Allowed origins (comma-separated) |
| `COOKIE_DOMAIN` | _(empty)_ | Auth cookie domain (e.g. `.example.com`) |
| `SUPPORT_EMAIL` | _(empty)_ | Contact email shown to users |

### Email (SMTP)

Required for account verification and notifications. Leave blank to disable.

| Variable | Description |
|---|---|
| `SMTP_HOST` | SMTP server hostname |
| `SMTP_PORT` | SMTP port (default: 587) |
| `SMTP_USER` | SMTP username |
| `SMTP_PASS` | SMTP password |
| `SMTP_FROM` | Sender address (e.g. `noreply@example.com`) |

### Media Storage (S3/R2)

Required for image and video uploads.

| Variable | Description |
|---|---|
| `R2_ENDPOINT` | S3-compatible endpoint URL |
| `R2_ACCESS_KEY` | Access key |
| `R2_SECRET_KEY` | Secret key |
| `R2_MEDIA_BUCKET` | Bucket for images (default: `media`) |
| `R2_VIDEO_BUCKET` | Bucket for videos (default: `videos`) |
| `R2_IMG_DOMAIN` | CDN domain for images |
| `R2_VID_DOMAIN` | CDN domain for videos |

### Optional Services

| Variable | Default | Description |
|---|---|---|
| `FIREBASE_CREDENTIALS_FILE` | _(empty)_ | Firebase service account JSON for push notifications |
| `OLLAMA_URL` | http://localhost:11434 | Ollama API for AI moderation |
| `SEARXNG_URL` | http://localhost:8888 | SearXNG for official accounts news |
| `SIGHTENGINE_USER` | _(empty)_ | SightEngine image moderation |
| `EVENTBRITE_API_KEY` | _(empty)_ | Event ingestion |
| `TICKETMASTER_API_KEY` | _(empty)_ | Event ingestion |

## Manual Deployment (Bare Metal)

### 1. Database

```bash
# Create PostgreSQL database
createdb sojorn

# Run migrations
cd go-backend
export DATABASE_URL="postgres://user:pass@localhost:5432/sojorn?sslmode=disable"
go run cmd/migrate/main.go
```

### 2. API Backend

```bash
cd go-backend
cp .env.example .env
# Edit .env with your values

go build -ldflags="-s -w" -o bin/api ./cmd/api/main.go
./bin/api
```

### 3. Admin Panel

```bash
cd admin
npm ci
NEXT_PUBLIC_API_URL=https://api.example.com npm run build
npm start -- --port 3002
```

### 4. Flutter App

The Flutter app connects to your API via a compile-time flag:

```bash
cd sojorn_app
flutter build web --dart-define=API_BASE_URL=https://api.example.com/api/v1
flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

## First Admin Account

After your first user registers, promote them to admin using the CLI tool:

```bash
cd go-backend
./admin create-admin --handle your_handle
```

Then log in at the admin panel (port 3002).

## Invite-Only Mode

To restrict registration to invited users only, set the registration mode to "invite" in the admin panel under **Instance Config**. When invite-only mode is active, the `/auth/register` endpoint requires a valid invite code. Existing users are unaffected.

## Version Endpoint

Check the running version of your instance at any time:

```bash
curl https://api.example.com/api/v1/version
```

Returns:

```json
{
  "version": "1.0.0-beta",
  "commit": "abc1234",
  "built_at": "2026-01-15T12:00:00Z"
}
```

## Extensions

Sojorn features are modular. From the admin panel, go to **Extensions** to enable/disable:

| Extension | Description |
|---|---|
| Audio/Soundbank | Sound overlays for posts and quips |
| Beacons | Community safety alerts and crowd-verified reports |
| Neighborhoods | Location-based boards and local moderation |
| Groups | Public community groups with discovery |
| Capsules | End-to-end encrypted private groups |
| Events | Event discovery, RSVP, and ingestion |
| Reposts | Repost, boost, and amplification system |
| Discover | Search, hashtags, and content exploration |
| Chat | Direct messaging with reactions |

Extensions can be toggled at runtime without restarting the server.

## Reverse Proxy (Nginx)

Example configuration for production:

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}

server {
    listen 443 ssl http2;
    server_name admin.example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Backups

### Database

```bash
# Backup
pg_dump -Fc sojorn > sojorn_backup_$(date +%Y%m%d).dump

# Restore
pg_restore -d sojorn sojorn_backup.dump
```

### Media

Back up your R2/S3 buckets using `rclone` or your cloud provider's tools.

## Upgrading

```bash
git pull
docker compose build
docker compose up -d
```

Migrations run automatically on container start.

## Migration Failure Recovery

If a database migration fails (e.g., due to a syntax error in SQL, a constraint violation, or a timeout), the server will refuse to start until the issue is resolved.

To recover:

1. **Check the error message.** The server logs the exact migration file and SQL error on startup.
2. **Fix the SQL issue.** If you are running custom migrations, correct the problematic `.up.sql` file. If this is a Sojorn release migration, check the release notes or issue tracker for known workarounds.
3. **Re-run migrations.** Start the server again or run the migration tool manually:
   ```bash
   cd go-backend
   export DATABASE_URL="postgres://user:pass@localhost:5432/sojorn?sslmode=disable"
   go run cmd/migrate/main.go
   ```
4. **If the migration partially applied,** you may need to manually inspect the database state and clean up incomplete changes before re-running. Check the `schema_migrations` table to see which version was last successfully applied.

Migrations are idempotent where possible, but some DDL operations (adding columns, creating tables) cannot be safely retried if they partially succeeded. In those cases, manually roll back the partial change and re-run.

## Logging

Sojorn uses structured logging via zerolog. Set the log level with the `LOG_LEVEL` environment variable.

| Level | Value | What It Shows |
|-------|-------|---------------|
| Debug | `debug` | Everything: SQL queries, request/response details, middleware decisions, extension lifecycle events. Use for local development and troubleshooting. |
| Info | `info` | Startup summary, extension toggles, background job completions, significant state changes. This is the default. |
| Warn | `warn` | Degraded conditions: missing optional services (SMTP, R2, Firebase), failed background job iterations, deprecated usage patterns. The server continues operating. |
| Error | `error` | Failures that affect user-facing behavior: database errors, failed email sends, unrecoverable background job errors. Minimal output -- use in production if log volume is a concern. |

Set the level in your environment:

```bash
export LOG_LEVEL=info
```

Or in your `.env` file:

```
LOG_LEVEL=info
```

Logs are written to stderr in a human-readable console format. For production, pipe to a log aggregator or use Docker's logging driver.

## Shutdown & Restart

Sojorn handles graceful shutdown when it receives a `SIGTERM` or `SIGINT` signal.

The shutdown sequence:

1. **Signal received.** The server stops accepting new connections.
2. **In-flight requests drain.** All currently active HTTP requests are allowed to complete.
3. **Grace period: 10 seconds.** If in-flight requests do not finish within 10 seconds, the server force-closes remaining connections.
4. **Background jobs stop.** The background context is cancelled, signaling all extension background goroutines and internal jobs (feed scoring, account purge, audit retention) to exit.
5. **Database pool closes.** The PostgreSQL connection pool is drained and closed.
6. **Process exits.** The server logs total uptime and exits cleanly.

To restart with zero downtime behind a reverse proxy, start the new instance before stopping the old one, or use a process manager like systemd that handles restart sequencing:

```ini
# Example systemd unit excerpt
[Service]
ExecStart=/opt/sojorn/bin/api
Restart=always
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=15
```

The 15-second `TimeoutStopSec` gives the 10-second grace period room to complete before systemd sends SIGKILL.
