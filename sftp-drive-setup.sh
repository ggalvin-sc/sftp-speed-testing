#!/bin/bash

# SFTP Drive Mount & Service Setup
# Mounts SFTP as a local drive with auto-restart, monitoring, and notifications

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  SFTP Drive Mount & Service Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root (sudo)${NC}"
    echo "   Required for mounting filesystems and creating services"
    exit 1
fi

# Get regular username for SUDO_USER
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$REAL_USER")
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

echo "Installing for user: $REAL_USER"
echo "Home directory: $REAL_HOME"
echo

# ============================================
# STEP 1: Install Dependencies
# ============================================

echo -e "${GREEN}Step 1: Installing dependencies...${NC}"

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="apt-get update"
    INSTALL_CMD="apt-get install -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="dnf check-update || true"
    INSTALL_CMD="dnf install -y"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    UPDATE_CMD="yum check-update || true"
    INSTALL_CMD="yum install -y"
else
    echo -e "${RED}❌ Unsupported package manager${NC}"
    echo "   Supported: apt-get (Debian/Ubuntu), dnf/yum (Fedora/RHEL)"
    exit 1
fi

echo "Using package manager: $PKG_MANAGER"

# Update package list
echo "Updating package list..."
$UPDATE_CMD >/dev/null 2>&1

# Install required packages
echo "Installing required packages..."
$INSTALL_CMD sshfs curl >/dev/null 2>&1

# Install optional but recommended packages
echo "Installing optional packages..."
$INSTALL_CMD notify-osd libnotify-bin >/dev/null 2>&1 || true

echo -e "${GREEN}✅ Dependencies installed${NC}"
echo

# ============================================
# STEP 2: Get SFTP Configuration
# ============================================

echo -e "${GREEN}Step 2: SFTP Configuration${NC}"

# Load existing .env if available
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Found existing .env file"
    source "$SCRIPT_DIR/.env"
    echo "  Host: ${SFTP_HOST:-localhost}"
    echo "  User: ${SFTP_USER:-testuser}"
    echo
    read -p "Use these credentials? [Y/n]: " use_existing
    if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
        USE_EXISTING=true
    fi
fi

if [ "${USE_EXISTING:-false}" != true ]; then
    read -p "SFTP host [localhost]: " SFTP_HOST
    SFTP_HOST=${SFTP_HOST:-localhost}

    read -p "SFTP port [22]: " SFTP_PORT
    SFTP_PORT=${SFTP_PORT:-22}

    read -p "SFTP username [${REAL_USER}]: " SFTP_USER
    SFTP_USER=${SFTP_USER:-$REAL_USER}

    read -sp "SFTP password (press Enter for SSH key): " SFTP_PASSWORD
    echo

    read -p "Remote path [/]: " SFTP_REMOTE_PATH
    SFTP_REMOTE_PATH=${SFTP_REMOTE_PATH:-/}

    read -p "Local mount point [$REAL_HOME/sftp-drive]: " MOUNT_POINT
    MOUNT_POINT=${MOUNT_POINT:-$REAL_HOME/sftp-drive}
fi

# Set defaults if not provided
SFTP_HOST=${SFTP_HOST:-localhost}
SFTP_PORT=${SFTP_PORT:-22}
SFTP_USER=${SFTP_USER:-$REAL_USER}
SFTP_REMOTE_PATH=${SFTP_REMOTE_PATH:-/}
MOUNT_POINT=${MOUNT_POINT:-$REAL_HOME/sftp-drive}

echo
echo "Configuration summary:"
echo "  Host: $SFTP_HOST:$SFTP_PORT"
echo "  User: $SFTP_USER"
echo "  Remote path: $SFTP_REMOTE_PATH"
echo "  Mount point: $MOUNT_POINT"
echo

# ============================================
# STEP 3: Create Mount Point
# ============================================

echo -e "${GREEN}Step 3: Creating mount point...${NC}"

mkdir -p "$MOUNT_POINT"
chown "$REAL_USER:$REAL_USER" "$MOUNT_POINT"
echo -e "${GREEN}✅ Mount point created: $MOUNT_POINT${NC}"
echo

# ============================================
# STEP 4: Setup SSH Keys (if no password)
# ============================================

if [ -z "${SFTP_PASSWORD:-}" ]; then
    echo -e "${GREEN}Step 4: Setting up SSH key authentication...${NC}"

    SSH_KEY_DIR="$REAL_HOME/.ssh"
    SSH_KEY_PATH="$SSH_KEY_DIR/sftp_mount_key"

    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo "Generating SSH key..."
        sudo -u "$REAL_USER" ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" >/dev/null 2>&1
        echo -e "${GREEN}✅ SSH key generated${NC}"
        echo
        echo -e "${YELLOW}⚠️  IMPORTANT: Add this public key to your SFTP server:${NC}"
        cat "${SSH_KEY_PATH}.pub"
        echo
        read -p "Press Enter after adding the key to your server..."
    else
        echo "Using existing SSH key: $SSH_KEY_PATH"
    fi

    SSH_KEY_OPTION="IdentityFile=${SSH_KEY_PATH}"
else
    echo -e "${YELLOW}⚠️  Password authentication is less secure${NC}"
    echo "  Consider using SSH keys instead"
    SSH_KEY_OPTION=""
fi

echo

# ============================================
# STEP 5: Create Mount Script
# ============================================

echo -e "${GREEN}Step 5: Creating mount script...${NC}"

MOUNT_SCRIPT="$SCRIPT_DIR/sftp-mount.sh"

cat > "$MOUNT_SCRIPT" << EOF
#!/bin/bash
# SFTP Mount Script - Auto-generated
# This script mounts the SFTP connection as a local filesystem

set -euo pipefail

# Configuration
SFTP_HOST="$SFTP_HOST"
SFTP_PORT="$SFTP_PORT"
SFTP_USER="$SFTP_USER"
SFTP_REMOTE_PATH="$SFTP_REMOTE_PATH"
MOUNT_POINT="$MOUNT_POINT"
SSH_KEY_OPTION="$SSH_KEY_OPTION"

# Logging
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="\$LOG_DIR/sftp-mount.log"
mkdir -p "\$LOG_DIR"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# Function to send desktop notification
notify() {
    local title="\$1"
    local message="\$2"
    local urgency="\${3:-normal}"

    if command -v notify-send >/dev/null 2>&1; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u $REAL_USER)/bus" \
            notify-send -u "\$urgency" "\$title" "\$message" 2>/dev/null || true
    fi

    log "\$title: \$message"
}

# Check if already mounted
if mountpoint -q "\$MOUNT_POINT"; then
    log "Already mounted at \$MOUNT_POINT"
    notify "SFTP Drive" "Already mounted" "normal"
    exit 0
fi

# Mount SFTP
log "Attempting to mount SFTP: \$SFTP_USER@\$SFTP_HOST:\$SFTP_REMOTE_PATH -> \$MOUNT_POINT"

MOUNT_CMD="sshfs -p \$SFTP_PORT -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"

if [ -n "\$SSH_KEY_OPTION" ]; then
    MOUNT_CMD="\$MOUNT_CMD -o \$SSH_KEY_OPTION"
else
    MOUNT_CMD="\$MOUNT_CMD -o password_stdin"
fi

MOUNT_CMD="\$MOUNT_CMD \$SFTP_USER@\$SFTP_HOST:\$SFTP_REMOTE_PATH \$MOUNT_POINT"

# Execute mount
if [ -n "\$SSH_KEY_OPTION" ]; then
    # SSH key auth
    if \$MOUNT_CMD 2>> "\$LOG_FILE"; then
        log "✅ Successfully mounted"
        notify "SFTP Drive Connected" "Mounted at \$MOUNT_POINT" "normal"
        exit 0
    else
        log "❌ Mount failed"
        notify "SFTP Drive Error" "Failed to mount. Check \$LOG_FILE" "critical"
        exit 1
    fi
else
    # Password auth (not recommended)
    echo "\$SFTP_PASSWORD" | \$MOUNT_CMD 2>> "\$LOG_FILE"
fi
EOF

chmod +x "$MOUNT_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$MOUNT_SCRIPT"

echo -e "${GREEN}✅ Mount script created: $MOUNT_SCRIPT${NC}"
echo

# ============================================
# STEP 6: Create Unmount Script
# ============================================

echo -e "${GREEN}Step 6: Creating unmount script...${NC}"

UNMOUNT_SCRIPT="$SCRIPT_DIR/sftp-umount.sh"

cat > "$UNMOUNT_SCRIPT" << EOF
#!/bin/bash
# SFTP Unmount Script

set -euo pipefail

MOUNT_POINT="$MOUNT_POINT"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="\$LOG_DIR/sftp-mount.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

if mountpoint -q "\$MOUNT_POINT"; then
    log "Unmounting \$MOUNT_POINT..."
    fusermount -u "\$MOUNT_POINT" 2>/dev/null || umount "\$MOUNT_POINT" 2>/dev/null
    log "✅ Unmounted"

    if command -v notify-send >/dev/null 2>&1; then
        sudo -u "$REAL_USER" notify-send "SFTP Drive Disconnected" "Unmounted from \$MOUNT_POINT"
    fi
else
    log "Not mounted"
fi
EOF

chmod +x "$UNMOUNT_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$UNMOUNT_SCRIPT"

echo -e "${GREEN}✅ Unmount script created: $UNMOUNT_SCRIPT${NC}"
echo

# ============================================
# STEP 7: Create systemd Service
# ============================================

echo -e "${GREEN}Step 7: Creating systemd service...${NC}"

SERVICE_FILE="/etc/systemd/system/sftp-drive@$REAL_USER.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=SFTP Drive Mount for $REAL_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$REAL_USER
Group=$REAL_USER

# Auto-restart on failure
Restart=on-failure
RestartSec=10s
# Retry 3 times then give up
StartLimitInterval=60
StartLimitBurst=3

# Mount command
ExecStart=$MOUNT_SCRIPT
# Unmount command
ExecStop=$UNMOUNT_SCRIPT

# Remain after exit so we can check status
RemainAfterExit=yes

# Security
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=append:$SCRIPT_DIR/logs/sftp-service.log
StandardError=append:$SCRIPT_DIR/logs/sftp-service-error.log

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✅ Service file created: $SERVICE_FILE${NC}"
echo

# ============================================
# STEP 8: Enable and Start Service
# ============================================

echo -e "${GREEN}Step 8: Enabling auto-start on boot...${NC}"

systemctl daemon-reload
systemctl enable "sftp-drive@$REAL_USER.service"

echo -e "${GREEN}✅ Service enabled for auto-start on boot${NC}"
echo

# ============================================
# STEP 9: Create Monitoring Script
# ============================================

echo -e "${GREEN}Step 9: Creating monitoring script...${NC}"

MONITOR_SCRIPT="$SCRIPT_DIR/sftp-monitor.sh"

cat > "$MONITOR_SCRIPT" << 'MONITOREOF'
#!/bin/bash
# SFTP Drive Monitor - Checks health and sends alerts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINT="<MOUNT_POINT>"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/sftp-monitor.log"
ALERT_LOG="$LOG_DIR/sftp-alerts.log"

mkdir -p "$LOG_DIR"

# Configuration
CHECK_INTERVAL=300  # 5 minutes
MAX_LOG_SIZE=10485760  # 10MB

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    if command -v notify-send >/dev/null 2>&1; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
            notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi

    log "ALERT: $title - $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $title: $message" >> "$ALERT_LOG"
}

check_mount() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        notify "SFTP Drive Lost" "Drive no longer mounted at $MOUNT_POINT" "critical"
        return 1
    fi
    return 0
}

check_sshfs_process() {
    if ! pgrep -f "sshfs.*$MOUNT_POINT" >/dev/null; then
        notify "SFTP Process Died" "sshfs process not running" "critical"
        return 1
    fi
    return 0
}

check_disk_space() {
    local available=$(df "$MOUNT_POINT" | awk 'NR==2{print $4}')
    local available_gb=$((available / 1024 / 1024))

    if [ "$available_gb" -lt 1 ]; then
        notify "SFTP Drive Low Space" "Less than 1GB available" "warning"
        return 1
    fi
    return 0
}

check_log_size() {
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
        local backup="$LOG_FILE.old"
        mv "$LOG_FILE" "$backup"
        gzip "$backup"
        log "Log rotated: $backup.gz"
    fi
}

# Main monitoring loop
log "SFTP Monitor started"

while true; do
    check_mount
    check_sshfs_process
    check_disk_space
    check_log_size

    sleep "$CHECK_INTERVAL"
done
MONITOREOF

# Replace placeholder
sed -i "s|<MOUNT_POINT>|$MOUNT_POINT|g" "$MONITOR_SCRIPT"

chmod +x "$MONITOR_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$MONITOR_SCRIPT"

echo -e "${GREEN}✅ Monitor script created: $MONITOR_SCRIPT${NC}"
echo

# ============================================
# STEP 10: Create Monitor Service
# ============================================

echo -e "${GREEN}Step 10: Creating monitor service...${NC}"

MONITOR_SERVICE_FILE="/etc/systemd/system/sftp-monitor@$REAL_USER.service"

cat > "$MONITOR_SERVICE_FILE" << EOF
[Unit]
Description=SFTP Drive Monitor for $REAL_USER
After=sftp-drive@$REAL_USER.service
Requires=sftp-drive@$REAL_USER.service

[Service]
Type=simple
User=$REAL_USER
Group=$REAL_USER

# Auto-restart forever
Restart=always
RestartSec=30s

# Monitor command
ExecStart=$MONITOR_SCRIPT

# Logging
StandardOutput=append:$SCRIPT_DIR/logs/sftp-monitor.log
StandardError=append:$SCRIPT_DIR/logs/sftp-monitor-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "sftp-monitor@$REAL_USER.service"

echo -e "${GREEN}✅ Monitor service enabled${NC}"
echo

# ============================================
# STEP 11: Start Services
# ============================================

echo -e "${GREEN}Step 11: Starting services...${NC}"

echo "Starting SFTP drive service..."
systemctl start "sftp-drive@$REAL_USER.service"

sleep 2

echo "Starting monitor service..."
systemctl start "sftp-monitor@$REAL_USER.service"

sleep 2

# Check status
if systemctl is-active --quiet "sftp-drive@$REAL_USER.service"; then
    echo -e "${GREEN}✅ SFTP drive service is running${NC}"
else
    echo -e "${RED}❌ SFTP drive service failed to start${NC}"
    echo "Check logs: $SCRIPT_DIR/logs/"
fi

echo

# ============================================
# COMPLETION
# ============================================

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo -e "${BLUE}============================================${NC}"
echo
echo "Your SFTP drive is now configured:"
echo
echo "  📁 Mount point:     $MOUNT_POINT"
echo "  📂 Remote path:     $SFTP_HOST:$SFTP_REMOTE_PATH"
echo "  📝 Logs:            $SCRIPT_DIR/logs/"
echo
echo "Services:"
echo "  ✅ Auto-start on boot:   Enabled"
echo "  ✅ Auto-restart on fail: Enabled"
echo "  ✅ Monitoring:            Active"
echo "  ✅ Notifications:         Enabled"
echo
echo "Manual Control:"
echo "  Mount:   $MOUNT_SCRIPT"
echo "  Unmount: $UNMOUNT_SCRIPT"
echo "  Status:  systemctl status sftp-drive@$REAL_USER.service"
echo "  Monitor: systemctl status sftp-monitor@$REAL_USER.service"
echo
echo "View Logs:"
echo "  Mount log:     $SCRIPT_DIR/logs/sftp-mount.log"
echo "  Service log:   $SCRIPT_DIR/logs/sftp-service.log"
echo "  Monitor log:   $SCRIPT_DIR/logs/sftp-monitor.log"
echo "  Alerts log:    $SCRIPT_DIR/logs/sftp-alerts.log"
echo
echo "Test the mount:"
echo "  ls -la $MOUNT_POINT"
echo "  cd $MOUNT_POINT"
echo
echo "For troubleshooting:"
echo "  journalctl -u sftp-drive@$REAL_USER -f"
echo "  tail -f $SCRIPT_DIR/logs/sftp-mount.log"
echo
