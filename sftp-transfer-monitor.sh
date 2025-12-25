#!/bin/bash

# SFTP Transfer Monitor with Alerts
# Monitors file transfers and sends notifications for failures

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  SFTP Transfer Monitor Setup${NC}"
echo -e "${GREEN}============================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root (sudo)${NC}"
    exit 1
fi

# Get regular username
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$REAL_USER")
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

# ============================================
# CREATE TRANSFER MONITOR SCRIPT
# ============================================

echo -e "${GREEN}Creating transfer monitor script...${NC}"

MONITOR_SCRIPT="$SCRIPT_DIR/sftp-transfer-monitor.sh"

cat > "$MONITOR_SCRIPT" << 'MONITOREOF'
#!/bin/bash
# SFTP Transfer Monitor
# Monitors file transfers and alerts on failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINT="<MOUNT_POINT>"
LOG_DIR="$SCRIPT_DIR/logs"
TRANSFER_LOG="$LOG_DIR/sftp-transfers.log"
FAILED_LOG="$LOG_DIR/sftp-transfer-failures.log"
ALERT_LOG="$LOG_DIR/sftp-alerts.log"
STATE_FILE="$LOG_DIR/transfer-monitor.state"

# Configuration
CHECK_INTERVAL=30              # Check every 30 seconds during active transfers
INACTIVE_CHECK_INTERVAL=300    # Check every 5 minutes when idle
MAX_LOG_SIZE=10485760          # 10MB
ALERT_COOLDOWN=300             # Don't alert more often than every 5 minutes

mkdir -p "$LOG_DIR"

# State tracking
LAST_ALERT_TIME=0
LAST_TRANSFER_COUNT=0
LAST_CHECK_TIME=$(date +%s)

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$TRANSFER_LOG"
}

notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    local now=$(date +%s)

    # Rate limiting
    if [ $((now - LAST_ALERT_TIME)) -lt $ALERT_COOLDOWN ]; then
        log "[RATE-LIMITED] $title: $message"
        return 0
    fi

    LAST_ALERT_TIME=$now

    # Desktop notification
    if command -v notify-send >/dev/null 2>&1; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
            notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi

    # Log alert
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $title - $message" >> "$ALERT_LOG"

    log "🚨 ALERT: $title - $message"
}

check_active_transfers() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        notify "Transfer Monitor Error" "SFTP drive not mounted" "critical"
        return 1
    fi

    # Check for active sshfs transfers using /proc
    local sshfs_pid=$(pgrep -f "sshfs.*$MOUNT_POINT" || true)
    if [ -z "$sshfs_pid" ]; then
        return 1
    fi

    # Check if process is doing I/O
    if [ -f "/proc/$sshfs_pid/io" ]; then
        local read_bytes=$(cat /proc/$sshfs_pid/io | grep "^read_bytes:" | awk '{print $2}')
        local write_bytes=$(cat /proc/$sshfs_pid/io | grep "^write_bytes:" | awk '{print $2}')

        # Store state
        echo "$read_bytes:$write_bytes:$(date +%s)" > "$STATE_FILE"

        # If actively reading/writing, consider it active
        if [ "$read_bytes" -gt 0 ] || [ "$write_bytes" -gt 0 ]; then
            return 0
        fi
    fi

    return 1
}

check_incomplete_transfers() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        return
    fi

    # Look for partial files (common patterns)
    local incomplete_files=$(find "$MOUNT_POINT" -type f \
        \( -name "*.part" -o -name "*.partial" -o -name "*.tmp" -o -name "*.download" \) \
        -mmin -5 2>/dev/null | wc -l)

    if [ "$incomplete_files" -gt 0 ]; then
        log "⚠️  Found $incomplete_files incomplete file(s)"
        notify "Incomplete Transfers" "$incomplete_files file(s) may not have completed" "warning"
    fi
}

check_sshfs_errors() {
    local sshfs_pid=$(pgrep -f "sshfs.*$MOUNT_POINT" || true)
    if [ -z "$sshfs_pid" ]; then
        return
    fi

    # Check if process is in error state
    if ! ps -p "$sshfs_pid" >/dev/null 2>&1; then
        notify "SSHFS Process Died" "Transfer process crashed. Check logs." "critical"
        return 1
    fi

    return 0
}

check_network_stability() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        return
    fi

    # Test file system access
    if ! timeout 5 ls "$MOUNT_POINT" >/dev/null 2>&1; then
        notify "SFTP Access Timeout" "Cannot list files. Network may be unstable." "critical"
        return 1
    fi

    return 0
}

monitor_transfer_progress() {
    # Monitor inotify events for file changes
    if ! command -v inotifywait >/dev/null 2>&1; then
        return 0  # Skip if inotifywait not available
    fi

    log "Monitoring file changes in $MOUNT_POINT"

    # Monitor for file close events (transfer completion)
    inotifywait -m -r -e close_write,moved_to,create,delete \
        --format '%w%f %e' "$MOUNT_POINT" 2>/dev/null | while read -r file event; do

        local filename=$(basename "$file")
        log "File event: $filename - $event"

        # Check for errors in filename
        if [[ "$filename" =~ \.(error|failed|corrupt)$ ]]; then
            notify "Transfer Error" "Problem with file: $filename" "critical"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAILED: $file - $event" >> "$FAILED_LOG"
        fi

    done &
}

check_transfer_timeouts() {
    # Find files that haven't changed in 10 minutes but are still being written
    if ! mountpoint -q "$MOUNT_POINT"; then
        return
    fi

    local now=$(date +%s)
    local timeout_seconds=600  # 10 minutes

    # Find files with recent mtime but old atime (stalled transfers)
    find "$MOUNT_POINT" -type f -mmin -10 -fml -10 +5 2>/dev/null | while read -r file; do
        local filename=$(basename "$file")
        log "⏰ Possible stalled transfer: $filename"
        notify "Stalled Transfer" "File may be stuck: $filename" "warning"
    done
}

verify_file_integrity() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        return
    fi

    # Check for recently modified files
    local recent_files=$(find "$MOUNT_POINT" -type f -mmin -5 2>/dev/null)

    if [ -z "$recent_files" ]; then
        return
    fi

    # Sample check - verify a few files are accessible
    local count=0
    local failed=0

    echo "$recent_files" | while read -r file; do
        if [ $count -ge 5 ]; then
            break
        fi

        if [ ! -r "$file" ]; then
            log "❌ Cannot read file: $file"
            failed=$((failed + 1))
        fi

        count=$((count + 1))
    done

    if [ $failed -gt 0 ]; then
        notify "File Integrity Check" "$failed file(s) may be corrupted" "critical"
    fi
}

check_disk_space() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        return
    fi

    local available=$(df "$MOUNT_POINT" | awk 'NR==2{print $4}')
    local available_gb=$((available / 1024 / 1024))

    if [ "$available_gb" -lt 1 ]; then
        notify "Disk Space Critical" "Less than 1GB available on SFTP drive" "critical"
    elif [ "$available_gb" -lt 5 ]; then
        notify "Disk Space Warning" "Less than 5GB available on SFTP drive" "warning"
    fi
}

rotate_logs() {
    for log in "$TRANSFER_LOG" "$FAILED_LOG" "$ALERT_LOG"; do
        if [ -f "$log" ] && [ $(stat -c%s "$log" 2>/dev/null || stat -f%z "$log") -gt "$MAX_LOG_SIZE" ]; then
            local backup="${log}.old"
            mv "$log" "$backup"
            gzip "$backup"
            log "📦 Log rotated: ${backup}.gz"
        fi
    done
}

# Main monitoring loop
log "🚀 Transfer Monitor Started"
log "Mount point: $MOUNT_POINT"
log "Check interval: ${CHECK_INTERVAL}s (active), ${INACTIVE_CHECK_INTERVAL}s (idle)"

# Start file change monitor if available
if command -v inotifywait >/dev/null 2>&1; then
    monitor_transfer_progress
    log "👁️  File change monitoring active"
fi

last_active=false

while true; do
    local now=$(date +%s)

    # Check if transfers are active
    if check_active_transfers; then
        # Active transfers - check frequently
        log "✅ Active transfers detected"
        check_network_stability
        check_sshfs_errors

        last_active=true
        sleep $CHECK_INTERVAL
    else
        # Idle - check less frequently
        if [ "$last_active" = true ]; then
            log "💤 Transfers completed, switching to idle mode"
        fi

        check_incomplete_transfers
        check_transfer_timeouts
        verify_file_integrity
        check_disk_space
        rotate_logs

        last_active=false
        sleep $INACTIVE_CHECK_INTERVAL
    fi
done
MONITOREOF

# Replace mount point placeholder
MOUNT_POINT="${MOUNT_POINT:-$REAL_HOME/sftp-drive}"
sed -i "s|<MOUNT_POINT>|$MOUNT_POINT|g" "$MONITOR_SCRIPT"

chmod +x "$MONITOR_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$MONITOR_SCRIPT"

echo -e "${GREEN}✅ Transfer monitor created: $MONITOR_SCRIPT${NC}"
echo

# ============================================
# CREATE TRANSFER TEST SCRIPT
# ============================================

echo -e "${GREEN}Creating transfer test script...${NC}"

TEST_SCRIPT="$SCRIPT_DIR/test-sftp-transfers.sh"

cat > "$TEST_SCRIPT" << 'TESTEOF'
#!/bin/bash
# Test SFTP Transfers with Monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env" 2>/dev/null || true

MOUNT_POINT="${MOUNT_POINT:-$HOME/sftp-drive}"
LOG_DIR="$SCRIPT_DIR/logs"
TEST_LOG="$LOG_DIR/transfer-test.log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$TEST_LOG"
}

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$1" "$2"
    fi
}

# Test 1: Small file transfer
test_small_file() {
    log "Test 1: Transferring small file (1MB)..."

    local test_file="/tmp/test-small-$$.dat"
    local dest_file="$MOUNT_POINT/test-small-$$.dat"

    dd if=/dev/urandom of="$test_file" bs=1M count=1 2>/dev/null

    local start_time=$(date +%s)

    if cp "$test_file" "$dest_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "✅ Small file transferred successfully in ${duration}s"

        # Verify
        if [ -f "$dest_file" ]; then
            local size=$(stat -c%s "$dest_file")
            log "✅ File verified: $size bytes"
            rm -f "$test_file" "$dest_file"
            return 0
        else
            log "❌ File not found at destination"
            rm -f "$test_file"
            return 1
        fi
    else
        log "❌ Failed to transfer small file"
        rm -f "$test_file"
        return 1
    fi
}

# Test 2: Large file transfer
test_large_file() {
    log "Test 2: Transferring large file (50MB)..."

    local test_file="/tmp/test-large-$$.dat"
    local dest_file="$MOUNT_POINT/test-large-$$.dat"

    dd if=/dev/urandom of="$test_file" bs=1M count=50 2>/dev/null

    local start_time=$(date +%s)

    if cp "$test_file" "$dest_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "✅ Large file transferred successfully in ${duration}s"

        # Calculate speed
        local speed=$((50 / duration))
        log "📊 Transfer speed: ~${speed} MB/s"

        # Verify
        if [ -f "$dest_file" ]; then
            local size=$(stat -c%s "$dest_file")
            local expected_size=$((50 * 1024 * 1024))

            if [ $size -eq $expected_size ]; then
                log "✅ File size verified: $size bytes"
                rm -f "$test_file" "$dest_file"
                return 0
            else
                log "❌ File size mismatch: expected $expected_size, got $size"
                rm -f "$test_file" "$dest_file"
                return 1
            fi
        else
            log "❌ File not found at destination"
            rm -f "$test_file"
            return 1
        fi
    else
        log "❌ Failed to transfer large file"
        rm -f "$test_file"
        return 1
    fi
}

# Test 3: Multiple concurrent transfers
test_concurrent_transfers() {
    log "Test 3: Transferring 10 files concurrently..."

    local pids=()
    local failed=0

    for i in {1..10}; do
        local test_file="/tmp/test-concurrent-$i-$$.dat"
        local dest_file="$MOUNT_POINT/test-concurrent-$i-$$.dat"

        dd if=/dev/urandom of="$test_file" bs=1M count=5 2>/dev/null

        (
            if cp "$test_file" "$dest_file" && [ -f "$dest_file" ]; then
                rm -f "$test_file" "$dest_file"
                exit 0
            else
                rm -f "$test_file"
                exit 1
            fi
        ) &
        pids+=($!)
    done

    # Wait for all transfers
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log "✅ All 10 concurrent transfers succeeded"
        return 0
    else
        log "❌ $failed/10 concurrent transfers failed"
        return 1
    fi
}

# Main
log "=========================================="
log "SFTP Transfer Test Started"
log "=========================================="

if ! mountpoint -q "$MOUNT_POINT"; then
    log "❌ SFTP drive not mounted at $MOUNT_POINT"
    notify "Transfer Test" "SFTP drive not mounted" "critical"
    exit 1
fi

log "✅ SFTP drive mounted at $MOUNT_POINT"

total_tests=0
passed_tests=0

test_small_file && ((passed_tests++)) || true
((total_tests++))

test_large_file && ((passed_tests++)) || true
((total_tests++))

test_concurrent_transfers && ((passed_tests++)) || true
((total_tests++))

log "=========================================="
log "Test Results: $passed_tests/$total_tests passed"
log "=========================================="

if [ $passed_tests -eq $total_tests ]; then
    log "✅ All tests passed!"
    notify "Transfer Test" "All tests passed!" "normal"
    exit 0
else
    log "❌ Some tests failed"
    notify "Transfer Test" "$((total_tests - passed_tests)) test(s) failed" "critical"
    exit 1
fi
TESTEOF

chmod +x "$TEST_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$TEST_SCRIPT"

echo -e "${GREEN}✅ Transfer test script created: $TEST_SCRIPT${NC}"
echo

# ============================================
# CREATE TRANSFER MONITOR SERVICE
# ============================================

echo -e "${GREEN}Creating transfer monitor service...${NC}"

MONITOR_SERVICE_FILE="/etc/systemd/system/sftp-transfer-monitor@$REAL_USER.service"

cat > "$MONITOR_SERVICE_FILE" << EOF
[Unit]
Description=SFTP Transfer Monitor for $REAL_USER
After=sftp-drive@$REAL_USER.service
Requires=sftp-drive@$REAL_USER.service

[Service]
Type=simple
User=$REAL_USER
Group=$REAL_USER

# Auto-restart forever
Restart=always
RestartSec=30s

# Monitor command
ExecStart=$MONITOR_SCRIPT

# Logging
StandardOutput=append:$SCRIPT_DIR/logs/sftp-transfer-monitor.log
StandardError=append:$SCRIPT_DIR/logs/sftp-transfer-monitor-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "sftp-transfer-monitor@$REAL_USER.service"

echo -e "${GREEN}✅ Transfer monitor service enabled${NC}"
echo

# ============================================
# INSTALL OPTIONAL DEPENDENCIES
# ============================================

echo -e "${GREEN}Installing optional dependencies...${NC}"

if command -v apt-get >/dev/null 2>&1; then
    $INSTALL_CMD inotify-tools >/dev/null 2>&1 && echo -e "${GREEN}✅ inotify-tools installed (for file change monitoring)${NC}" || echo -e "${YELLOW}⚠️  inotify-tools not available (optional)${NC}"
fi

echo

# ============================================
# START SERVICE
# ============================================

echo -e "${GREEN}Starting transfer monitor service...${NC}"

systemctl start "sftp-transfer-monitor@$REAL_USER.service"

sleep 2

if systemctl is-active --quiet "sftp-transfer-monitor@$REAL_USER.service"; then
    echo -e "${GREEN}✅ Transfer monitor service is running${NC}"
else
    echo -e "${RED}❌ Transfer monitor service failed to start${NC}"
    echo "Check logs: $SCRIPT_DIR/logs/"
fi

echo

# ============================================
# COMPLETION
# ============================================

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}🎉 Transfer Monitor Setup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo
echo "Your SFTP system now has complete transfer monitoring:"
echo
echo "✅ Transfer Monitoring:"
echo "   - Detects active transfers"
echo "   - Monitors for incomplete files"
echo "   - Checks for stalled transfers"
echo "   - Verifies file integrity"
echo "   - Tracks transfer progress"
echo
echo "✅ Alerts & Notifications:"
echo "   - Transfer failures"
echo "   - Network issues"
echo "   - Process crashes"
echo "   - Stalled transfers"
echo "   - File corruption"
echo "   - Disk space warnings"
echo
echo "✅ Logs:"
echo "   - Transfer log:    logs/sftp-transfers.log"
echo "   - Failure log:     logs/sftp-transfer-failures.log"
echo "   - Alert log:       logs/sftp-alerts.log"
echo "   - Monitor log:     logs/sftp-transfer-monitor.log"
echo
echo "Services:"
echo "  ✅ sftp-drive@$REAL_USER           - Mount service"
echo "  ✅ sftp-monitor@$REAL_USER          - Health monitor"
echo "  ✅ sftp-transfer-monitor@$REAL_USER - Transfer monitor"
echo
echo "Test transfers:"
echo "  $TEST_SCRIPT"
echo
echo "View transfer status:"
echo "  tail -f logs/sftp-transfers.log"
echo "  tail -f logs/sftp-transfer-failures.log"
echo "  tail -f logs/sftp-alerts.log"
echo
echo "Service control:"
echo "  systemctl status sftp-transfer-monitor@$REAL_USER"
echo "  systemctl restart sftp-transfer-monitor@$REAL_USER"
echo
echo -e "${YELLOW}⚠️  IMPORTANT: The transfer monitor works with the SFTP drive.${NC}"
echo -e "${YELLOW}   Make sure the drive is mounted: ./sftp-mount.sh${NC}"
echo
