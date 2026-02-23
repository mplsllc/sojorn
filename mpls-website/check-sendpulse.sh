#!/bin/bash
set -a
source /opt/sojorn/mpls-website/.env 2>/dev/null
set +a

TOKEN=$(curl -s -X POST https://api.sendpulse.com/oauth/access_token \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"client_credentials","client_id":"'"$SENDPULSE_ID"'","client_secret":"'"$SENDPULSE_SECRET"'"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token","FAILED"))')

echo "Token: ${TOKEN:0:10}..."

echo "=== Address Books ==="
curl -s -H "Authorization: Bearer $TOKEN" "https://api.sendpulse.com/addressbooks" \
  | python3 << 'PYEOF'
import sys,json
data=json.load(sys.stdin)
for b in data:
    bid = b['id']
    bname = b['name']
    bcount = b.get('all_email_qty', 0)
    print('  ID=%s name=%s emails=%s' % (bid, bname, bcount))
PYEOF

echo "=== Emails in book 568090 ==="
curl -s -H "Authorization: Bearer $TOKEN" "https://api.sendpulse.com/addressbooks/568090/emails" \
  | python3 << 'PYEOF'
import sys,json
data=json.load(sys.stdin)
if isinstance(data, list):
    print('Total: %d' % len(data))
    for e in data[:15]:
        print('  %s' % e.get('email', '?'))
else:
    print('Response:', data)
PYEOF
