#!/bin/bash

print_box() {
    local s="$1"
    local length=${#s}
    local padding=5
    local total_length=$((length + 2 * padding))
    local border=$(printf '%*s' "$total_length" | tr ' ' '#')
    
    echo "$border"
    printf "#%*s%-*s%*s#\n" $padding '' $length "$s" $padding ''
    echo "$border"
}

print_box "INSTALLATION BEGINS"

# Update and install necessary packages
sudo apt-get update
sudo apt-get install -y net-tools docker.io nginx

# Create log directory and file
LOG_DIR="/var/log/devopsfetch"
LOG_FILE="$LOG_DIR/devopsfetch.log"

if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
fi
sudo touch "$LOG_FILE"
sudo chown -R $USER:$USER "$LOG_DIR"
sudo chmod 666 "$LOG_FILE"

# Copy the devopsfetch script to /usr/local/bin
DEVOPSFETCH_SCRIPT_PATH="/usr/local/bin/devopsfetch"
sudo cp devopsfetch.sh "$DEVOPSFETCH_SCRIPT_PATH"
sudo chmod +x "$DEVOPSFETCH_SCRIPT_PATH"

# Set up log rotation
cat << EOF | sudo tee /etc/logrotate.d/devopsfetch > /dev/null
$LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        systemctl restart devopsfetch.service > /dev/null 2>&1 || true
    endscript
}
EOF

# Create and configure systemd service
sudo tee /etc/systemd/system/devopsfetch.service > /dev/null <<EOF
[Unit]
Description=DevOps Fetch Service
After=network.target

[Service]
ExecStart=/usr/local/bin/devopsfetch --monitor
WorkingDirectory=/usr/local/bin
StandardOutput=append:/var/log/devopsfetch/devopsfetch.log
StandardError=append:/var/log/devopsfetch/devopsfetch.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the service
sudo systemctl daemon-reload

sudo systemctl enable devopsfetch.service

sudo systemctl start devopsfetch.service
print_box "SERVICE STARTED"


