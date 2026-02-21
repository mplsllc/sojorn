# Sojorn Admin Panel

Secure administration frontend for the Sojorn social network platform.

## Tech Stack

- **Framework**: Next.js 14 (App Router)
- **Language**: TypeScript
- **Styling**: TailwindCSS
- **Charts**: Recharts
- **Icons**: Lucide React
- **Backend**: Go (Gin) REST API at `api.sojorn.net`

## Features

- **Dashboard** — Real-time platform stats, user/post growth charts, quick actions
- **User Management** — Search, view, suspend, ban, verify, change roles, reset strikes
- **Post Management** — Browse, search, flag, remove, restore, view details
- **Groups & Capsules** — List groups, member management, deactivate, key rotation status
- **Quip Repair** — List missing thumbnails, server-side FFmpeg repair
- **AI Moderation Queue** — Review AI-flagged content (OpenAI + Google Vision), approve/dismiss/remove/ban
- **AI Moderation Config** — Tune thresholds and scoring weights
- **AI Audit Log** — Full history of AI moderation decisions with feedback
- **Appeal System** — Full appeal workflow: review violations, approve/reject appeals, restore content
- **Reports** — Community reports management with action/dismiss workflow
- **Algorithm Settings** — Configure feed ranking weights, cooling period, diversity injection
- **Algorithm Feed Scores** — Live viewer of feed scoring for any post
- **Categories** — Create, edit, manage content categories
- **Neighborhoods** — Manage neighborhood seeds and geographic zones
- **Official Accounts** — Scheduler for official account article posting
- **Content Tools** — Bulk content operations
- **Safety** — Safe domains management, content filter configuration
- **Storage Browser** — Browse Cloudflare R2 media storage
- **System Health** — Database status, connection pool monitoring
- **Settings** — Platform-wide configuration
- **Email Templates** — Manage and test-send email templates
- **Reserved Usernames** — Manage reserved/blocked handles
- **Waitlist** — Manage waitlist entries and invitations
- **Audit Log** — Full admin action history

## Setup

```bash
npm install
cp .env.local.example .env.local
npm run dev
```

The admin panel runs on **port 3001** by default.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXT_PUBLIC_API_URL` | `https://api.sojorn.net` | Backend API base URL |

## Authentication

Uses JWT authentication. Users must have `role = 'admin'` in the `profiles` table.

```sql
UPDATE profiles SET role = 'admin' WHERE handle = 'your_handle';
```

## Deployment

```bash
npm run build && npm start
```

Served behind Nginx with SSL at `admin.sojorn.net`, proxied to port 3001.

## Moderation Flow

```
Content Created → AI Analysis (OpenAI text / Google Vision images)
    ↓
Score > threshold → Auto-flag → Moderation Queue
    ↓
Admin reviews → Approve / Dismiss / Remove Content / Ban User
    ↓
If removed → User notified → Can file appeal
    ↓
Admin reviews appeal → Approve (restore) / Reject (uphold)
```
