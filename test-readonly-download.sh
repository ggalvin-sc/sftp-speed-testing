#!/bin/bash

# SFTP Read-Only Download Speed Test
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

clear
cat << 'HEADER'
╔═══════════════════════════════════════════════════════════════╗
║         SFTP READ-ONLY DOWNLOAD SPEED TEST                   ║
╚═══════════════════════════════════════════════════════════════╝
HEADER

echo
echo -e "${CYAN}This test will:${NC}"
echo "  • Connect to SFTP in READ-ONLY mode"
echo "  • Download files and measure speed"
echo "  • Generate performance report"
echo

# Load config
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✓ Loaded configuration from .env${NC}"
else
    echo -e "${YELLOW}⚠ No .env file - run ./interactive-setup.sh first${NC}"
    exit 1
fi

echo
echo -e "${BOLD}Connection:${NC} $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo

# Create test directory
TEST_DIR="download_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_DIR"
echo -e "${GREEN}✓ Created: $TEST_DIR${NC}"
echo

# Setup SFTP command
if command -v sshpass >/dev/null 2>&1 && [ -n "${SFTP_PASSWORD:-}" ]; then
    SFTP_CMD="sshpass -p \"$SFTP_PASSWORD\" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST"
elif [ -n "${SFTP_KEY_PATH:-}" ]; then
    SFTP_CMD="sftp -o StrictHostKeyChecking=no -i $SFTP_KEY_PATH -P $SFTP_PORT $SFTP_USER@$SFTP_HOST"
else
    echo -e "${RED}✗ No credentials found${NC}"
    exit 1
fi

# Test connection
echo "Testing connection..."
if eval "$SFTP_CMD <<< \"ls\" >/dev/null 2>&1"; then
    echo -e "${GREEN}✓ Connection successful${NC}"
else
    echo -e "${RED}✗ Connection failed${NC}"
    echo "Check: ping $SFTP_HOST"
    exit 1
fi

# List files
echo
echo "Files on server:"
eval "$SFTP_CMD <<< \"ls\"" 2>/dev/null | grep -v "^sftp>" | grep -v "^Trying" | tail -20
echo

# Get file choice
echo "Select download option:"
echo "  1) First 5 files"
echo "  2) First 10 files"
echo "  3) All files"
read -p "Choose [1-3]: " choice

case "$choice" in
    1) FILE_COUNT=5 ;;
    2) FILE_COUNT=10 ;;
    3) FILE_COUNT=99999 ;;
    *) FILE_COUNT=5 ;;
esac

# Get file list
FILE_LIST=$(eval "$SFTP_CMD <<< \"ls\"" 2>/dev/null | grep -v "^sftp>" | grep -v "^Trying" | head -$FILE_COUNT)

if [ -z "$FILE_LIST" ]; then
    echo "No files found"
    exit 1
fi

# Count files
NUM_FILES=$(echo "$FILE_LIST" | wc -l)
echo
echo -e "${GREEN}✓ Will download $NUM_FILES file(s)${NC}"
echo

# Download files
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}           STARTING DOWNLOAD                         ${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo

START_TIME=$(date +%s)
TOTAL_SIZE=0
SUCCESS=0
FAILED=0

while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    
    echo -n "Downloading: $FILE ... "
    
    FILE_START=$(date +%s)
    
    if eval "$SFTP_CMD <<< \"get $FILE $TEST_DIR/$FILE\"" >/dev/null 2>&1; then
        FILE_END=$(date +%s)
        
        if [ -f "$TEST_DIR/$FILE" ]; then
            SIZE=$(stat -c%s "$TEST_DIR/$FILE" 2>/dev/null || stat -f%z "$TEST_DIR/$FILE")
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            SUCCESS=$((SUCCESS + 1))
            
            FILE_TIME=$((FILE_END - FILE_START))
            if [ "$FILE_TIME" -gt 0 ]; then
                SPEED=$((SIZE / FILE_TIME))
                SPEED_MB=$(echo "scale=1; $SPEED / 1024 / 1024" | bc)
                echo -e "${GREEN}✓${NC} ${SPEED_MB} MB/s"
            else
                echo -e "${GREEN}✓${NC} fast!"
            fi
        else
            FAILED=$((FAILED + 1))
            echo -e "${RED}✗ Failed${NC}"
        fi
    else
        FAILED=$((FAILED + 1))
        echo -e "${RED}✗ Failed${NC}"
    fi
done <<< "$FILE_LIST"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}              RESULTS                                ${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo

# Calculate stats
if [ "$DURATION" -gt 0 ]; then
    AVG_SPEED=$((TOTAL_SIZE / DURATION))
    AVG_SPEED_MB=$(echo "scale=2; $AVG_SPEED / 1024 / 1024" | bc)
else
    AVG_SPEED_MB="N/A"
fi

# Format total size
if [ "$TOTAL_SIZE" -gt 1073741824 ]; then
    SIZE_GB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)
    SIZE_STR="${SIZE_GB} GB"
elif [ "$TOTAL_SIZE" -gt 1048576 ]; then
    SIZE_MB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc)
    SIZE_STR="${SIZE_MB} MB"
elif [ "$TOTAL_SIZE" -gt 1024 ]; then
    SIZE_KB=$(echo "scale=2; $TOTAL_SIZE / 1024" | bc)
    SIZE_STR="${SIZE_KB} KB"
else
    SIZE_STR="${TOTAL_SIZE} B"
fi

echo "Files downloaded: $NUM_FILES"
echo -e "  ${GREEN}Success: $SUCCESS${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo
echo "Total size: $SIZE_STR"
echo "Time: ${DURATION}s"
echo -e "Average speed: ${GREEN}${AVG_SPEED_MB} MB/s${NC}"
echo

# Save report
REPORT="$TEST_DIR/report.txt"
cat > "$REPORT" << REPORTEOF
SFTP Download Test - $(date)
===============================
Host: $SFTP_HOST:$SFTP_PORT
User: $SFTP_USER

Results:
  Files: $NUM_FILES
  Success: $SUCCESS
  Failed: $FAILED
  Size: $SIZE_STR
  Time: ${DURATION}s
  Speed: ${AVG_SPEED_MB} MB/s
REPORTEOF

echo -e "${GREEN}✓ Report saved: $REPORT${NC}"
echo

# Show files
echo "Downloaded files:"
ls -lh "$TEST_DIR" | grep -v "^total" | grep -v "^d" | tail -10
echo

# Performance rating
echo -e "${BOLD}Performance Rating:${NC}"

if [ "$AVG_SPEED_MB" != "N/A" ]; then
    SPEED_INT=${AVG_SPEED_MB%.*}
    
    if [ "$SPEED_INT" -ge 50 ]; then
        echo -e "  ${GREEN}EXCELLENT${NC} - Very fast (>50 MB/s)"
    elif [ "$SPEED_INT" -ge 20 ]; then
        echo -e "  ${GREEN}GOOD${NC} - Fast (20-50 MB/s)"
    elif [ "$SPEED_INT" -ge 10 ]; then
        echo -e "  ${YELLOW}AVERAGE${NC} - Moderate (10-20 MB/s)"
    elif [ "$SPEED_INT" -ge 1 ]; then
        echo -e "  ${YELLOW}SLOW${NC} - Low speed (<10 MB/s)"
    else
        echo -e "  ${RED}VERY SLOW${NC} - Poor connection (<1 MB/s)"
    fi
fi

echo
echo "Download location: $TEST_DIR"
echo

read -p "Press Enter to view downloaded files..."
ls -la "$TEST_DIR"
