#!/bin/bash

# SFTP Test using expect for password automation

SFTP_HOST="209.159.145.206"
SFTP_PORT="22"
SFTP_USER="root"
SFTP_PASSWORD='ESSrkoc!6954O)'

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP DOWNLOAD SPEED TEST (with expect)             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo

# Create expect script
cat > /tmp/sftp_test.exp << EXPECTEOF
#!/usr/bin/expect -f
set timeout 30
spawn sftp -P 22 root@209.159.145.206
expect {
    "password:" {
        send "ESSrkoc!6954O)\r"
        expect "sftp>"
        send "ls\r"
        expect "sftp>"
        send "exit\r"
        exp_continue
    }
    "sftp>" {
        send "ls\r"
        expect "sftp>"
        send "exit\r"
    }
    timeout {
        puts "Connection timed out"
        exit 1
    }
    eof
EXPECTEOF

chmod +x /tmp/sftp_test.exp

# Run it and capture output
echo "Connecting to $SFTP_USER@$SFTP_HOST:$SFTP_PORT..."
echo

OUTPUT=$(/tmp/sftp_test.exp 2>&1)
echo "$OUTPUT"

# Check if we got files
if echo "$OUTPUT" | grep -q "^-"; then
    echo
    echo "✓ Connection successful!"
    echo
    # Extract file list
    FILES=$(echo "$OUTPUT" | grep "^-" | awk '{print $NF}' | head -5)
    FILE_COUNT=$(echo "$FILES" | wc -l)
    echo "Found $FILE_COUNT files"
    echo
    echo "First few files:"
    echo "$FILES" | head -5
fi
