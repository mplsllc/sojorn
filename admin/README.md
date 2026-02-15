# Sojorn Admin Panel

Secure administration frontend for the Sojorn social network platform.

## Features

- **Dashboard** — Real-time platform stats, user/post growth charts, quick actions
- **User Management** — Search, view, suspend, ban, verify, change roles, reset strikes
- **Post Management** — Browse, search, flag, remove, restore, view details
- **AI Moderation Queue** — Review AI-flagged content (OpenAI + Google Vision), approve/dismiss/remove/ban
- **Appeal System** — Full appeal workflow: review violations, approve/reject appeals, restore content
- **Reports** — Community reports management with action/dismiss workflow
- **Algorithm Settings** — Configure feed ranking weights and AI moderation thresholds
- **Categories** — Create, edit, manage content categories
- **System Health** — Database status, connection pool monitoring, audit log

## Tech Stack

- **Framework**: Next.js 14 (App Router)
- **Language**: TypeScript
- **Styling**: TailwindCSS
- **Charts**: Recharts
- **Icons**: Lucide React
- **Backend**: Go (Gin) REST API at `api.sojorn.net`

## Setup

```bash
# Install dependencies
npm install

# Configure API endpoint
cp .env.local.example .env.local
# Edit NEXT_PUBLIC_API_URL if needed

# Run development server
npm run dev
```

The admin panel runs on **port 3001** by default.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXT_PUBLIC_API_URL` | `https://api.sojorn.net` | Backend API base URL |

## Authentication

The admin panel uses the same JWT authentication as the main app. Users must have `role = 'admin'` in the `profiles` table to access admin endpoints.

### Setting up an admin user

```sql
-- On the VPS, connect to sojorn database
UPDATE profiles SET role = 'admin' WHERE handle = 'your_handle';
```

## Backend API Routes

All admin endpoints are under `/api/v1/admin/` and require:
1. Valid JWT token (Bearer auth)
2. User profile with `role = 'admin'`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/admin/dashboard` | Platform stats |
| GET | `/admin/growth` | User/post growth data |
| GET | `/admin/users` | List users (search, filter) |
| GET | `/admin/users/:id` | User detail |
| PATCH | `/admin/users/:id/status` | Change user status |
| PATCH | `/admin/users/:id/role` | Change user role |
| PATCH | `/admin/users/:id/verification` | Toggle verification |
| POST | `/admin/users/:id/reset-strikes` | Reset strikes |
| GET | `/admin/posts` | List posts |
| GET | `/admin/posts/:id` | Post detail |
| PATCH | `/admin/posts/:id/status` | Change post status |
| DELETE | `/admin/posts/:id` | Delete post |
| GET | `/admin/moderation` | Moderation queue |
| PATCH | `/admin/moderation/:id/review` | Review flagged content |
| GET | `/admin/appeals` | List appeals |
| PATCH | `/admin/appeals/:id/review` | Review appeal |
| GET | `/admin/reports` | List reports |
| PATCH | `/admin/reports/:id` | Update report status |
| GET | `/admin/algorithm` | Get algorithm config |
| PUT | `/admin/algorithm` | Update algorithm config |
| GET | `/admin/categories` | List categories |
| POST | `/admin/categories` | Create category |
| PATCH | `/admin/categories/:id` | Update category |
| GET | `/admin/health` | System health check |
| GET | `/admin/audit-log` | Audit log |

## Deployment

```bash
# Build for production
npm run build

# Start production server
npm start
```

For production, serve behind Nginx with SSL. Add a server block for `admin.sojorn.net`:

```nginx
server {
    listen 443 ssl http2;
    server_name admin.sojorn.net;

    ssl_certificate /etc/letsencrypt/live/admin.sojorn.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.sojorn.net/privkey.pem;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

## Moderation Flow

```
Content Created → AI Analysis (OpenAI/Google Vision)
    ↓
Score > threshold → Auto-flag → Moderation Queue
    ↓
Admin reviews → Approve / Dismiss / Remove Content / Ban User
    ↓
If removed → User sees violation → Can file appeal
    ↓
Admin reviews appeal → Approve (restore) / Reject (uphold)
```
