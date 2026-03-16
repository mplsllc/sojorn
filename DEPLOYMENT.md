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

After your first user registers, promote them to admin:

```sql
UPDATE profiles SET role = 'admin' WHERE handle = 'your_handle';
```

Then log in at the admin panel (port 3002).

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
