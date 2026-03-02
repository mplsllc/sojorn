# Sojorn Master TODO
Generated 2026-02-23 — carry this into each new session.

---

## 🔴 IMMEDIATE — Do before next deploy

### 1. Deploy Events Migration
```bash
wsl -d Ubuntu -- bash -c "ssh -i ~/.ssh/mpls.pem mpls 'psql \"postgres://postgres:\$DB_PASS@127.0.0.1:5432/sojorn\" < /dev/stdin'" < go-backend/migrations/20260223_create_events.sql
```

### 2. Commit + Push + Rebuild Go Binary
```bash
git add -A
git commit -m "feat: phase 2 — beacon verification, harmony, AGPL relicense, status line, trust tier, GIF fixes"
git push internal main
# Then on server: build + restart
```

### 3. Wire HarmonyCalculator into main.go
In `go-backend/cmd/api/main.go`, after dbPool is ready:
```go
harmonyCalc := services.NewHarmonyCalculator(dbPool)
harmonyCalc.ScheduleDailyRecalculation(ctx)
```

---

## 🟠 BROKEN — Needs fix now

### 4. Recently-Used Reactions — Image URLs show "•"
File: `sojorn_app/lib/widgets/reactions/anchored_reaction_popup.dart`
In the recently-used tray, replace:
```dart
child: Text(r.startsWith('https://') || r.startsWith('asset') ? '•' : r,
    style: const TextStyle(fontSize: 22)),
```
With:
```dart
child: r.startsWith('https://')
    ? CachedNetworkImage(imageUrl: r, width: 28, height: 28, fit: BoxFit.contain)
    : r.startsWith('asset:')
        ? Image.asset(r.replaceFirst('asset:', ''), width: 28, height: 28)
        : Text(r, style: const TextStyle(fontSize: 22)),
```

### 5. Trust Tier Missing from Non-Feed Queries
`GetFeed` in `post_repository.go` has trust tier ✅ but these don't:
- `GetPostsByAuthor` (line ~275)
- `GetSinglePost` / `GetPostByID`
- `GetChainedPosts`
Copy the same `LEFT JOIN public.trust_state t ON p.author_id = t.user_id` pattern
and add `COALESCE(t.tier, 'new_user') as author_trust_tier` to SELECT + Scan.

### 6. first_frame_url — Not wired into upload
`ExtractFirstFrameWebP()` exists in `video_processor.go` but is never called.
- Add `first_frame_url TEXT` column: `ALTER TABLE posts ADD COLUMN IF NOT EXISTS first_frame_url TEXT;`
- In quip upload handler (`post_handler.go` CreateQuip/CreatePost with video):
  after R2 upload, call `vp.ExtractFirstFrameWebP(ctx, videoURL)` and store result.
- Flutter: in `QuipVideoItem._buildVideo()`, prefer `first_frame_url` over `thumbnailUrl`

---

## 🟡 FEATURES — Frankenstein Framework Queue

### Phase 2 — Connect the Dots

**7. Notification Grouping Check (Mastodon-inspired)**
- Backend `GetGroupedNotifications` exists in `notification_repository.go` ✅
- Verify `notifications_screen.dart` actually calls the grouped endpoint
- Add `otherCount` display: "Patrick and 4 others liked your post"

**8. Beacon Confidence Auto-Elevation (Ushahidi-inspired)**
- In `post_handler.go` `VouchBeacon`: after INSERT, check `vouch_count >= 3`
- If so, set a `is_priority = true` flag on the beacon post
- Surface priority beacons at top of the right panel list in `beacon_screen.dart`

**9. Events on Beacon Map**
- In `beacon_screen.dart` `_buildMap()`, add MarkerLayer for events with lat/long
- Fetch `/api/v1/events/upcoming?lat=&long=&radius=`
- Use 🎉 icon, `BeaconType.event.color`

**10. Events in Home Feed**
- In `feed_sojorn_screen.dart` `_loadPosts()`, fetch upcoming events and
  interleave `_EventFeedCard` widgets at positions [5, 12]

**11. Double Ratchet / PFS (Matrix/Element-inspired)**
- Upgrade `capsule_crypto.dart` from static symmetric key to per-message ratchet
- Go backend: `ratchet_service.go` — clean-room implementation of key rotation
- 2-session task — start with state machine design doc

**12. Video Comment Threading (PeerTube-inspired)**
- File: `sojorn_app/lib/widgets/video_comments_sheet.dart`
- Add nested reply rendering (currently flat list)

**13. Discover — Quips + Groups filter tabs**
- Filter bar has All/Posts/People/Hashtags ✅
- Add `Quips` and `Groups` tabs
- Backend search endpoint needs to return quips and groups

### Phase 3 — Events + Marketplace

**14. Create Event Sheet (Hi.Events-inspired)**
- File to create: `sojorn_app/lib/screens/events/create_event_sheet.dart`
- Multi-step: Title/Date → Location/Map pin → Cover image → RSVP options
- Wire to POST `/api/v1/groups/:id/events` or a standalone `/api/v1/events`

**15. Event Card for Feed + Profile**
- `_EventFeedCard` widget for feed interleaving
- `EventDetailScreen` for tapping into an event
- Profile "Upcoming Events" widget already exists and is wired ✅

**16. Marketplace**
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
| #29 | Harmony Score expandable | ✅ DONE in profile_settings_screen |
| #30 | Settings — Privacy section | Who can see posts / message / online status |
| #30 | Settings — Appearance | Light/Dark/System theme, font size |
| #32 | Messages search bar | Filter conversations by name |
| #37 | Unify primary reaction | Standardize 🔥 across Feed/Quips/Board |
| #38 | Context-aware Create button | ✅ Desktop already has context menu |

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

## ✅ COMPLETED THIS SESSION (2026-02-23)

- All 7 pre-existing Flutter compile errors fixed
- Flutter relicensed: 240 files → AGPL-3.0
- Root LICENSE + sojorn_app/LICENSE + website licenses page updated
- MEMORY.md updated with license change
- Beacon crowd-verification buttons (`_BeaconVoteRow`) — Ushahidi-inspired
- HarmonyCalculator Go service — Discourse clean-room (`harmony_calculator.go`)
- Events: migration + Go model + handler all existed/written
- Profile status line: full stack (DB deployed, Go model/repo/handler, Flutter model/UI/settings)
- Trust tier in feed API: Go model + GetFeed query + Flutter Profile.fromJson + `_TierChip`
- GIF picker: Reddit User-Agent fix, GifCities dual-regex fix
- Reaction picker: recently-used tray + `recentReactionsProvider` + `recordUse` wired
- Beacon new types: utilityAlert, packageTheft, noiseReport, development, communityGood
- Beacon legend: collapsible "Legend" chip
- Group avatars: category icon fallback with color
- Board chat: blue/gray bubble differentiation + avatars + date separators
- Discover: content type filter bar (All/Posts/People/Hashtags)
- Profile: status line tray on sidebar + viewable profile header
- Post header: `_TierChip` harmony badge (trusted/established only)
