# Sojorn

A self-hosted social network CMS. Deploy your own community with the features you need — text feeds, image sharing, E2EE messaging, groups, short-form video, and more. Enable only what you want.

**License**: AGPL-3.0 | **Copyright**: MPLS LLC

## How It Works

Sojorn is three things:

1. **Sojorn Server** — A Go backend + admin panel you deploy on your own infrastructure. Configure which features (extensions) are active for your community.
2. **Sojorn App** — A universal Flutter client (Android, iOS, Web). Users connect to any Sojorn instance. Your server can opt into a public directory so people can discover it.
3. **sojorn.net** — Product site + instance directory.

## Core Features (Always On)

- Text and image posts with feed algorithm
- User profiles, follow system, trust scores
- E2EE direct messaging (Signal protocol)
- Content moderation with configurable rules
- Search, discovery, hashtags
- Push notifications (FCM)
- Admin panel with full user/post/moderation management
- JWT auth, ALTCHA bot protection, Cloudflare R2 media storage

## Extensions (Operator Toggles)

Enable/disable from the admin panel at runtime — no restart needed.

| Extension | What It Does |
|-----------|-------------|
| **Audio** | In-house soundbank for audio overlays on posts |
| **Beacons** | Community safety alerts with location fuzzing |
| **Neighborhoods** | Location-based boards with auto-detection |
| **Groups** | Public/private communities with E2EE Capsules |
| **Events** | Group events with RSVP (Eventbrite/Ticketmaster ingestion) |
| **Quips** | Short-form video with sound picker |
| **Reposts** | Boost/repost system with amplification analytics |
| **Official Accounts** | Auto-publish from RSS/news sources |
| **AI Moderation** | Ollama + SightEngine moderation cascade |
| **ActivityPub** | Fediverse federation (planned) |

## Architecture

```
sojorn/
├── go-backend/        # Go API server (Gin + pgx v5 + PostgreSQL)
│   └── internal/
│       ├── extension/     # Extension system (interface, registry, middleware)
│       └── extensions/    # Individual extensions (audio, beacons, groups, ...)
├── sojorn_app/        # Flutter universal client (Riverpod + GoRouter)
├── admin/             # Next.js admin panel
├── website/           # sojorn.net (Astro SSR)
└── ai-gateway/        # AI moderation pipeline (Ollama)
```

## Quick Start

```bash
# Build the server
cd go-backend
go build -o bin/api ./cmd/api/...

# Run (needs PostgreSQL + .env config)
./bin/api

# Instance capabilities (public, no auth)
curl http://localhost:8080/api/v1/instance
```

## Admin Panel

```bash
cd admin
npm install && npm run dev
```

Includes: dashboard, user/post management, moderation queue, extensions manager, algorithm tuning, categories, groups, email templates, storage browser, system health, audit log, and more.

## Flutter App

```bash
cd sojorn_app
flutter pub get
flutter run
```

The app connects to any Sojorn server. It queries `GET /api/v1/instance` to discover which extensions are enabled and adapts the UI accordingly.

## Instance API

Every Sojorn server exposes `GET /api/v1/instance` (unauthenticated):

```json
{
  "name": "My Community",
  "description": "A place for us",
  "version": "1.0.0",
  "registration": "open",
  "extensions": {
    "audio": true,
    "beacons": false,
    "groups": true,
    "quips": true
  }
}
```

## Licensing

| Component | License |
|-----------|---------|
| Go API Engine (`go-backend/`) | [AGPL-3.0](go-backend/LICENSE) |
| AI Gateway (`ai-gateway/`) | [AGPL-3.0](ai-gateway/LICENSE) |
| Flutter App (`sojorn_app/`) | [AGPL-3.0](sojorn_app/LICENSE) |
| Admin Panel (`admin/`) | [AGPL-3.0](admin/LICENSE) |
| Website (`website/`) | [AGPL-3.0](website/LICENSE) |

## Data Privacy

- E2EE messages: server stores only ciphertext
- Location data: fuzzed before storage
- No third-party analytics, no cross-site tracking, no ad SDKs
- Hard deletes with ON DELETE CASCADE on all user data
- Moderation content auto-deleted after 14 days

## Source

| Host | URL |
|------|-----|
| GitLab | https://gitlab.com/mpls/sojorn.git |
| GitHub | https://github.com/mplsllc/sojorn.git |
