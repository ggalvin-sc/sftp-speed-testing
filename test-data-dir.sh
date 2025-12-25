#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         READ-ONLY SFTP TEST - DATA DIRECTORY               ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Load credentials
export SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
export SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
export SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
export SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "Mode: READ-ONLY (downloading only, no modifications)"
echo

# First, explore the data directory
echo "Exploring data directory..."
echo "════════════════════════════════════════"

# List data directory
sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST << 'SFTPCMD'
cd data
pwd
ls -lh
exit
SFTPCMD

echo
echo "Press Enter to continue with download test..."
read

# Create test directory
TEST_DIR="readonly_download_test_$(date +%H%M%S)"
mkdir -p "$TEST_DIR"

# List files in data directory and get first few
echo
echo "Getting list of files from /data..."
echo "════════════════════════════════════════"

FILE_LIST=$(sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST << 'SFTPCMD'
cd data
ls -la
exit
SFTPCMD
)

echo "$FILE_LIST"
echo

# Extract filenames (only regular files, not directories)
REAL_FILES=$(echo "$FILE_LIST" | grep "^-" | awk '{print $NF}' | grep -v "^$" | head -10)

if [ -z "$REAL_FILES" ]; then
    echo -e "${RED}✗ No files found in /data${NC}"
    echo
    echo "Trying subdirectories..."
    sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST << 'SFTPCMD'
cd data
find . -maxdepth 2 -type f -ls 2>/dev/null || ls -R
exit
SFTPCMD
    exit 0
fi

FILE_COUNT=$(echo "$REAL_FILES" | wc -l)
echo -e "${GREEN}✓ Found $FILE_COUNT file(s) in /data${NC}"
echo

# Ask how many to download
echo "How many files to download for speed test?"
echo "  1) First 3 files"
echo "  2) First 5 files"
echo "  3) First 10 files"
read -p "Choose [1-3]: " choice

case "$choice" in
    1) LIMIT=3 ;;
    2) LIMIT=5 ;;
    3) LIMIT=10 ;;
    *) LIMIT=3 ;;
esac

echo
echo "Will download first $LIMIT files..."
echo

# Download files
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}         STARTING READ-ONLY DOWNLOAD                  ${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo

START_TIME=$(date +%s)
TOTAL_SIZE=0
SUCCESS=0
FAILED=0

COUNT=0
while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    [ "$COUNT" -ge "$LIMIT" ] && break
    
    COUNT=$((COUNT + 1))
    
    echo -ne "${CYAN}[$COUNT/$LIMIT]${NC} Downloading: $FILE ... "
    
    FILE_START=$(date +%s)
    
    # Download file (read-only, no modification to server)
    if sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST <<< "cd data" <<< "get \"$FILE\" $TEST_DIR/$FILE" >/dev/null 2>&1; then
        FILE_END=$(date +%s)
        
        if [ -f "$TEST_DIR/$FILE" ]; then
            SIZE=$(stat -c%s "$TEST_DIR/$FILE")
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            SUCCESS=$((SUCCESS + 1))
            
            FILE_TIME=$((FILE_END - FILE_START))
            
            if [ "$FILE_TIME" -gt 0 ]; then
                SPEED=$((SIZE / FILE_TIME))
                SPEED_MB=$(echo "scale.2; $SPEED / 1024 / 1024" | bc)
                
                # Format size
                if [ "$SIZE" -gt 1048576 ]; then
                    SIZE_FMT=$(echo "scale.1; $SIZE / 1024 / 1024" | bc)MB
                elif [ "$SIZE" -gt 1024 ]; then
                    SIZE_FMT=$(echo "scale.1; $SIZE / 1024" | bc)KB
                else
                    SIZE_FMT=${SIZE}B
                fi
                
                echo -e "${GREEN}✓${NC} ${SIZE_FMT} @ ${SPEED_MB} MB/s (${FILE_TIME}s)"
            else
                echo -e "${GREEN}✓${NC} very fast!"
            fi
        else
            FAILED=$((FAILED + 1))
            echo -e "${RED}✗ Failed${NC}"
        fi
    else
        FAILED=$((FAILED + 1))
        echo -e "${YELLOW}✗${NC} Download failed"
    fi
done <<< "$REAL_FILES"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                    RESULTS                           ${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo

# Calculate stats
if [ "$DURATION" -gt 0 ]; then
    AVG_SPEED=$((TOTAL_SIZE / DURATION))
    AVG_SPEED_KB=$(echo "scale.1; $AVG_SPEED / 1024" | bc)
    AVG_SPEED_MB=$(echo "scale.2; $AVG_SPEED / 1024 / 1024" | bc)
else
    AVG_SPEED_KB="N/A"
    AVG_SPEED_MB="N/A"
fi

# Format total size
if [ "$TOTAL_SIZE" -gt 1073741824 ]; then
    TOTAL_GB=$(echo "scale.2; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)
    TOTAL_STR="${TOTAL_GB} GB"
elif [ "$TOTAL_SIZE" -gt 1048576 ]; then
    TOTAL_MB=$(echo "scale.1; $TOTAL_SIZE / 1024 / 1024" | bc)
    TOTAL_STR="${TOTAL_MB} MB"
elif [ "$TOTAL_SIZE" -gt 1024 ]; then
    TOTAL_KB=$(echo "scale.1; $TOTAL_SIZE / 1024" | bc)
    TOTAL_STR="${TOTAL_KB} KB"
else
    TOTAL_STR="${TOTAL_SIZE} B"
fi

echo "Files downloaded: $COUNT"
echo -e "  ${GREEN}Success: $SUCCESS${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo
echo "Total size: $TOTAL_STR"
echo "Total time: ${DURATION}s"
echo -e "Average speed: ${GREEN}${AVG_SPEED_MB} MB/s${NC}"
echo

# Save report
REPORT="$TEST_DIR/readonly_test_report.txt"
cat > "$REPORT" << REPORTEOF
SFTP READ-ONLY Download Test - $(date)
========================================
Server: $SFTP_HOST:$SFTP_PORT
User: $SFTP_USER
Directory: /data
Mode: READ-ONLY (no modifications to server)

Results:
  Files downloaded: $COUNT
  Success: $SUCCESS
  Failed: $FAILED
  Total size: $TOTAL_STR
  Time: ${DURATION}s
  Speed: ${AVG_SPEED_MB} MB/s
REPORTEOF

echo -e "${GREEN}✓ Report saved: $REPORT${NC}"
echo

# Performance rating
echo -e "${BOLD}Performance Rating:${NC}"

if [ "$AVG_SPEED_MB" != "N/A" ]; then
    SPEED_VAL=${AVG_SPEED_MB%.*}
    
    if [ "$SPEED_VAL" -ge 50 ]; then
        echo -e "  ${GREEN}★★★★★ EXCELLENT${NC} - Very fast (>50 MB/s)"
    elif [ "$SPEED_VAL" -ge 20 ]; then
        echo -e "  ${GREEN}★★★★☆ GOOD${NC} - Fast (20-50 MB/s)"
    elif [ "$SPEED_VAL" -ge 10 ]; then
        echo -e "  ${YELLOW}★★★☆☆ AVERAGE${NC} - Moderate (10-20 MB/s)"
    elif [ "$SPEED_VAL" -ge 1 ]; then
        echo -e "  ${YELLOW}★★☆☆☆ SLOW${NC} - Low speed (<10 MB/s)"
    else
        echo -e "  ${RED}★☆☆☆☆ VERY SLOW${NC} - Poor connection (<1 MB/s)"
    fi
fi

echo
echo "Files saved to: $TEST_DIR"
echo
echo -e "${YELLOW}NOTE: This was READ-ONLY access. No files were modified on the server.${NC}"
echo

# List downloaded files
echo "Downloaded files:"
ls -lh "$TEST_DIR" | grep -v "^total" | grep -v "^d" | tail -10
