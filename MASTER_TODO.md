# Sojorn Master TODO
Last updated 2026-03-16.

---

## 🔧 EXTENSION MIGRATION — CMS Refactor

### Migrated to extension system ✅
| Extension | ID | Routes | Background Jobs |
|---|---|---|---|
| Soundbank | `audio` | sounds CRUD | — |
| Beacons | `beacons` | all beacon routes (create, nearby, unified, cameras, iced, vouch, report, resolve, search) | beacon ingestion |
| Neighborhoods | `neighborhoods` | detect, board, moderation | — |
| Groups | `groups` | groups CRUD, membership, group events | — |
| Capsules | `capsules` | E2EE groups, posts, chat, threads, key escrow | — |
| Events | `events` | public event feed, user events | event ingestion (Eventbrite + Ticketmaster) |
| Reposts | `reposts` | repost, boost, amplification, trending | — |
| Discover | `discover` | search, hashtags, follow suggestions | trending score refresh |
| Chat | `chat` | conversations, messages, reactions | — |
| Official Accounts | `official_accounts` | — (admin-only) | news posting scheduler |
| Content Moderation | `moderation` | /moderate, /analysis/tone | — |

### Still in main.go
- **Admin routes** — adminHandler is a mega-handler; admin routes for each feature still wired inline
- **Marketplace** — not yet built

### Next steps
- [ ] Split adminHandler into per-extension admin route registration
- [ ] Flutter: query `GET /api/v1/instance` to conditionally render feature UI
- [ ] Marketplace extension (DB + handler + Flutter)

---

## 🟠 BROKEN — Needs fix now

*(none)*

---

## 🟡 FEATURES — Queue

### Phase 2 — Connect the Dots

**2. Notification Grouping Check (Mastodon-inspired)**
- Backend `GetGroupedNotifications` exists in `notification_repository.go` ✅
- Verify `notifications_screen.dart` actually calls the grouped endpoint
- Add `otherCount` display: "Patrick and 4 others liked your post"

**3. Beacon Confidence Auto-Elevation (Ushahidi-inspired)**
- In `post_handler.go` `VouchBeacon`: after INSERT, check `vouch_count >= 3`
- If so, set a `is_priority = true` flag on the beacon post
- Surface priority beacons at top of the right panel list in `beacon_screen.dart`

**4. Events on Beacon Map**
- In `beacon_screen.dart` `_buildMap()`, add MarkerLayer for events with lat/long
- Fetch `/api/v1/events/upcoming?lat=&long=&radius=`
- Use 🎉 icon, `BeaconType.event.color`

**5. Events in Home Feed**
- In `feed_sojorn_screen.dart` `_loadPosts()`, fetch upcoming events and
  interleave `_EventFeedCard` widgets at positions [5, 12]

**6. Double Ratchet / PFS (Matrix/Element-inspired)**
- Upgrade `capsule_crypto.dart` from static symmetric key to per-message ratchet
- Go backend: `ratchet_service.go` — clean-room implementation of key rotation
- 2-session task — start with state machine design doc

**7. Video Comment Threading (PeerTube-inspired)**
- File: `sojorn_app/lib/widgets/video_comments_sheet.dart`
- Add nested reply rendering (currently flat list)

**8. Discover — Quips + Groups filter tabs**
- Filter bar has All/Posts/People/Hashtags ✅
- Add `Quips` and `Groups` tabs
- Backend search endpoint needs to return quips and groups

### Phase 3 — Events + Marketplace

**9. Create Event Sheet (Hi.Events-inspired)**
- File to create: `sojorn_app/lib/screens/events/create_event_sheet.dart`
- Multi-step: Title/Date → Location/Map pin → Cover image → RSVP options
- Wire to POST `/api/v1/groups/:id/events` or a standalone `/api/v1/events`

**10. Event Card for Feed + Profile**
- `_EventFeedCard` widget for feed interleaving
- `EventDetailScreen` for tapping into an event
- Profile "Upcoming Events" widget already exists and is wired ✅

**11. Marketplace**
- DB migration: `CREATE TABLE marketplace_listings (...)`
- Go handler, Flutter listing screen, Flutter create sheet
- Connect "Message Seller" to encrypted DMs

---

## 🟢 v2 BUG SPEC — Remaining genuine items

| # | Item | Notes |
|---|---|---|
| #8 | Dashboard live preview when toggling | Toggle dims widget in sidebar immediately |
| #13 | Quips comment threading + likes | Nested replies, heart on each comment |
| #16 | Beacon map filter controls wired | Filter UI exists, not connected to map |
| #30 | Settings — Privacy section | Who can see posts / message / online status |
| #30 | Settings — Appearance | Light/Dark/System theme, font size |
| #32 | Messages search bar | Filter conversations by name |
| #37 | Unify primary reaction | Standardize 🔥 across Feed/Quips/Board |

---

## 🔵 OPEN SOURCE ATTRIBUTION — Add to /licenses page

Add these to `website/src/pages/licenses.astro` as ported projects:

| Project | License | What |
|---|---|---|
| Matrix/Element | Apache 2.0 | E2EE patterns |
| Ushahidi | AGPL-3.0 | Beacon verification UI ✅ |
| Discourse | GPL-2.0 | HarmonyCalculator algorithm ✅ |
| Hi.Events | AGPL-3.0 | Event creation forms |
| HumHub | AGPL-3.0 | Community spaces patterns |
| Misskey | AGPL-3.0 | Reaction picker recently-used tray ✅ |
| Mastodon | AGPL-3.0 | Notification grouping |
| PeerTube | AGPL-3.0 | Video comment threading |
| Pixelfed | AGPL-3.0 | Photo grid, discover feed |

---

## ✅ COMPLETED

- Extension system: 11 features migrated to toggleable extensions with runtime enable/disable ✅
- Self-hosting: all hardcoded domains removed, .env.example, docker-compose.yml, DEPLOYMENT.md, Dockerfiles ✅
- Instance branding: admin settings page for name, logo, accent color, registration mode, contact/terms/privacy ✅
- first_frame_url: DB migration + Go model field + repo INSERT/SELECT + handler call after frame moderation + Flutter Quip model + QuipVideoItem thumbnail preference ✅
- Quip report button: wired to SanctuarySheet via Post stub (id/authorId/caption from Quip) ✅
- All 7 pre-existing Flutter compile errors fixed
- Flutter relicensed: 240 files → AGPL-3.0
- Root LICENSE + sojorn_app/LICENSE + website licenses page updated
- Beacon crowd-verification buttons (`_BeaconVoteRow`) — Ushahidi-inspired
- HarmonyCalculator Go service — Discourse clean-room (`harmony_calculator.go`) — **wired into main.go** ✅
- Events: migration + Go model + handler + DB tables deployed ✅
- Profile status line: full stack (DB, Go, Flutter) ✅
- Trust tier: wired into ALL post queries (feed, GetPostByID, GetPostsByAuthor, GetChainedPosts) ✅
- GIF picker: Reddit User-Agent fix, GifCities dual-regex fix
- Reaction picker: recently-used tray + `recentReactionsProvider` + `recordUse` + image rendering fixed ✅
- Beacon new types + legend
- Group avatars: category icon fallback
- Board chat: bubble styling + avatars + date separators
- Discover: content type filter bar (All/Posts/People/Hashtags)
- Profile: status line tray on sidebar + viewable profile header
- Post header: `_TierChip` harmony badge (trusted/established only)
- Soundbank + quip editor flow ✅
- Security: history rewrite — DB password, personal emails scrubbed from all 3 remotes ✅
- JWT_SECRET: rotated from placeholder to strong 64-char key ✅
- key_handler.go: debug logging of cryptographic signatures removed ✅
- Infisical migration: all secrets moved, local .env files deleted ✅
- Flutter dart-define keys (KLIPY, Firebase) added to Infisical ✅
