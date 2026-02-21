# Sojorn

A privacy-first social network with community safety features, end-to-end encrypted messaging, and neighborhood-based organizing.

**Operator**: MPLS LLC
**License**: AGPL-3.0
**Status**: Active Development — MVP near-complete

## Architecture

```
sojorn/
├── go-backend/        # Go API server (Gin + pgx v5 + PostgreSQL)
├── sojorn_app/        # Flutter mobile/web app (Riverpod)
├── admin/             # Next.js admin panel
├── website/           # sojorn.net (Astro SSR)
├── mpls-website/      # mp.ls (Astro SSR)
└── sojorn_docs/       # Internal docs and deployment notes
```

## Go Backend

**Framework**: Gin + pgx v5 + PostgreSQL + PostGIS
**Port**: 8080 (behind nginx at api.sojorn.net)

Key features:
- JWT auth with 15-minute access tokens + refresh tokens
- ALTCHA bot protection (proof-of-work, no tracking)
- Feed algorithm: 5-factor scoring, cooling period, diversity injection, impression recording
- Content moderation: Local AI (Ollama) + SightEngine text/image analysis, Three Poisons scoring
- E2EE messaging (Signal protocol key management)
- Community Safety Beacons with neutral-language filtering and coordinate fuzzing (~1.1km precision)
- Neighborhood boards with location-based discovery
- Groups and encrypted Capsules (E2EE group messaging)
- Cloudflare R2 media storage with signed URLs
- Push notifications via FCM
- Repost/boost system with amplification analytics
- Trust system (harmony score) with rate limiting
- Profile widget system with layout persistence

```bash
cd go-backend
go build -o bin/api ./cmd/api/...
```

## Flutter App

**State management**: Riverpod
**Video**: ffmpeg_kit_flutter_new (mobile), stub for web
**Platforms**: Android, iOS, Web

Key features:
- Full post creation with rich text, images, video, audio overlays
- Quips (short-form video) with comment chains
- E2EE direct messaging (Signal protocol)
- Community Safety Beacons and neighborhood boards
- Group navigation, group feed, encrypted Capsules
- Signed media URL resolution via Go backend
- Profile privacy controls and NSFW blur toggles

```bash
cd sojorn_app
flutter pub get
flutter run
```

## Admin Panel

**Framework**: Next.js 14 (App Router) + TailwindCSS
**Port**: 3001

Includes: dashboard, user/post management, moderation queue, AI moderation config, appeals, reports, algorithm tuning, categories, neighborhoods, official accounts, groups/capsules, quip repair, storage browser, system health, reserved usernames, safe domains, email templates, audit log, AI audit log, waitlist, content tools.

```bash
cd admin
npm install && npm run dev
```

## Websites

### sojorn.net (`website/`)

Astro SSR site with privacy policy, terms of service, advertising policy, account deletion/data clearing forms (SendPulse integration). Runs via PM2 on port 4323.

### mp.ls (`mpls-website/`)

MPLS LLC company site. Astro SSR with newsletter signup, project portal. Runs via PM2 on port 4322.

```bash
# Build either site
cd website && npm run build      # sojorn.net
cd mpls-website && npm run build  # mp.ls
```

## Server Deployment

**Server**: Hetzner VPS at 116.202.231.103
**OS**: Ubuntu
**Reverse proxy**: Nginx with Let's Encrypt SSL
**Process manager**: PM2 (websites), systemd (Go API)
**Backups**: Borgmatic (every 6h) + rclone sync to Cloudflare R2 (14-day retention)

```bash
# Full deploy from server
cd /opt/sojorn
git pull internal main

# Go backend
cd go-backend && go build -o bin/api ./cmd/api/...
cp bin/api ../bin/sojorn-api.new && mv ../bin/sojorn-api.new ../bin/sojorn-api
sudo systemctl restart sojorn-api.service

# sojorn.net
cd ../website && npm run build && pm2 restart sojorn-site

# mp.ls
cd ../mpls-website && npm run build && pm2 restart mp.ls
```

## Database

**Engine**: PostgreSQL 16 with PostGIS
**Tables**: 104 (as of Feb 2026)
**Migrations**: `go-backend/migrations/` (gitignored, force-add with `git add -f`)

```bash
# Run a migration
psql "$DATABASE_URL" -f go-backend/migrations/MIGRATION_FILE.sql
```

## Git Remotes

| Remote | URL | Purpose |
|--------|-----|---------|
| `internal` | `https://git.mp.ls/patrick/sojorn.git` | Primary (Forgejo) |
| `public` | `https://gitlab.com/patrickbritton3/sojorn.git` | Public mirror |

## Data Privacy

- E2EE messages: server stores only ciphertext
- Board entry coordinates: fuzzed to ~1.1km before storage
- Beacon text: neutral-language filter applied automatically
- Expired tokens: purged daily via cron
- Moderation content snippets: auto-deleted after 14 days
- Cloud backups: 14-day rolling retention
- No third-party analytics, no cross-site tracking, no third-party ad SDKs
- Hard deletes with ON DELETE CASCADE on all user data
- Age requirement: 18+

## Environment Variables

See `go-backend/.env.example`, `website/.env.example`, and `mpls-website/.env.example` for required configuration.
