#!/bin/bash
# Restart backend cleanly
systemctl stop sojorn-api
pkill -9 sojorn-api
sleep 2
systemctl start sojorn-api
sleep 3
echo "=== Backend Status ==="
systemctl status sojorn-api --no-pager | head -15
echo ""
echo "=== FCM Logs ==="
journalctl -u sojorn-api --since "10 seconds ago" | grep -i "server started\|failed\|fcm\|firebase\|push" || echo "No relevant logs"
