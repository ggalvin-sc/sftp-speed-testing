#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\0333[1m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         AUTO-MOUNT SFTP DRIVE SETUP                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please run ./interactive-setup.sh first"
    exit 1
fi

# Get current username
CURRENT_USER=$(whoami)
MOUNT_POINT="/home/$CURRENT_USER/SFTP-Drive"

# Load credentials
SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

echo -e "${BOLD}Configuration:${NC}"
echo "  Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "  Mount Point: $MOUNT_POINT"
echo "  Auto-mount: Yes (boot + login)"
echo

# Install sshfs if needed
if ! command -v sshfs &> /dev/null; then
    echo -e "${YELLOW}Installing sshfs...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y sshfs
fi

# Add user to fuse group
echo "Adding $CURRENT_USER to fuse group..."
sudo usermod -aG fuse "$CURRENT_USER"

# Create mount point
echo "Creating mount point..."
mkdir -p "$MOUNT_POINT"

# Create password file for sshfs (secure)
PASS_FILE="/home/$CURRENT_USER/.sftp-pass"
echo "$SFTP_PASSWORD" > "$PASS_FILE"
chmod 600 "$PASS_FILE"

# Create systemd user service for auto-mount on boot
echo "Creating systemd service..."
sudo tee "/etc/systemd/system/sftp-$CURRENT_USER.service" > /dev/null << SVC
[Unit]
Description=SFTP Drive Auto-Mount for $CURRENT_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=$CURRENT_USER
Group=fuse
Environment="DISPLAY=:0"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $CURRENT_USER)/bus"
WorkingDirectory=$HOME
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/sshfs -o password_stdin,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,ConnectTimeout=10 $SFTP_USER@$SFTP_HOST:$SFTP_PORT/ $MOUNT_POINT
ExecStartPost=/bin/bash -c 'notify-send "SFTP Drive" "SFTP Drive mounted at $MOUNT_POINT" || true'
ExecStop=/bin/fusermount -u $MOUNT_POINT
Restart=on-failure
RestartSec=5s
StandardInput=file
StandardInputFile=$PASS_FILE
ForceUnmount=true

[Install]
WantedBy=default.target
SVC

# Enable and start the service
echo "Enabling auto-mount service..."
sudo systemctl daemon-reload
sudo systemctl enable "sftp-$CURRENT_USER.service"

# Create desktop autostart file (for GUI login)
echo "Setting up desktop auto-start..."
mkdir -p "/home/$CURRENT_USER/.config/autostart"
cat > "/home/$CURRENT_USER/.config/autostart/sftp-drive.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=SFTP Drive
Comment=Auto-mount SFTP drive
Exec=bash -c 'sleep 5 && echo "$SFTP_PASSWORD" | /usr/bin/sshfs -o password_stdin,allow_other,reconnect $SFTP_USER@$SFTP_HOST:$SFTP_PORT/ $MOUNT_POINT'
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false
DESKTOP

chmod +x "/home/$CURRENT_USER/.config/autostart/sftp-drive.desktop"

# Create mount/unmount scripts
cat > "/home/$CURRENT_USER/mount-sftp.sh" << 'MOUNTSCRIPT'
#!/bin/bash
MOUNT_POINT="$HOME/SFTP-Drive"
mkdir -p "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
    DIR="$(cd "$(dirname "$0")" && pwd)"
    cd "$DIR"
    if [ -f .env ]; then
        SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")
        echo "$SFTP_PASSWORD" | sshfs -o password_stdin,allow_other,reconnect root@209.159.145.206:/ "$MOUNT_POINT"
        echo "✓ SFTP Drive mounted at $MOUNT_POINT"
        notify-send "SFTP Drive" "Mounted at $MOUNT_POINT" 2>/dev/null || true
    fi
else
    echo "✓ Already mounted at $MOUNT_POINT"
fi
MOUNTSCRIPT

chmod +x "/home/$CURRENT_USER/mount-sftp.sh"

cat > "/home/$CURRENT_USER/unmount-sftp.sh" << 'UNMOUNTSCRIPT'
#!/bin/bash
MOUNT_POINT="$HOME/SFTP-Drive"
fusermount -u "$MOUNT_POINT"
echo "✓ SFTP Drive unmounted"
UNMOUNTSCRIPT

chmod +x "/home/$CURRENT_USER/unmount-sftp.sh"

echo
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo
echo -e "${BOLD}Auto-mount will now:${NC}"
echo "  • Mount on system boot"
echo "  • Mount when you login to desktop"
echo "  • Auto-reconnect if connection drops"
echo
echo -e "${BOLD}Drive location:${NC} $MOUNT_POINT"
echo
echo -e "${BOLD}Manual controls:${NC}"
echo "  Mount now:    /home/$CURRENT_USER/mount-sftp.sh"
echo "  Unmount:      /home/$CURRENT_USER/unmount-sftp.sh"
echo "  Start service: systemctl --user start sftp-$CURRENT_USER.service"
echo "  Stop service:  systemctl --user stop sftp-$CURRENT_USER.service"
echo
echo -e "${YELLOW}⚠ You need to logout and login for changes to take effect${NC}"
echo -e "${YELLOW}  Or run: newgrp fuse${NC}"
echo
echo -e "${BOLD}After login:${NC}"
echo "  • Open Nautilus/File Manager"
echo "  • 'SFTP-Drive' will appear in sidebar"
echo "  • Drag & drop files like a local drive"
