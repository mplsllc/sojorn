#!/bin/bash

# Configuration
APP_NAME="sojorn-api"
INSTALL_DIR="/opt/sojorn"
BINARY_PATH="$INSTALL_DIR/bin/sojorn-api"
SYSTEMD_SERVICE="/etc/systemd/system/$APP_NAME.service"

echo "Stopping sojorn-api service..."
sudo systemctl stop $APP_NAME

echo "Building Sojorn Backend..."
go build -o api ./cmd/api/main.go
go build -o migrate ./cmd/migrate/main.go

echo "Preparing installation directory..."
sudo mkdir -p $INSTALL_DIR/bin
sudo cp api $BINARY_PATH
sudo cp migrate $INSTALL_DIR/bin/migrate
sudo cp .env $INSTALL_DIR/.env

echo "Setting up Systemd service..."
sudo tee $SYSTEMD_SERVICE <<EOF
[Unit]
Description=Sojorn Golang API Server
After=network.target postgresql.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$INSTALL_DIR
ExecStart=$BINARY_PATH
Restart=always
RestartSec=5s
EnvironmentFile=$INSTALL_DIR/.env

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable $APP_NAME
sudo systemctl restart $APP_NAME

echo "Deployment complete!"
