#!/bin/bash
#
# SFTP Test Library
# Shared functions and constants for SFTP performance testing scripts
#
# USAGE:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/sftp_test_lib.sh"
#

# ============================================
# CONSTANTS
# ============================================

# Buffer and chunk sizes (in bytes)
readonly BUFFER_SIZE=524288           # 512KB
readonly CHUNK_SIZE=16777216          # 16MB

# Timeout values (in seconds)
readonly CONNECTION_TIMEOUT=60
readonly OPERATION_TIMEOUT=600
readonly BATCH_TIMEOUT=300
readonly IDLE_TIMEOUT=300

# Thresholds
readonly SUCCESS_THRESHOLD=90         # 90% success rate required
readonly CPU_THRESHOLD=80             # 80% CPU usage threshold
readonly MIN_MEMORY_MB=16384          # 16GB minimum memory for high concurrency
readonly MIN_DISK_GB=20               # 20GB minimum disk space
readonly MIN_CPU_CORES=8              # 8 CPU cores minimum

# Retry configuration
readonly MAX_RETRIES=5
readonly RETRY_DELAY_MS=2000
readonly MAX_RETRY_DELAY_SECS=30

# Monitoring intervals
readonly MONITOR_INTERVAL_SEC=2
readonly HEALTH_CHECK_INTERVAL_SEC=30

# ============================================
# COLORS
# ============================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ============================================
# LOGGING FUNCTIONS
# ============================================

# Log informational message
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

# Log warning message
warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING:${NC} $1"
}

# Log error message and exit
error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $1" >&2
}

# Log SFTP-specific message
sftp_log() {
    echo -e "${CYAN}[$(date +%H:%M:%S)] SFTP:${NC} $1"
}

# Log batch test message
batch_log() {
    echo -e "${CYAN}[$(date +%H:%M:%S)] BATCH-TEST:${NC} $1"
}

# Log high concurrency message
high_concurrency_log() {
    echo -e "${PURPLE}[$(date +%H:%M:%S)] HIGH-CONCURRENCY:${NC} $1"
}

# Fatal error - log and exit with cleanup
die() {
    error "$1"
    cleanup
    exit "${2:-1}"
}

# ============================================
# ERROR HANDLING
# ============================================

# Set up error handling
setup_error_handling() {
    set -euo pipefail
    trap 'handle_error $? $LINENO' ERR
}

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    error "Script failed at line $line_number with exit code $exit_code"
    cleanup
}

# ============================================
# CLEANUP FUNCTIONS
# ============================================

# Global cleanup tracker
declare -a CLEANUP_FUNCTIONS=()
declare -a MONITOR_PIDS=()

# Register cleanup function
register_cleanup() {
    CLEANUP_FUNCTIONS+=("$1")
}

# Register monitor PID for cleanup
register_monitor_pid() {
    MONITOR_PIDS+=("$1")
    echo "$1" > "$2"
}

# Perform cleanup
cleanup() {
    log "Performing cleanup..."

    # Kill all registered monitor processes
    for pid in "${MONITOR_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping monitor process (PID: $pid)"
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    MONITOR_PIDS=()

    # Execute registered cleanup functions
    for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
        "$cleanup_func" 2>/dev/null || true
    done
    CLEANUP_FUNCTIONS=()

    log "Cleanup completed"
}

# Cleanup test files
cleanup_test_files() {
    local test_dir="$1"
    if [[ -n "$test_dir" && -d "$test_dir" ]]; then
        log "Cleaning up test files in $test_dir"
        rm -rf "${test_dir:?}/test_file_"*.dat 2>/dev/null || true
        rm -rf "${test_dir:?}/"*.tmp 2>/dev/null || true
    fi
}

# ============================================
# SYSTEM REQUIREMENTS CHECKS
# ============================================

# Check system requirements
check_system_requirements() {
    local min_memory_mb=${1:-$MIN_MEMORY_MB}
    local min_disk_gb=${2:-$MIN_DISK_GB}
    local min_cpu_cores=${3:-$MIN_CPU_CORES}

    log "Checking system requirements..."

    # Check available memory
    local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    log "Available memory: ${available_mem}MB"

    if [ "$available_mem" -lt "$min_memory_mb" ]; then
        warn "Low memory available. Recommended: ${min_memory_mb}MB, Available: ${available_mem}MB"
    fi

    # Check CPU cores
    local cpu_cores=$(nproc)
    log "CPU cores available: $cpu_cores"

    if [ "$cpu_cores" -lt "$min_cpu_cores" ]; then
        warn "Low CPU core count. Recommended: $min_cpu_cores, Available: $cpu_cores"
    fi

    # Check disk space
    local available_disk=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    log "Available disk space: ${available_disk}GB"

    if [ "$available_disk" -lt "$min_disk_gb" ]; then
        die "Insufficient disk space. Need at least ${min_disk_gb}GB, Available: ${available_disk}GB"
    fi

    # Check network connectivity (optional)
    if command -v ping >/dev/null 2>&1; then
        if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            warn "Network connectivity check failed. SFTP operations may fail."
        else
            log "Network connectivity confirmed"
        fi
    fi

    log "System requirements check completed"
}

# ============================================
# FILE OPERATIONS
# ============================================

# Create test file efficiently (using fallocate if available)
create_test_file() {
    local file_path="$1"
    local size_mb="$2"

    if command -v fallocate >/dev/null 2>&1; then
        # Fast allocation
        fallocate -l "${size_mb}M" "$file_path" 2>/dev/null || \
            dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" 2>/dev/null
    else
        # Fallback to dd
        dd if=/dev/urandom of="$file_path" bs=1M count="$size_mb" 2>/dev/null
    fi
}

# Create multiple test files in parallel
create_test_files() {
    local test_dir="$1"
    local count="$2"
    local min_size_mb="$3"
    local max_size_mb="$4"
    local parallel_jobs="${5:-16}"

    log "Creating $count test files (${min_size_mb}-${max_size_mb}MB each)..."

    local created=0
    for i in $(seq 1 "$count"); do
        local size=$((min_size_mb + RANDOM % (max_size_mb - min_size_mb + 1)))
        create_test_file "$test_dir/test_file_${i}.dat" "$size" &

        created=$((created + 1))

        # Control parallelism
        if [ $((created % parallel_jobs)) -eq 0 ]; then
            wait
        fi
    done
    wait

    log "Created $count test files"
}

# ============================================
# MONITORING FUNCTIONS
# ============================================

# Start system monitoring
start_monitoring() {
    local test_name="$1"
    local monitor_file="$2"
    local interval_sec="${3:-$MONITOR_INTERVAL_SEC}"

    log "Starting system monitoring for $test_name..."

    # Create monitoring header
    echo "timestamp,batch_size,cpu_usage,memory_used_mb,memory_available_mb,disk_io_read_mb,disk_io_write_mb,network_rx_mb,network_tx_mb,active_processes" > "$monitor_file"

    # Start monitoring in background
    (
        while true; do
            local timestamp=$(date +%s)

            # CPU usage
            local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")

            # Memory usage
            local memory_used=$(free -m | awk 'NR==2{print $3}')
            local memory_available=$(free -m | awk 'NR==2{print $7}')

            # Disk I/O
            local disk_read=$(cat /proc/diskstats 2>/dev/null | awk '{sum+=$6} END{printf "%.0f", sum*512/1024/1024}' || echo "0")
            local disk_write=$(cat /proc/diskstats 2>/dev/null | awk '{sum+=$10} END{printf "%.0f", sum*512/1024/1024}' || echo "0")

            # Network I/O
            local network_rx=$(cat /proc/net/dev 2>/dev/null | awk 'NR>2{sum+=$2} END{printf "%.0f", sum/1024/1024}' || echo "0")
            local network_tx=$(cat /proc/net/dev 2>/dev/null | awk 'NR>2{sum+=$10} END{printf "%.0f", sum/1024/1024}' || echo "0")

            # Active processes
            local active_processes=$(ps aux | grep -E "(sftp|ssh)" | grep -v grep | wc -l)

            echo "$timestamp,,$cpu_usage,$memory_used,$memory_available,$disk_read,$disk_write,$network_rx,$network_tx,$active_processes" >> "$monitor_file"

            sleep "$interval_sec"
        done
    ) &

    local monitor_pid=$!
    register_monitor_pid "$monitor_pid" "${monitor_file}.pid"

    log "Monitoring started (PID: $monitor_pid, Interval: ${interval_sec}s)"
}

# Stop monitoring
stop_monitoring() {
    local test_name="$1"
    local pid_file="$2"

    if [ -f "$pid_file" ]; then
        local monitor_pid=$(cat "$pid_file")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            log "Stopping monitoring (PID: $monitor_pid)"
            kill "$monitor_pid" 2>/dev/null || true
            wait "$monitor_pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

# ============================================
# PROGRESS REPORTING
# ============================================

# Display progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%% (%d/%d)" "$percentage" "$current" "$total"

    # Add newline when complete
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# ============================================
# CONFIGURATION GENERATION
# ============================================

# Create SFTP configuration file
create_sftp_config() {
    local config_file="$1"
    local batch_size="$2"
    local log_dir="$3"

    cat > "$config_file" << EOF
# SFTP Configuration for Batch Size $batch_size
[connection]
host = "\${SFTP_HOST:-localhost}"
port = \${SFTP_PORT:-22}
username = "\${SFTP_USER:-testuser}"
password = "\${SFTP_PASSWORD:-testpass}"

[transfer]
max_concurrency = $batch_size
buffer_size = $BUFFER_SIZE
chunk_size = $CHUNK_SIZE
max_inflight_bytes = $((BUFFER_SIZE * batch_size * 2))
max_retries = $MAX_RETRIES
retry_delay_ms = $RETRY_DELAY_MS
connection_timeout_secs = $CONNECTION_TIMEOUT
operation_timeout_secs = $OPERATION_TIMEOUT

[permissions]
allow_download = true
allow_upload = false
allow_overwrite = true
allow_delete = false
allow_create = false
allow_create_directories = false
allow_move = false
allow_copy = false
allow_list = true
allow_read_attributes = true
allow_write_attributes = false
allow_execute = false

[security]
host_key_verification = "accept_new"
known_hosts_path = ""

[logging]
level = "info"
file_path = "$log_dir/sftp_batch_${batch_size}.log"
max_file_size_mb = 100
max_files = 5

[resume]
enabled = true
chunk_size = $CHUNK_SIZE
max_resume_attempts = $MAX_RETRIES

[checksums]
enabled = true
algorithm = "sha256"
verify_after_transfer = true

# Batch-specific settings
[batch]
batch_size = $batch_size
max_concurrent_batches = $((batch_size / 16))
batch_timeout_secs = $BATCH_TIMEOUT
continue_on_batch_failure = true
EOF

    log "Configuration created: $config_file"
}

# ============================================
# RESULT VALIDATION
# ============================================

# Validate test results
validate_results() {
    local expected_count=$1
    local completed_count=$2
    local threshold_percent="${3:-$SUCCESS_THRESHOLD}"

    local success_rate=$((completed_count * 100 / expected_count))

    if [ "$completed_count" -ge $((expected_count * threshold_percent / 100)) ]; then
        log "Validation passed: $completed_count/$expected_count (${success_rate}%)"
        return 0
    else
        warn "Validation failed: $completed_count/$expected_count (${success_rate}%), required: ${threshold_percent}%"
        return 1
    fi
}

# ============================================
# REPORT GENERATION
# ============================================

# Generate test summary
generate_test_summary() {
    local summary_file="$1"
    local test_name="$2"
    local batch_size="$3"
    local duration=$4
    local completed=$5
    local failed=$6
    local retried=$7
    local success=$8

    {
        echo "=== TEST SUMMARY ==="
        echo "Test: $test_name"
        echo "Batch Size: $batch_size"
        echo "Duration: ${duration}s"
        echo "Success: $success"
        echo "Timestamp: $(date)"
        echo
        echo "Results:"
        echo "  Total transfers: $((completed + failed))"
        echo "  Successfully completed: $completed"
        echo "  Failed: $failed"
        echo "  Retried: $retried"
        echo "  Success rate: $((completed * 100 / (completed + failed)))%"
        echo
        echo "Performance:"
        echo "  Average time per transfer: $((duration * 1000 / (completed + failed)))ms"
        local avg_size=10  # Assuming 10MB average
        echo "  Estimated throughput: $((completed * avg_size / duration)) MB/s"
    } > "$summary_file"

    log "Test summary saved to: $summary_file"
}

# ============================================
# INITIALIZATION
# ============================================

# Initialize directories
init_directories() {
    local base_dir="$1"

    local log_dir="$base_dir/logs"
    local results_dir="$base_dir/performance_results"

    mkdir -p "$log_dir"
    mkdir -p "$results_dir"

    echo "$log_dir,$results_dir"
}

# Get script directory
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# ============================================
# HELPERS
# ============================================

# Convert bytes to human readable
human_readable_size() {
    local bytes=$1
    local units=('B' 'KB' 'MB' 'GB' 'TB')
    local unit=0

    while [ $bytes -gt 1024 ] && [ $unit -lt ${#units[@]}-1 ]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done

    echo "${bytes}${units[$unit]}"
}

# Format duration
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Export functions for use in sourced scripts
export -f log warn error sftp_log batch_log high_concurrency_log die
export -f setup_error_handling handle_error cleanup
export -f register_cleanup register_monitor_pid cleanup_test_files
export -f check_system_requirements create_test_file create_test_files
export -f start_monitoring stop_monitoring show_progress
export -f create_sftp_config validate_results generate_test_summary
export -f init_directories get_script_dir
export -f human_readable_size format_duration
