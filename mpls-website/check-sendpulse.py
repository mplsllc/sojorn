#!/usr/bin/env python3
import json, urllib.request, os

# Read .env manually
env = {}
with open('/opt/sojorn/mpls-website/.env') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip()

sid = env.get('SENDPULSE_ID', '')
secret = env.get('SENDPULSE_SECRET', '')
print(f'SENDPULSE_ID: {sid[:10]}...')
print(f'SENDPULSE_SECRET: {"set" if secret else "MISSING"}')

if not sid or not secret:
    print('ERROR: Missing credentials')
    exit(1)

# Get OAuth token
req = urllib.request.Request(
    'https://api.sendpulse.com/oauth/access_token',
    data=json.dumps({'grant_type': 'client_credentials', 'client_id': sid, 'client_secret': secret}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST'
)
with urllib.request.urlopen(req) as resp:
    token_data = json.load(resp)
token = token_data['access_token']
print(f'Token: {token[:10]}...')

# List address books
req = urllib.request.Request(
    'https://api.sendpulse.com/addressbooks',
    headers={'Authorization': f'Bearer {token}'}
)
with urllib.request.urlopen(req) as resp:
    books = json.load(resp)
print('\n=== Address Books ===')
for b in books:
    print(f'  ID={b["id"]} name={b["name"]} emails={b.get("all_email_qty", 0)}')

# List emails in book 568090
req = urllib.request.Request(
    'https://api.sendpulse.com/addressbooks/568090/emails',
    headers={'Authorization': f'Bearer {token}'}
)
try:
    with urllib.request.urlopen(req) as resp:
        emails = json.load(resp)
    print(f'\n=== Emails in Sojorn Waitlist (568090) ===')
    if isinstance(emails, list):
        print(f'Total: {len(emails)}')
        for e in emails[:15]:
            print(f'  {e.get("email", "?")} (status={e.get("status", "?")})')
    else:
        print('Response:', emails)
except Exception as ex:
    print(f'Error fetching emails: {ex}')
