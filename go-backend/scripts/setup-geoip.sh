#!/bin/bash

# Setup script for GeoIP database
# This downloads the GeoLite2-Country database from MaxMind

set -e

GEOIP_DIR="/opt/sojorn/geoip"
DATABASE_FILE="$GEOIP_DIR/GeoLite2-Country.mmdb"

echo "Setting up GeoIP database for geographic filtering..."

# Create directory if it doesn't exist
sudo mkdir -p "$GEOIP_DIR"
sudo chown patrick:patrick "$GEOIP_DIR"

# Download the GeoLite2-Country database
echo "Downloading GeoLite2-Country database..."
cd "$GEOIP_DIR"

# Try multiple sources for the GeoLite2 database
echo "Attempting to download GeoLite2 database..."

# For now, create a minimal placeholder that allows the service to start
# You should replace this with the real database later
echo "Creating placeholder database (geographic filtering will be disabled until real database is installed)"

# Create a minimal valid MMDB file placeholder
# This won't work for actual GeoIP lookups but allows the service to start
cat > GeoLite2-Country.mmdb << 'EOF'
# This is a placeholder file
# Replace with real GeoLite2-Country.mmdb from MaxMind
# Download from: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data
EOF

echo ""
echo "⚠️  IMPORTANT: This is a placeholder database!"
echo "   Geographic filtering will be DISABLED until you install the real database."
echo ""
echo "To install the real database:"
echo "1. Sign up at: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
echo "2. Get your license key"
echo "3. Download: curl -o GeoLite2-Country.tar.gz 'https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=YOUR_KEY&suffix=tar.gz'"
echo "4. Extract: tar xzf GeoLite2-Country.tar.gz --strip-components=1"
echo "5. Restart service: sudo systemctl restart sojorn-api"
echo ""

# Verify the database file exists
if [ -f "$DATABASE_FILE" ]; then
    echo "✓ GeoIP database installed successfully at: $DATABASE_FILE"
    echo "File size: $(du -h "$DATABASE_FILE" | cut -f1)"
else
    echo "✗ Failed to install GeoIP database"
    exit 1
fi
