# Sojorn

A self-hosted social network CMS. Deploy your own community with the features you need — text feeds, image sharing, E2EE messaging, groups, short-form video, and more. Enable only what you want.

## Architecture

| Component | Stack |
|-----------|-------|
| `go-backend/` | Go API server (Gin + pgx v5 + PostgreSQL) |
| `admin/` | Next.js admin panel |
| `sojorn_app/` | Flutter universal client (Android, iOS, Web) |
| `ai-gateway/` | AI moderation pipeline (Ollama) |

## Quick Start

```bash
git clone https://github.com/mplsllc/sojorn.git && cd sojorn
cp go-backend/.env.example go-backend/.env   # edit with your values
docker compose up -d
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full self-hosting guide (TLS, R2, FCM, DNS, etc.).

## Core Features

- Text and image posts with feed algorithm
- User profiles, follow system, trust scores
- E2EE direct messaging (Signal protocol)
- Content moderation with configurable rules
- Push notifications (FCM)
- Admin panel with user/post/moderation management
- JWT auth, ALTCHA bot protection, Cloudflare R2 media storage

## Extensions

Toggle from the admin panel at runtime — no restart needed.

| Extension | Description |
|-----------|-------------|
| **Audio** | Soundbank for audio overlays on posts |
| **Beacons** | Community safety alerts with location fuzzing |
| **Neighborhoods** | Location-based boards with auto-detection |
| **Groups** | Public/private communities with E2EE Capsules |
| **Capsules** | Ephemeral encrypted group threads |
| **Events** | Group events with RSVP and ticket ingestion |
| **Reposts** | Boost/repost system with amplification analytics |
| **Discover** | Content and community discovery feeds |
| **Chat** | Real-time group and direct messaging |

## Instance API

Every server exposes `GET /api/v1/instance` (unauthenticated) so clients can discover enabled extensions and adapt the UI.

## Data Privacy

- E2EE messages: server stores only ciphertext
- Location data: fuzzed before storage
- No third-party analytics, no cross-site tracking, no ad SDKs
- Hard deletes with `ON DELETE CASCADE` on all user data

## License

[AGPL-3.0](go-backend/LICENSE) — Copyright MPLS LLC
