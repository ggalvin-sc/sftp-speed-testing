#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
echo "║         SFTP DOWNLOAD SPEED TEST                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Load credentials
export SFTP_HOST=$(grep "^SFTP_HOST=" .env | cut -d= -f2)
export SFTP_PORT=$(grep "^SFTP_PORT=" .env | cut -d= -f2)
export SFTP_USER=$(grep "^SFTP_USER=" .env | cut -d= -f2)
export SFTP_PASSWORD=$(grep "^SFTP_PASSWORD=" .env | cut -d= -f2 | sed "s/^'//" | sed "s/'$//")

echo "Server: $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
echo "Testing read-only download speed..."
echo

# Create test directory
TEST_DIR="speed_test_results"
mkdir -p "$TEST_DIR"

# List of files to download (from the directory listing)
FILES_TO_TEST=(
    ".bash_history"
    ".bashrc"
    ".joe_state"
    ".profile"
    ".viminfo"
)

echo "Will download ${#FILES_TO_TEST[@]} files..."
echo

START_TIME=$(date +%s)
TOTAL_SIZE=0
SUCCESS=0

for FILE in "${FILES_TO_TEST[@]}"; do
    echo -ne "${CYAN}→${NC} Downloading: $FILE ... "
    
    FILE_START=$(date +%s)
    
    if sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P $SFTP_PORT $SFTP_USER@$SFTP_HOST <<< "get \"$FILE\" $TEST_DIR/$FILE" >/dev/null 2>&1; then
        FILE_END=$(date +%s)
        
        if [ -f "$TEST_DIR/$FILE" ]; then
            SIZE=$(stat -c%s "$TEST_DIR/$FILE")
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            SUCCESS=$((SUCCESS + 1))
            
            FILE_TIME=$((FILE_END - FILE_START))
            
            if [ "$FILE_TIME" -gt 0 ]; then
                SPEED=$((SIZE / FILE_TIME))
                SPEED_KB=$(echo "scale=1; $SPEED / 1024" | bc)
                SPEED_MB=$(echo "scale=2; $SPEED / 1024 / 1024" | bc)
                
                # Format size
                if [ "$SIZE" -gt 1024 ]; then
                    SIZE_KB_FMT=$(echo "scale=1; $SIZE / 1024" | bc)
                    echo -e "${GREEN}✓${NC} ${SIZE_KB_FMT} KB @ ${SPEED_MB} MB/s (${FILE_TIME}s)"
                else
                    echo -e "${GREEN}✓${NC} ${SIZE} B @ ${SPEED_KB} KB/s (${FILE_TIME}s)"
                fi
            else
                echo -e "${GREEN}✓${NC} very fast!"
            fi
        else
            echo -e "${YELLOW}✗${NC} File not found"
        fi
    else
        echo -e "${YELLOW}✗${NC} Failed"
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo "════════════════════════════════════════"
echo -e "${BOLD}RESULTS${NC}"
echo "════════════════════════════════════════"

# Calculate stats
if [ "$DURATION" -gt 0 ]; then
    AVG_SPEED=$((TOTAL_SIZE / DURATION))
    AVG_SPEED_KB=$(echo "scale=1; $AVG_SPEED / 1024" | bc)
    AVG_SPEED_MB=$(echo "scale.2; $AVG_SPEED / 1024 / 1024" | bc)
else
    AVG_SPEED_KB="N/A"
    AVG_SPEED_MB="N/A"
fi

# Format total size
if [ "$TOTAL_SIZE" -gt 1024 ]; then
    TOTAL_KB=$(echo "scale.1; $TOTAL_SIZE / 1024" | bc)
    TOTAL_STR="${TOTAL_KB} KB"
else
    TOTAL_STR="${TOTAL_SIZE} B"
fi

echo "Files downloaded: ${#FILES_TO_TEST[@]}"
echo -e "  ${GREEN}Success: $SUCCESS${NC}"
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
        echo -e "  ${GREEN}EXCELLENT${NC} - Very fast (>50 MB/s)"
    elif [ "$SPEED_VAL" -ge 20 ]; then
        echo -e "  ${GREEN}GOOD${NC} - Fast (20-50 MB/s)"
    elif [ "$SPEED_VAL" -ge 10 ]; then
        echo -e "  ${YELLOW}AVERAGE${NC} - Moderate (10-20 MB/s)"
    elif [ "$SPEED_VAL" -ge 1 ]; then
        echo -e "  ${YELLOW}SLOW${NC} - Low speed (<10 MB/s)"
    else
        echo -e "  ${GREEN}EXCELLENT${NC} - Very fast for small files"
    fi
fi

echo
echo "Files saved to: $TEST_DIR"
ls -lh "$TEST_DIR" 2>/dev/null | tail -10
