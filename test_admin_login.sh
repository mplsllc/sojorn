#!/bin/bash

# Test admin login with admin@sojorn.net (primary admin)
echo "Testing admin login with admin@sojorn.net..."

curl -X POST http://localhost:8080/api/v1/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@sojorn.net",
    "password": "password123",
    "turnstile_token": "BYPASS_DEV_MODE"
  }' | jq .

echo ""
echo "Testing admin login with admin@mp.ls..."

curl -X POST http://localhost:8080/api/v1/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@mp.ls", 
    "password": "password123",
    "turnstile_token": "BYPASS_DEV_MODE"
  }' | jq .
