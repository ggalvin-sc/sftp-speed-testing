#!/bin/bash

# Quick SFTP Mount Script
# This will mount your SFTP server as a local drive

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP DRIVE QUICK MOUNT                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo

# Load credentials
SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

MOUNT_POINT="$HOME/casedoxx_server"

echo "Mounting SFTP as local drive..."
echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "Mount point: $MOUNT_POINT"
echo

# Create mount point
mkdir -p "$MOUNT_POINT"

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo "Drive already mounted. Unmounting first..."
    fusermount -u "$MOUNT_POINT" 2>/dev/null || umount "$MOUNT_POINT" 2>/dev/null
    sleep 1
fi

# Mount the drive
echo "Mounting..."
echo "$SFTP_PASSWORD" | sshfs -o password_stdin,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 -p "$SFTP_PORT" "$SFTP_USER@$SFTP_HOST:/" "$MOUNT_POINT"

if [ $? -eq 0 ]; then
    echo
    echo "✓ SUCCESS! Drive mounted at: $MOUNT_POINT"
    echo
    echo "You can now:"
    echo "  • Open Nautilus/File Manager - drive will appear in sidebar"
    echo "  • Drag and drop files to/from the drive"
    echo "  • Access files: cd $MOUNT_POINT"
    echo "  • Browse: ls $MOUNT_POINT"
    echo
    echo "To unmount later: fusermount -u $MOUNT_POINT"
else
    echo
    echo "✗ Mount failed. Check your credentials and connection."
fi
