#!/bin/bash
cat > /tmp/sojorn-admin.conf << 'EOF'
server {
    listen 80;
    server_name admin.sojorn.net;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

sudo cp /tmp/sojorn-admin.conf /etc/nginx/sites-available/sojorn-admin
sudo ln -sf /etc/nginx/sites-available/sojorn-admin /etc/nginx/sites-enabled/sojorn-admin
sudo nginx -t && sudo systemctl reload nginx
echo "--- Nginx status ---"
sudo systemctl status nginx --no-pager | head -5
echo "--- Testing certbot ---"
sudo certbot --nginx -d admin.sojorn.net --non-interactive --agree-tos --redirect -m admin@sojorn.net
echo "--- Done ---"
