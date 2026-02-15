#!/bin/bash
set -e

echo "=== Sojorn Admin Panel Server Deployment ==="

# 1. Run DB migration
echo "--- Running DB migration ---"
export PGPASSWORD="${PGPASSWORD:?Set PGPASSWORD before running this script}"

psql -U postgres -h localhost -d sojorn <<'EOSQL'
-- Algorithm configuration table
CREATE TABLE IF NOT EXISTS public.algorithm_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default algorithm config values
INSERT INTO public.algorithm_config (key, value, description) VALUES
    ('feed_recency_weight', '0.4', 'Weight for post recency in feed ranking'),
    ('feed_engagement_weight', '0.3', 'Weight for engagement metrics (likes, comments)'),
    ('feed_harmony_weight', '0.2', 'Weight for author harmony/trust score'),
    ('feed_diversity_weight', '0.1', 'Weight for content diversity in feed'),
    ('moderation_auto_flag_threshold', '0.7', 'AI score threshold for auto-flagging content'),
    ('moderation_auto_remove_threshold', '0.95', 'AI score threshold for automatic content removal'),
    ('moderation_greed_keyword_threshold', '0.7', 'Keyword-based spam/greed detection threshold'),
    ('feed_max_posts_per_author', '3', 'Max posts from same author in a single feed page'),
    ('feed_boost_mutual_follow', '1.5', 'Multiplier boost for posts from mutual follows'),
    ('feed_beacon_boost', '1.2', 'Multiplier boost for beacon posts in nearby feeds')
ON CONFLICT (key) DO NOTHING;

-- Audit log table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id UUID,
    details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_id ON public.audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.audit_log(action);

-- Ensure profiles.role column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT NOT NULL DEFAULT 'user';
    END IF;
END $$;

-- Ensure profiles.is_verified column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'is_verified'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Ensure profiles.is_private column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'is_private'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_private BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Ensure users.status column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'status'
    ) THEN
        ALTER TABLE public.users ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
    END IF;
END $$;

-- Ensure users.last_login column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'last_login'
    ) THEN
        ALTER TABLE public.users ADD COLUMN last_login TIMESTAMPTZ;
    END IF;
END $$;
EOSQL

echo "--- DB migration complete ---"

# 2. Check/install Node.js
echo "--- Checking Node.js ---"
if ! command -v node &> /dev/null; then
    echo "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
    sudo apt-get install -y nodejs
fi
echo "Node: $(node --version), npm: $(npm --version)"

# 3. Pull latest code
echo "--- Pulling latest code ---"
cd /opt/sojorn
git pull origin main || echo "Git pull skipped (may not be configured)"

# 4. Build Go backend
echo "--- Building Go backend ---"
cd /opt/sojorn/go-backend
go build -ldflags="-s -w" -o /opt/sojorn/bin/api ./cmd/api/main.go
echo "Go backend built successfully"

# 5. Restart Go backend
echo "--- Restarting Go backend ---"
sudo systemctl restart sojorn-api
sleep 3
sudo systemctl status sojorn-api --no-pager || true

# 6. Setup admin frontend
echo "--- Setting up admin frontend ---"
mkdir -p /opt/sojorn/admin
cd /opt/sojorn/admin

# Check if package.json exists (code should be pulled via git)
if [ ! -f package.json ]; then
    echo "Admin frontend source not found at /opt/sojorn/admin"
    echo "Please ensure the admin/ directory is in the git repo and pulled"
    exit 1
fi

npm install --production=false
npx next build

echo "--- Admin frontend built ---"

# 7. Create .env.local for admin
cat > /opt/sojorn/admin/.env.local <<'EOF'
NEXT_PUBLIC_API_URL=https://api.sojorn.net
EOF

# 8. Create systemd service for admin
sudo tee /etc/systemd/system/sojorn-admin.service > /dev/null <<'EOF'
[Unit]
Description=Sojorn Admin Panel
After=network.target sojorn-api.service

[Service]
Type=simple
User=patrick
Group=patrick
WorkingDirectory=/opt/sojorn/admin
ExecStart=/usr/bin/npx next start --port 3001
Restart=always
RestartSec=5
Environment=NODE_ENV=production
EnvironmentFile=/opt/sojorn/admin/.env.local

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sojorn-admin
sudo systemctl restart sojorn-admin
sleep 3
sudo systemctl status sojorn-admin --no-pager || true

# 9. Setup Nginx
echo "--- Setting up Nginx for admin ---"
sudo tee /etc/nginx/sites-available/sojorn-admin > /dev/null <<'EOF'
server {
    listen 80;
    server_name admin.sojorn.net;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Enable site if not already
if [ ! -L /etc/nginx/sites-enabled/sojorn-admin ]; then
    sudo ln -s /etc/nginx/sites-available/sojorn-admin /etc/nginx/sites-enabled/
fi

sudo nginx -t
sudo systemctl reload nginx

echo "=== Deployment complete! ==="
echo "Admin panel running on port 3001"
echo "Nginx configured for admin.sojorn.net"
echo ""
echo "NEXT STEPS:"
echo "1. Point admin.sojorn.net DNS A record to this server IP"
echo "2. Run: sudo certbot --nginx -d admin.sojorn.net"
echo "3. Set an admin user: psql -U postgres -h localhost -d sojorn -c \"UPDATE profiles SET role = 'admin' WHERE handle = 'your_handle';\""
