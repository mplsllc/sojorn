#!/bin/bash
# Fix and restart the sojorn-admin service
# Run as: sudo bash /opt/sojorn/admin/fix_service.sh

# 1. Remove old service completely
systemctl stop sojorn-admin 2>/dev/null
systemctl disable sojorn-admin 2>/dev/null

# 2. Kill ANY process on port 3001
fuser -k 3001/tcp 2>/dev/null
sleep 2
# Double check
fuser -k 3001/tcp 2>/dev/null
sleep 1

# 3. Write fresh service file with Restart=on-failure
cat > /etc/systemd/system/sojorn-admin.service <<'SVCEOF'
[Unit]
Description=Sojorn Admin Panel
After=network.target sojorn-api.service

[Service]
Type=simple
User=patrick
Group=patrick
WorkingDirectory=/opt/sojorn/admin
ExecStart=/usr/bin/node /opt/sojorn/admin/node_modules/next/dist/bin/next start --port 3001
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=60
StartLimitBurst=3
Environment=NODE_ENV=production
Environment=NEXT_PUBLIC_API_URL=https://api.sojorn.net

[Install]
WantedBy=multi-user.target
SVCEOF

# 4. Reload and start
systemctl daemon-reload
systemctl enable sojorn-admin
systemctl start sojorn-admin

sleep 4
systemctl status sojorn-admin --no-pager
