# Sojorn API Reference

Base URL: `/api/v1`

All authenticated endpoints require an `Authorization: Bearer <token>` header. Tokens are obtained from the login or refresh endpoints.

---

## Health & Instance

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Basic health check (returns `{"status":"ok"}`) |
| HEAD | `/health` | No | Health check (status code only) |
| GET | `/health/detailed` | No | Detailed health with component status |
| GET | `/health/ready` | No | Readiness probe for load balancers |
| GET | `/health/live` | No | Liveness probe for orchestrators |
| GET | `/api/v1/instance` | No | Public instance info: name, capabilities, enabled extensions |
| GET | `/api/v1/version` | No | Build info: version, git commit, build date |
| GET | `/robots.txt` | No | Returns `Disallow: /` for all user agents |
| GET | `/api/v1/test` | No | Route connectivity test |

## Authentication

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | No | Create a new account (rate limited: 0.5/s, burst 3) |
| POST | `/auth/signup` | No | Alias for `/auth/register` |
| POST | `/auth/login` | No | Authenticate and receive access + refresh tokens (rate limited: 1/s, burst 5) |
| POST | `/auth/refresh` | No | Exchange a refresh token for a new access token |
| POST | `/auth/resend-verification` | No | Re-send the email verification link (rate limited: 0.2/s, burst 2) |
| GET | `/auth/verify` | No | Verify email address via token in query string |
| POST | `/auth/forgot-password` | No | Send a password reset email (rate limited: 0.2/s, burst 2) |
| POST | `/auth/reset-password` | No | Reset password using the emailed token |
| GET | `/auth/altcha-challenge` | No | Get an ALTCHA proof-of-work challenge |
| POST | `/auth/mfa/verify` | No | Submit a TOTP code during login (no auth -- user is mid-login) |
| POST | `/auth/mfa/setup` | Yes | Begin MFA setup (returns TOTP secret + QR URI) |
| POST | `/auth/mfa/confirm` | Yes | Confirm MFA setup with a valid TOTP code |
| POST | `/auth/mfa/disable` | Yes | Disable MFA on the current account |

## Users & Profiles

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/profile` | Yes | Get the authenticated user's profile |
| GET | `/profiles/:id` | Yes | Get a user's public profile by ID |
| PATCH | `/profile` | Yes | Update the authenticated user's profile |
| POST | `/complete-onboarding` | Yes | Mark onboarding as complete |
| GET | `/profile/trust-state` | Yes | Get the user's Harmony (trust) score state |
| GET | `/users/by-handle/:handle` | Yes | Look up a user by handle |
| POST | `/users/:id/follow` | Yes | Follow a user |
| DELETE | `/users/:id/follow` | Yes | Unfollow a user |
| POST | `/users/:id/accept` | Yes | Accept a pending follow request |
| DELETE | `/users/:id/reject` | Yes | Reject a pending follow request |
| GET | `/users/requests` | Yes | List pending incoming follow requests |
| GET | `/users/:id/followers` | Yes | List a user's followers |
| GET | `/users/:id/following` | Yes | List who a user follows |
| POST | `/users/:id/block` | Yes | Block a user |
| DELETE | `/users/:id/block` | Yes | Unblock a user |
| GET | `/users/blocked` | Yes | List blocked users |
| POST | `/users/block_by_handle` | Yes | Block a user by handle |
| POST | `/users/me/blocks/bulk` | Yes | Bulk block multiple users |
| POST | `/users/report` | Yes | Report a user |
| GET | `/reports/mine` | Yes | List reports filed by the authenticated user |
| POST | `/users/circle/:id` | Yes | Add a user to your Close Circle |
| DELETE | `/users/circle/:id` | Yes | Remove a user from your Close Circle |
| GET | `/users/circle/members` | Yes | List Close Circle members |
| GET | `/users/me/export` | Yes | Export your account data |

## Posts

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/posts` | Yes | Create a new post |
| GET | `/posts/:id` | Yes | Get a single post |
| GET | `/posts/:id/chain` | Yes | Get a post's reply chain (thread view) |
| GET | `/posts/:id/thread` | Yes | Alias for `/posts/:id/chain` |
| GET | `/posts/:id/focus-context` | Yes | Get surrounding context for a focused post |
| PATCH | `/posts/:id` | Yes | Update a post |
| DELETE | `/posts/:id` | Yes | Delete a post |
| POST | `/posts/:id/pin` | Yes | Pin a post to your profile |
| PATCH | `/posts/:id/visibility` | Yes | Change post visibility (public, circle, private) |
| POST | `/posts/:id/hide` | Yes | Hide a post from your feed |
| POST | `/posts/:id/view` | Yes | Record a view impression |
| GET | `/posts/:id/score` | Yes | Get the algorithmic score for a post |
| POST | `/posts/:id/like` | Yes | Like a post |
| DELETE | `/posts/:id/like` | Yes | Unlike a post |
| POST | `/posts/:id/save` | Yes | Save (bookmark) a post |
| DELETE | `/posts/:id/save` | Yes | Unsave a post |
| POST | `/posts/:id/reactions/toggle` | Yes | Toggle an emoji reaction on a post |
| POST | `/posts/:id/comments` | Yes | Create a comment on a post |
| GET | `/users/:id/posts` | Yes | Get a user's posts |
| GET | `/users/:id/saved` | Yes | Get a user's saved posts |
| GET | `/users/me/liked` | Yes | Get posts liked by the authenticated user |

## Feed

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/feed` | Yes | Algorithmic home feed |
| GET | `/feed/personal` | Yes | Alias for `/feed` |
| GET | `/feed/sojorn` | Yes | Instance-wide curated feed |

## Categories

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/categories` | Yes | List all content categories |
| POST | `/categories/settings` | Yes | Set user category preferences |
| GET | `/categories/settings` | Yes | Get user category preferences |

## Notifications

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/notifications` | Yes | List notifications |
| GET | `/notifications/unread` | Yes | Get unread notification count |
| GET | `/notifications/badge` | Yes | Get badge count (unread + actionable) |
| PUT | `/notifications/:id/read` | Yes | Mark a notification as read |
| POST | `/notifications/read` | Yes | Bulk mark notifications as read |
| PUT | `/notifications/read-all` | Yes | Mark all notifications as read |
| POST | `/notifications/archive` | Yes | Archive a notification |
| POST | `/notifications/archive-all` | Yes | Archive all notifications |
| DELETE | `/notifications/:id` | Yes | Delete a notification |
| GET | `/notifications/preferences` | Yes | Get notification preferences |
| PUT | `/notifications/preferences` | Yes | Update notification preferences |
| POST | `/notifications/device` | Yes | Register a device for push notifications |
| DELETE | `/notifications/device` | Yes | Unregister a device |
| DELETE | `/notifications/devices` | Yes | Unregister all devices |

## Activity Log

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/users/me/activity` | Yes | Get the authenticated user's activity log |

## Settings

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/settings/privacy` | Yes | Get privacy settings |
| PATCH | `/settings/privacy` | Yes | Update privacy settings |
| GET | `/settings/user` | Yes | Get user preferences |
| PATCH | `/settings/user` | Yes | Update user preferences |

## Keys (End-to-End Encryption)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/keys` | Yes | Publish identity + signed pre-key + one-time keys |
| GET | `/keys/:id` | Yes | Fetch a user's key bundle |
| DELETE | `/keys/otk/:keyId` | Yes | Delete a consumed one-time key |

## Backup & Recovery

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/backup/sync/generate-code` | Yes | Generate a device sync code |
| POST | `/backup/sync/verify-code` | Yes | Verify a device sync code |
| POST | `/backup/upload` | Yes | Upload an encrypted backup |
| GET | `/backup/download` | Yes | Download the latest backup |
| GET | `/backup/download/:backupId` | Yes | Download a specific backup |
| GET | `/backup/list` | Yes | List available backups |
| DELETE | `/backup/:backupId` | Yes | Delete a backup |
| GET | `/backup/preferences` | Yes | Get backup preferences |
| PUT | `/backup/preferences` | Yes | Update backup preferences |
| POST | `/recovery/social/setup` | Yes | Set up social recovery contacts |
| POST | `/recovery/initiate` | Yes | Start a social recovery session |
| POST | `/recovery/submit-shard` | Yes | Submit a recovery shard from a contact |
| POST | `/recovery/complete/:sessionId` | Yes | Complete social recovery |
| GET | `/devices` | Yes | List registered devices |

## Media

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/upload` | Yes | Upload an image or video |
| GET | `/media/sign` | Yes | Get a signed URL for private media |
| GET | `/image-proxy` | No | CORS-bypassing image proxy for external URLs |

## Account Lifecycle

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/account/status` | Yes | Get account status (active, deactivated, pending deletion) |
| POST | `/account/deactivate` | Yes | Deactivate account (reversible) |
| DELETE | `/account` | Yes | Request account deletion (14-day grace period) |
| POST | `/account/cancel-deletion` | Yes | Cancel a pending deletion |
| POST | `/account/destroy` | Yes | Request immediate account destruction (email confirmation required) |
| GET | `/account/destroy/confirm` | No | Confirm immediate destruction via emailed link |

## Appeals

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/appeals` | Yes | List your moderation violations |
| GET | `/appeals/summary` | Yes | Get violation summary (strike count, status) |
| POST | `/appeals` | Yes | Submit an appeal for a moderation action |
| GET | `/appeals/:id` | Yes | Get appeal details |

## Profile & Dashboard Layout

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/profile/layout` | Yes | Get your profile widget layout |
| PUT | `/profile/layout` | Yes | Save your profile widget layout |
| GET | `/profiles/:id/layout` | Yes | Get another user's public profile layout |
| GET | `/dashboard/layout` | Yes | Get your dashboard widget layout |
| PUT | `/dashboard/layout` | Yes | Save your dashboard widget layout |
| GET | `/users/:id/dashboard-layout` | Yes | Get another user's dashboard layout |

## Safe Domains

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/safe-domains` | Yes | List trusted domains (no external link warning) |
| GET | `/safe-domains/check` | Yes | Check if a URL is on the safe list |

## Waitlist

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/waitlist` | No | Join the instance waitlist (rate limited: 0.2/s, burst 3) |

## Username Claims

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/username-claim` | No | Submit a reserved username claim request |

---

## Extension Routes

Extension routes return `404 {"error": "feature not available on this instance"}` when the extension is disabled. Extensions can be toggled at runtime from the admin panel without restarting the server.

### Beacons

Community safety alerts and crowd-verified incident reports. Routes are registered under `/api/v1/beacons` (authorized) and `/api/v1/admin/beacons` (admin).

### Neighborhoods

Location-based community boards with local moderation. Routes are registered under `/api/v1/neighborhoods` (authorized) and managed via `/api/v1/admin/neighborhoods` (admin).

### Groups

Public community groups with member roles, discovery, and group feeds. Routes are registered under `/api/v1/groups` (authorized) and `/api/v1/admin/groups` (admin).

### Capsules

End-to-end encrypted private groups. Routes are registered under `/api/v1/capsules` (authorized).

### Events

Event discovery, RSVP tracking, and ingestion from external sources (Eventbrite, Ticketmaster). Routes are registered under `/api/v1/events` (authorized) and `/api/v1/admin/events` (admin).

### Reposts

Repost and boost system for amplifying content. Routes are registered under `/api/v1/reposts` (authorized).

### Discover

Search, hashtags, trending content, and follow suggestions. Routes are registered under `/api/v1/discover` and related sub-paths (authorized).

### Chat

Direct messaging with reactions, read receipts, and real-time delivery via WebSocket. Routes are registered under `/api/v1/chat` (authorized).

### Audio / Soundbank

In-house audio library for sound overlays on posts. Routes are registered under `/api/v1/sounds` (authorized) and `/api/v1/admin/sounds` (admin).

### Official Accounts

AI-powered official accounts that aggregate and post curated content. Routes are registered under `/api/v1/official-accounts` (authorized) and `/api/v1/admin/official-accounts` (admin).

### Moderation

Content analysis, tone detection, and automated moderation pipeline. Routes are registered under `/api/v1/analysis` (authorized) and `/api/v1/admin/moderation` (admin).

---

## Admin API

The admin API is mounted at `/api/v1/admin`. All admin endpoints require a valid JWT from an account with the `admin` role (or `moderator` for a subset of read-only and moderation routes).

Admin login uses a separate endpoint:

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/admin/login` | No | Authenticate as admin (rate limited: 0.1/s, burst 2) |
| POST | `/api/v1/admin/logout` | No | Clear admin session |
| GET | `/api/v1/admin/altcha-challenge` | No | ALTCHA challenge for admin login |

High-level admin capabilities include:

- **Dashboard & Analytics** -- growth stats, user metrics, content metrics
- **User Management** -- list, search, update status/role/verification, create users, hard delete
- **Post Management** -- list, review, update status, bulk operations, thumbnail management
- **Moderation Queue** -- review flagged content, bulk actions, AI moderation audit log
- **Appeals** -- review and resolve user appeals
- **Reports** -- user reports and capsule reports management
- **Categories** -- CRUD for content categories
- **Neighborhoods** -- create, update, delete, manage admins and board entries
- **Groups** -- manage groups, members, and roles
- **Events** -- manage events
- **Extensions** -- view and toggle extensions, instance configuration
- **Algorithm Config** -- tune feed scoring weights, refresh scores
- **Storage** -- R2/S3 bucket stats, browse and delete objects
- **AI Management** -- Ollama model management, moderation config, training data export
- **Official Accounts** -- manage AI-powered content accounts
- **Email Templates** -- customize transactional emails, send test emails
- **Safe Domains** -- manage the trusted domain allowlist
- **Beacon Alerts** -- manage alert feeds, trigger syncs
- **Waitlist** -- manage signups, import CSVs, send email blasts
- **Reserved Usernames** -- manage reserved handles and claim requests
- **Audit Log** -- browse and purge audit entries
- **Social Media Import** -- fetch content, manage platform cookies

See the admin panel for the full interactive reference of every admin endpoint.

---

## WebSocket

| Path | Auth | Description |
|------|------|-------------|
| `/ws` | Yes (token in query) | Real-time event stream |

The WebSocket connection delivers real-time updates including new posts in followed feeds, notifications, chat messages, and typing indicators. Connect with your JWT as a query parameter:

```
wss://api.example.com/ws?token=<jwt>
```

---

## Error Format

All error responses follow a consistent JSON structure:

```json
{
  "error": "human-readable error message",
  "code": "MACHINE_READABLE_CODE",
  "request_id": "uuid-v4"
}
```

Common error codes:

| HTTP Status | Meaning |
|-------------|---------|
| 400 | Bad request -- invalid input or missing required fields |
| 401 | Unauthorized -- missing or expired token |
| 403 | Forbidden -- insufficient permissions |
| 404 | Not found -- resource does not exist or extension is disabled |
| 409 | Conflict -- duplicate resource (e.g., already following) |
| 429 | Too many requests -- rate limit exceeded |
| 500 | Internal server error |

---

## Rate Limits

Rate limits are enforced per IP address using a token-bucket algorithm.

| Endpoint Category | Rate | Burst |
|-------------------|------|-------|
| General API (`/api/v1/*`) | 30 req/s | 60 |
| Registration (`/auth/register`) | 0.5 req/s | 3 |
| Login (`/auth/login`) | 1 req/s | 5 |
| Email actions (verify, forgot password) | 0.2 req/s | 2 |
| Admin login | 0.1 req/s | 2 |
| Waitlist signup | 0.2 req/s | 3 |

When a rate limit is exceeded, the server responds with HTTP 429 and a `Retry-After` header indicating how many seconds to wait.
