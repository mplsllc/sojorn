#!/bin/bash
# Fix FCM configuration and restart backend
# Run with: bash fix_fcm_and_restart.sh

echo "=== Fixing FCM Configuration ==="

# Kill old backend process
echo "Killing old backend process on port 8080..."
sudo kill -9 $(sudo lsof -ti:8080) 2>/dev/null || echo "No process to kill"

# Verify Firebase JSON exists
if [ -f "/opt/sojorn/firebase-service-account.json" ]; then
    echo "✓ Firebase service account JSON exists"
    ls -lh /opt/sojorn/firebase-service-account.json
else
    echo "✗ Firebase service account JSON not found!"
    exit 1
fi

# Add FIREBASE_CREDENTIALS_FILE to .env if not present
if ! grep -q "FIREBASE_CREDENTIALS_FILE" /opt/sojorn/.env; then
    echo "Adding FIREBASE_CREDENTIALS_FILE to .env..."
    echo "" | sudo tee -a /opt/sojorn/.env > /dev/null
    echo "FIREBASE_CREDENTIALS_FILE=/opt/sojorn/firebase-service-account.json" | sudo tee -a /opt/sojorn/.env > /dev/null
    echo "✓ Added FIREBASE_CREDENTIALS_FILE"
else
    echo "✓ FIREBASE_CREDENTIALS_FILE already in .env"
fi

# Restart backend
echo ""
echo "=== Restarting Backend ==="
sudo systemctl restart sojorn-api
sleep 3

# Check status
sudo systemctl status sojorn-api --no-pager | head -20

echo ""
echo "=== Checking FCM Initialization ==="
sudo journalctl -u sojorn-api --since "30 seconds ago" | grep -i "push\|fcm\|firebase" || echo "No FCM logs yet"

echo ""
echo "=== Done! ==="
echo "If you see 'Server started on port 8080' with no errors, FCM is working!"
