#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP DRIVE MOUNTING WIZARD                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Load credentials
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please run interactive-setup.sh first"
    exit 1
fi

SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

# Get current username (the non-root user who ran sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
MOUNT_POINT="/home/$REAL_USER/SFTP-Drive"

echo -e "${BOLD}SFTP Drive Configuration${NC}"
echo "══════════════════════════════════════"
echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "Mount Point: $MOUNT_POINT"
echo "Auto-mount: Yes (on boot and login)"
echo "Desktop Integration: Yes (Nautilus, file manager)"
echo

# Install dependencies if needed
echo -e "${YELLOW}Checking dependencies...${NC}"
if ! command -v sshfs &> /dev/null; then
    echo "Installing sshfs..."
    apt-get update -qq && apt-get install -y sshfs
fi

# Add user to fuse group
echo "Adding $REAL_USER to fuse group..."
usermod -aG fuse "$REAL_USER"

# Create mount point
echo "Creating mount point at $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
chown "$REAL_USER:$REAL_USER" "$MOUNT_POINT"

# Save credentials for SSH (create passwordless SSH)
echo "Setting up SSH key for auto-mount..."
SSH_DIR="/home/$REAL_USER/.ssh"
mkdir -p "$SSH_DIR"
chown -R "$REAL_USER:$REAL_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Create SSH config
cat > "$SSH_DIR/config" << SSHCONFIG
Host sftp-automount
    HostName $SFTP_HOST
    Port $SFTP_PORT
    User $SFTP_USER
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
SSHCONFIG

chmod 600 "$SSH_DIR/config"
chown "$REAL_USER:$REAL_USER" "$SSH_DIR/config"

# Use sshpass to set up password authentication (create a helper script)
mkdir -p /usr/local/bin
cat > /usr/local/bin/sftp-connect << 'SCRIPT'
#!/bin/bash
echo "$SFTP_PASSWORD"
SCRIPT
chmod 500 /usr/local/bin/sftp-connect

# Create systemd user service
echo "Creating systemd service for auto-mount..."
cat > "/etc/systemd/system/sftp-$REAL_USER.service" << SVC
[Unit]
Description=SFTP Drive Mount for $REAL_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=$REAL_USER
Group=fuse
Environment="DISPLAY=:0"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $REAL_USER)/bus"
ExecStart=/usr/bin/sshfs -o password_stdin,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 $SFTP_USER@$SFTP_HOST:$SFTP_PORT/ $MOUNT_POINT
ExecStop=/bin/fusermount -u $MOUNT_POINT
Restart=on-failure
RestartSec=5s
StandardInput=tty
ForceUnmount=true

[Install]
WantedBy=default.target
SVC

# Create auto-mount on login
echo "Setting up desktop auto-mount..."
mkdir -p "/home/$REAL_USER/.config/autostart"
cat > "/home/$REAL_USER/.config/autostart/sftp-mount.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=SFTP Drive
Comment=Auto-mount SFTP drive
Exec=bash -c 'echo "$SFTP_PASSWORD" | /usr/bin/sshfs -o password_stdin,allow_other $SFTP_USER@$SFTP_HOST:$SFTP_PORT/ $MOUNT_POINT'
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false
X-GNOME-AutoStart-enabled=true
DESKTOP

chown "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.config/autostart/sftp-mount.desktop"
chmod +x "/home/$REAL_USER/.config/autostart/sftp-mount.desktop"

# Enable systemd service
systemctl daemon-reload
systemctl enable "sftp-$REAL_USER.service"

echo
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo
echo -e "${BOLD}To mount the drive now:${NC}"
echo "  systemctl --user start sftp-$REAL_USER.service"
echo "  OR simply log out and log back in"
echo
echo -e "${BOLD}Drive Location:${NC}"
echo "  $MOUNT_POINT"
echo
echo -e "${BOLD}Features:${NC}"
echo "  ✓ Auto-mounts on system boot"
echo "  ✓ Auto-mounts on user login"
echo "  ✓ Auto-reconnects if connection drops"
echo "  ✓ Appears in file manager (Nautilus)"
echo "  ✓ Drag & drop files like a local drive"
echo "  ✓ Shows in desktop sidebar"
echo
echo -e "${YELLOW}Note: You may need to log out and log back in for all changes to take effect.${NC}"
