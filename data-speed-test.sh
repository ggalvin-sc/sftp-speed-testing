#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP DATA DIRECTORY SPEED TEST                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Load credentials
SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "Mode: READ-ONLY (downloading only, no modifications)"
echo "Path: /data/casedoxx.com/cases/56/3M/PDF/IMAGES001"
echo

# Create test directory
TEST_DIR="data_speed_test_$(date +%H%M%S)"
mkdir -p "$TEST_DIR"

# Test files (various sizes for good speed measurement)
FILES=(
    "/data/casedoxx.com/cases/56/3M/PDF/IMAGES001/3rdP_EPA_Weatherford_-17980-19181.PDF"
    "/data/casedoxx.com/cases/56/3M/PDF/IMAGES001/3rdP_EPA_Weatherford_-19245-19260.PDF"
    "/data/casedoxx.com/cases/56/3M/PDF/IMAGES001/3rdP_EPA_Weatherford_-19261-19281.PDF"
    "/data/casedoxx.com/cases/56/3M/PDF/IMAGES001/3rdP_EPA_Weatherford_-19282-19310.PDF"
    "/data/casedoxx.com/cases/56/3M/PDF/IMAGES001/3rdP_EPA_Weatherford_-19240-19242.PDF"
)

echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}         STARTING READ-ONLY DOWNLOAD                  ${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
echo

START_TIME=$(date +%s)
TOTAL_SIZE=0
SUCCESS=0
FAILED=0

for FILE in "${FILES[@]}"; do
    FILENAME=$(basename "$FILE")
    echo -ne "${CYAN}Downloading:${NC} $FILENAME ... "
    
    FILE_START=$(date +%s)
    
    # Download file (read-only, no modification to server)
    if sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST <<< "get \"$FILE\" $TEST_DIR/$FILENAME" >/dev/null 2>&1; then
        FILE_END=$(date +%s)
        
        if [ -f "$TEST_DIR/$FILENAME" ]; then
            SIZE=$(stat -c%s "$TEST_DIR/$FILENAME")
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
done

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
    AVG_SPEED_MB=$(echo "scale.2; $AVG_SPEED / 1024 / 1024" | bc)
else
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

echo "Files downloaded: $((SUCCESS + FAILED))"
echo -e "  ${GREEN}Success: $SUCCESS${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo
echo "Total size: $TOTAL_STR"
echo "Total time: ${DURATION}s"
echo -e "Average speed: ${GREEN}${AVG_SPEED_MB} MB/s${NC}"
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
