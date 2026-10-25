#!/bin/bash
set -e

# Update packages and install Apache HTTP server and cronie
dnf update -y
dnf install -y httpd cronie

# Ensure log file exists with proper permissions
touch /var/log/cv-sync.log
chmod 644 /var/log/cv-sync.log

# Deploy sync script
cat << 'EOF' > /usr/local/bin/sync-cv.sh
#!/bin/bash
set -e

BUCKET="cv-23l-3055"
WEB_ROOT="/var/www/html"
LOG_FILE="/var/log/cv-sync.log"

# Get instance ID via IMDSv2
TOKEN=$(curl -s -S -f -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
if [ -n "$TOKEN" ]; then
    INSTANCE_ID=$(curl -s -S -f -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")
else
    INSTANCE_ID="unknown"
fi

mkdir -p "$WEB_ROOT"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if aws s3 sync "s3://${BUCKET}/site/" "$WEB_ROOT/" --delete; then
    if [ -f "${WEB_ROOT}/index.html" ]; then
        sed -i "s/{{HOSTED_ON}}/EC2 ${INSTANCE_ID}/g" "${WEB_ROOT}/index.html"
    fi
    chmod -R 755 "$WEB_ROOT"
    echo "[$TIMESTAMP] sync successful (instance: ${INSTANCE_ID})" >> "$LOG_FILE"
else
    EXIT_CODE=$?
    echo "[$TIMESTAMP] sync failed with status ${EXIT_CODE}" >> "$LOG_FILE"
fi
EOF

chmod +x /usr/local/bin/sync-cv.sh

# Setup cron schedule (every 5 minutes)
echo "*/5 * * * * root /usr/local/bin/sync-cv.sh" > /etc/cron.d/cv-sync
chmod 644 /etc/cron.d/cv-sync

# Setup systemd timer for cv-sync (every 5 minutes)
cat << 'EOF' > /etc/systemd/system/cv-sync.service
[Unit]
Description=CV S3 Sync Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat << 'EOF' > /etc/systemd/system/cv-sync.timer
[Unit]
Description=Run CV S3 Sync every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=cv-sync.service

[Install]
WantedBy=timers.target
EOF

# Start services
systemctl daemon-reload
systemctl enable --now httpd
systemctl enable --now crond
systemctl enable --now cv-sync.timer

# Run the sync script once immediately
/usr/local/bin/sync-cv.sh
