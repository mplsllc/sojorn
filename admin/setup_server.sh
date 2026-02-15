#!/bin/bash
set -e

echo "=== Cleaning up all node processes on port 3001 ==="

# Stop and fully remove any existing service
systemctl stop sojorn-admin 2>/dev/null || true
systemctl disable sojorn-admin 2>/dev/null || true

# Kill ALL node processes related to the admin panel
pkill -9 -f "next start --port 3001" 2>/dev/null || true
pkill -9 -f "dist/server/entry.mjs" 2>/dev/null || true
sleep 2

# Double-kill anything left on port 3001
fuser -k 3001/tcp 2>/dev/null || true
sleep 2

# Triple check
STILL_RUNNING=$(fuser 3001/tcp 2>/dev/null || true)
if [ -n "$STILL_RUNNING" ]; then
    echo "Force killing PIDs: $STILL_RUNNING"
    kill -9 $STILL_RUNNING 2>/dev/null || true
    sleep 2
fi

echo "Port 3001 status:"
ss -tlnp | grep 3001 || echo "PORT IS FREE"

echo ""
echo "=== Writing systemd service ==="

cat > /etc/systemd/system/sojorn-admin.service <<'SVCEOF'
[Unit]
Description=Sojorn Admin Panel
After=network.target

[Service]
Type=simple
User=patrick
Group=patrick
WorkingDirectory=/opt/sojorn/admin
ExecStart=/usr/bin/node /opt/sojorn/admin/node_modules/next/dist/bin/next start --port 3001
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=120
StartLimitBurst=3
Environment=NODE_ENV=production
Environment=NEXT_PUBLIC_API_URL=https://api.sojorn.net

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable sojorn-admin
systemctl start sojorn-admin

echo "Waiting 5s for startup..."
sleep 5

echo ""
echo "=== Service status ==="
systemctl status sojorn-admin --no-pager

echo ""
echo "=== Port check ==="
ss -tlnp | grep 3001

echo ""
echo "=== Setting up Nginx ==="

cat > /etc/nginx/sites-available/sojorn-admin <<'NGXEOF'
server {
    listen 80;
    server_name admin.sojorn.net;

    location / {
        proxy_pass http://127.0.0.1:3001;
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
NGXEOF

if [ ! -L /etc/nginx/sites-enabled/sojorn-admin ]; then
    ln -s /etc/nginx/sites-available/sojorn-admin /etc/nginx/sites-enabled/
fi

nginx -t && systemctl reload nginx
echo "Nginx configured and reloaded"

echo ""
echo "=== Checking Go API service ==="
systemctl status sojorn-api --no-pager || true

echo ""
echo "=== DONE ==="
