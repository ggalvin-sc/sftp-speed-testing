#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP SPEED TEST                                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Load credentials
export SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
export SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
export SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
export SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo

# List all files recursively
echo "Listing files on server..."
echo "════════════════════════════════════════"

ALL_FILES=$(sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST << 'SFTPCMD'
ls -R
exit
SFTPCMD
)

echo "$ALL_FILES"
echo

# Get only regular files (not directories)
REAL_FILES=$(echo "$ALL_FILES" | grep "^-" | awk '{print $NF}' | grep -v "^$" | head -10)

if [ -z "$REAL_FILES" ]; then
    echo "No files found. Listing directories instead..."
    sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST << 'SFTPCMD'
pwd
ls -la
exit
SFTPCMD
    exit 0
fi

FILE_COUNT=$(echo "$REAL_FILES" | wc -l)
echo "Found $FILE_COUNT file(s)"
echo

# Create test directory
TEST_DIR="speed_test_$(date +%H%M%S)"
mkdir -p "$TEST_DIR"

# Download files and measure speed
echo "Downloading files..."
echo "════════════════════════════════════════"

START_TIME=$(date +%s)
TOTAL_SIZE=0

while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    
    echo -n "Downloading: $FILE ... "
    FILE_START=$(date +%s)
    
    if sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST <<< "get \"$FILE\" $TEST_DIR/" >/dev/null 2>&1; then
        FILE_END=$(date +%s)
        
        if [ -f "$TEST_DIR/$FILE" ]; then
            SIZE=$(stat -c%s "$TEST_DIR/$FILE")
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            FILE_TIME=$((FILE_END - FILE_START))
            
            if [ "$FILE_TIME" -gt 0 ]; then
                SPEED=$((SIZE / FILE_TIME))
                SPEED_MB=$(echo "scale=2; $SPEED / 1024 / 1024" | bc)
                echo -e "${GREEN}✓${NC} ${SPEED_MB} MB/s"
            else
                echo -e "${GREEN}✓${NC} fast!"
            fi
        else
            echo "✗ Failed"
        fi
    else
        echo "✗ Failed"
    fi
done <<< "$REAL_FILES"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo "════════════════════════════════════════"
echo -e "${BOLD}RESULTS${NC}"
echo "════════════════════════════════════════"

if [ "$DURATION" -gt 0 ]; then
    AVG_SPEED=$((TOTAL_SIZE / DURATION))
    AVG_SPEED_MB=$(echo "scale=2; $AVG_SPEED / 1024 / 1024" | bc)
else
    AVG_SPEED_MB="N/A"
fi

if [ "$TOTAL_SIZE" -gt 1048576 ]; then
    SIZE_MB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc)
    SIZE_STR="${SIZE_MB} MB"
elif [ "$TOTAL_SIZE" -gt 1024 ]; then
    SIZE_KB=$(echo "scale=2; $TOTAL_SIZE / 1024" | bc)
    SIZE_STR="${SIZE_KB} KB"
else
    SIZE_STR="${TOTAL_SIZE} B"
fi

echo "Time: ${DURATION}s"
echo "Size: $SIZE_STR"
echo -e "Average speed: ${GREEN}${AVG_SPEED_MB} MB/s${NC}"
echo
echo "Files saved to: $TEST_DIR"
