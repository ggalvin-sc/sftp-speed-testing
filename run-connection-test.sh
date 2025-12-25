#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         MANUAL SFTP CONNECTION TEST                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo
echo "I'll create a test that you can run manually."
echo

# Get credentials from .env
SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)

echo "Connection info:"
echo "  Host: $SFTP_HOST"
echo "  Port: $SFTP_PORT"
echo "  User: $SFTP_USER"
echo
echo "To test the connection manually, run:"
echo
echo -e "${GREEN}sftp -P $SFTP_PORT $SFTP_USER@$SFTP_HOST${NC}"
echo
echo "Then enter your password when prompted."
echo
echo "Once connected:"
echo "  - List files: ls"
echo "  - Download a file: get filename"
echo "  - Exit: exit"
echo

# Create a simple batch file for testing
cat > /tmp/sftp_batch.txt << 'BATCHFILE'
ls
exit
BATCHFILE

echo "Or use this command (will prompt for password):"
echo -e "${GREEN}echo 'ls' | sftp -b /tmp/sftp_batch.txt -P $SFTP_PORT $SFTP_USER@$SFTP_HOST${NC}"
echo
