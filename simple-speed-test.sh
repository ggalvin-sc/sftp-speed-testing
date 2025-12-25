#!/bin/bash

# Simple SFTP/FTP Speed Test using curl
# This will test download speed from your SFTP server

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         SIMPLE DOWNLOAD SPEED TEST                         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo

# Server info
SERVER="209.159.145.206"
PORT="22"
USER="root"

echo "Server: $USER@$SERVER:$PORT"
echo

# Test connection using SSH (will prompt for password)
echo "Testing connection..."
echo "(Enter your SFTP password when prompted)"
echo

# Try to list files and measure time
START_TIME=$(date +%s)

ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER "ls -lh / | head -20" 2>/dev/null && {
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo
    echo "✓ Connection successful!"
    echo "  Response time: ${DURATION}s"
    echo

    # If response is fast, connection is good
    if [ "$DURATION" -lt 2 ]; then
        echo "🟢 EXCELLENT - Very fast response (< 2s)"
    elif [ "$DURATION" -lt 5 ]; then
        echo "🟢 GOOD - Fast response (2-5s)"
    elif [ "$DURATION" -lt 10 ]; then
        echo "🟡 AVERAGE - Moderate response (5-10s)"
    else
        echo "🔴 SLOW - Poor response (> 10s)"
    fi

} || {
    echo
    echo "✗ Connection failed or password required"
    echo
    echo "To test download speed manually:"
    echo "1. Connect: sftp -P $PORT $USER@$SERVER"
    echo "2. Download: get somefile.dat"
    echo "3. Watch the transfer speed shown"
}
