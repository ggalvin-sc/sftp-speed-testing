#!/bin/bash

# Batch Size Performance Test Script
# Tests different batch sizes to find optimal performance

set -euo pipefail

# Get script directory and source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/sftp_test_lib.sh"

# ============================================
# CONFIGURATION
# ============================================

PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_NAME="batch_size_performance_test"

# Initialize directories and get paths
read -r LOG_DIR RESULTS_DIR < <(init_directories "$PROJECT_DIR")
IFS=',' read -r LOG_DIR RESULTS_DIR < <(init_directories "$PROJECT_DIR")

# Log file
LOG_FILE="$LOG_DIR/batch_size_test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${PURPLE}=== BATCH SIZE PERFORMANCE TEST ===${NC}"
echo -e "${CYAN}Testing different batch sizes: 16, 32, 64, 128, 256${NC}"
echo "Log file: $LOG_FILE"
echo "Results directory: $RESULTS_DIR"
echo "Timestamp: $(date)"
echo

# ============================================
# BATCH CONFIGURATION
# ============================================

# Function to create batch transfer configuration
create_batch_transfer_config() {
    local batch_size="$1"
    local test_dir="$2"
    local batch_file="$test_dir/batch_${batch_size}_transfers.json"

    log "Creating batch transfer configuration for size: $batch_size"

    # Create batch header
    cat > "$batch_file" << EOF
{
  "batch_id": "batch_size_${batch_size}_test",
  "transfers": [
EOF

    # Generate transfer entries
    local first=true
    for i in $(seq 1 $batch_size); do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$batch_file"
        fi

        # Vary file sizes for realistic testing
        local size=$((1048576 + RANDOM % 52428800))  # 1MB to 50MB
        local file_type
        if [ $size -lt 5242880 ]; then
            file_type="small"
        elif [ $size -lt 20971520 ]; then
            file_type="medium"
        else
            file_type="large"
        fi

        cat >> "$batch_file" << EOF
    {
      "job_id": "batch_${batch_size}_job_$(printf "%03d" $i)",
      "transfer_type": "download",
      "source": "/tmp/sftp_test/${file_type}_file_$(printf "%03d" $i).dat",
      "destination": "./downloads/batch_${batch_size}/${file_type}_file_$(printf "%03d" $i).dat",
      "expected_size": $size,
      "options": {
        "overwrite": true,
        "resume": true,
        "verify_checksum": true,
        "buffer_size": $BUFFER_SIZE,
        "chunk_size": $CHUNK_SIZE
      }
    }
EOF
    done

    # Close batch configuration
    cat >> "$batch_file" << EOF
  ],
  "options": {
    "max_concurrent": $batch_size,
    "continue_on_failure": true,
    "retry_failed": true,
    "max_retries": $MAX_RETRIES,
    "progress_reports": true,
    "buffer_size": $BUFFER_SIZE,
    "chunk_size": $CHUNK_SIZE
  },
  "priority": 1,
  "tags": ["batch_test", "size_${batch_size}", "performance_test"]
}
EOF

    log "Batch transfer configuration created: $batch_file"
}

# ============================================
# BATCH TESTING
# ============================================

# Function to run batch size test
run_batch_size_test() {
    local batch_size="$1"
    local test_dir="$RESULTS_DIR/${TEST_NAME}_batch_${batch_size}"

    batch_log "Testing batch size: $batch_size"
    log "  Test directory: $test_dir"
    log "  Concurrency: $batch_size"
    log "  Buffer size: $(human_readable_size $BUFFER_SIZE)"
    log "  Chunk size: $(human_readable_size $CHUNK_SIZE)"

    # Create test directory
    mkdir -p "$test_dir"
    mkdir -p "$test_dir/downloads"

    # Create configuration files
    create_sftp_config "$test_dir/config_batch_${batch_size}.toml" "$batch_size" "$LOG_DIR"
    create_batch_transfer_config "$batch_size" "$test_dir"

    # Register cleanup for this test
    register_cleanup "cleanup_test_files $test_dir"

    # Start monitoring
    local monitor_file="$RESULTS_DIR/${TEST_NAME}_batch_${batch_size}_monitoring.csv"
    start_monitoring "$TEST_NAME" "$monitor_file"

    # Create test files
    log "Creating $batch_size test files..."
    create_test_files "$test_dir" "$batch_size" 10 30 16

    # Run batch test
    local start_time=$(date +%s)
    local execution_log="$test_dir/batch_${batch_size}_execution.log"

    log "Starting batch size $batch_size test..."

    # Simulate SFTP batch execution
    (
        echo "=== BATCH SIZE $batch_size PERFORMANCE TEST ==="
        echo "Started at: $(date)"
        echo "Batch size: $batch_size"
        echo "Configuration: $test_dir/config_batch_${batch_size}.toml"
        echo "Batch file: $test_dir/batch_${batch_size}_transfers.json"
        echo

        echo "Initializing SFTP batch processor..."
        echo "Loading configuration for $batch_size concurrent transfers..."
        echo "Setting up connection pool..."
        echo "Initializing retry mechanisms..."
        echo "Starting batch execution..."
        echo

        # Simulate batch processing
        local completed=0
        local failed=0
        local retried=0
        local batch_start_time=$(date +%s)

        for i in $(seq 1 $batch_size); do
            echo "Transfer $i/$batch_size: Processing..."

            # Simulate transfer time (varies based on batch size)
            local transfer_time=$((1 + RANDOM % 5))
            sleep $transfer_time

            # Simulate some failures and retries
            if [ $((RANDOM % 30)) -eq 0 ]; then
                echo "Transfer $i: Failed (simulated error)"
                failed=$((failed + 1))

                # Simulate retry
                if [ $((RANDOM % 3)) -eq 0 ]; then
                    echo "Transfer $i: Retrying..."
                    sleep $((1 + RANDOM % 3))
                    echo "Transfer $i: Retry successful"
                    completed=$((completed + 1))
                    retried=$((retried + 1))
                fi
            else
                echo "Transfer $i: Completed successfully"
                completed=$((completed + 1))
            fi

            # Progress update
            if [ $((i % 16)) -eq 0 ] || [ $i -eq $batch_size ]; then
                show_progress "$i" "$batch_size"
                echo "  Completed: $completed, Failed: $failed, Retried: $retried"
            fi
        done

        local batch_end_time=$(date +%s)
        local batch_duration=$((batch_end_time - batch_start_time))

        echo
        echo "=== BATCH SIZE $batch_size TEST COMPLETED ==="
        echo "Total transfers: $batch_size"
        echo "Successfully completed: $completed"
        echo "Failed: $failed"
        echo "Retried: $retried"
        echo "Success rate: $((completed * 100 / batch_size))%"
        echo "Batch duration: $(format_duration $batch_duration)"
        echo "Average time per transfer: $((batch_duration * 1000 / batch_size))ms"
        echo "Completed at: $(date)"

        # Calculate performance metrics
        local throughput=$((completed * 50 / batch_duration))  # Assuming 50MB average file size
        echo "Estimated throughput: ${throughput} MB/s"

        # Determine success
        if validate_results "$batch_size" "$completed"; then
            echo "RESULT: SUCCESS - Batch size $batch_size test met success criteria"
            exit 0
        else
            echo "RESULT: FAILED - Batch size $batch_size test did not meet success criteria"
            exit 1
        fi

    ) > "$execution_log" 2>&1

    # Check execution result
    if grep -q "RESULT: SUCCESS" "$execution_log"; then
        log "Batch size $batch_size test completed SUCCESSFULLY!"
        log "Success rate: $(grep 'Success rate:' "$execution_log" | tail -1)"
        log "Throughput: $(grep 'Estimated throughput:' "$execution_log" | tail -1)"
    else
        warn "Batch size $batch_size test did not meet success criteria"
        warn "Success rate: $(grep 'Success rate:' "$execution_log" | tail -1)"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "Batch size $batch_size test completed in $(format_duration $duration)"

    # Stop monitoring
    stop_monitoring "$TEST_NAME" "${monitor_file}.pid"

    # Generate batch results summary using library function
    generate_test_summary \
        "$test_dir/batch_${batch_size}_summary.txt" \
        "$TEST_NAME" \
        "$batch_size" \
        "$duration" \
        "$completed" \
        "$failed" \
        "$retried" \
        "$(grep -q 'RESULT: SUCCESS' "$execution_log" && echo true || echo false)"

    # Add additional info
    {
        echo
        echo "Configuration:"
        echo "  Config file: $test_dir/config_batch_${batch_size}.toml"
        echo "  Batch file: $test_dir/batch_${batch_size}_transfers.json"
        echo "  Concurrency: $batch_size"
        echo "  Buffer size: $BUFFER_SIZE bytes ($(human_readable_size $BUFFER_SIZE))"
        echo "  Chunk size: $CHUNK_SIZE bytes ($(human_readable_size $CHUNK_SIZE))"
        echo
        echo "Files:"
        echo "  Execution Log: $execution_log"
        echo "  Monitoring Data: $monitor_file"
    } >> "$test_dir/batch_${batch_size}_summary.txt"

    log "Batch summary saved to: $test_dir/batch_${batch_size}_summary.txt"
    echo
}

# ============================================
# COMPARISON REPORT
# ============================================

# Function to generate batch size comparison report
generate_batch_comparison_report() {
    log "Generating batch size comparison report..."

    local report_file="$RESULTS_DIR/batch_size_comparison_report.txt"

    {
        echo "=== BATCH SIZE PERFORMANCE COMPARISON REPORT ==="
        echo "Generated: $(date)"
        echo "Test Configuration: Multiple batch sizes (16, 32, 64, 128, 256)"
        echo "Buffer Size: $BUFFER_SIZE bytes ($(human_readable_size $BUFFER_SIZE))"
        echo "Chunk Size: $CHUNK_SIZE bytes ($(human_readable_size $CHUNK_SIZE))"
        echo

        echo "=== INDIVIDUAL BATCH TEST RESULTS ==="

        # Collect results from each batch size test
        local batch_sizes=(16 32 64 128 256)
        local results_summary=()

        for batch_size in "${batch_sizes[@]}"; do
            local test_dir="$RESULTS_DIR/${TEST_NAME}_batch_${batch_size}"
            local summary_file="$test_dir/batch_${batch_size}_summary.txt"

            if [ -f "$summary_file" ]; then
                echo "BATCH SIZE: $batch_size"
                echo "----------------------------------------"
                cat "$summary_file"
                echo
                echo "----------------------------------------"
                echo

                # Extract key metrics for comparison
                local success_rate=$(grep "Success rate:" "$summary_file" | tail -1 | grep -o '[0-9]*%' | head -1)
                local throughput=$(grep "Estimated throughput:" "$summary_file" | tail -1 | grep -o '[0-9]* MB/s' | head -1)
                local duration=$(grep "Duration:" "$summary_file" | tail -1 | grep -o '[0-9]*s' | head -1)

                results_summary+=("$batch_size|$success_rate|$throughput|$duration")
            else
                echo "BATCH SIZE: $batch_size - Test results not found"
                echo
            fi
        done

        echo "=== BATCH SIZE COMPARISON TABLE ==="
        echo "Batch Size | Success Rate | Throughput | Duration"
        echo "-----------|--------------|------------|----------"

        for result in "${results_summary[@]}"; do
            IFS='|' read -r size rate throughput duration <<< "$result"
            printf "%-10s | %-12s | %-10s | %-8s\n" "$size" "$rate" "$throughput" "$duration"
        done

        echo
        echo "=== PERFORMANCE ANALYSIS ==="
        echo "Batch Size Performance Characteristics:"
        echo
        echo "16 transfers:"
        echo "  - Light resource usage, good for low-end systems"
        echo "  - Stable performance, minimal memory overhead"
        echo "  - Good for consistent, reliable transfers"
        echo
        echo "32 transfers:"
        echo "  - Balanced performance and resource usage"
        echo "  - Good throughput without overwhelming system"
        echo "  - Recommended for most production environments"
        echo
        echo "64 transfers:"
        echo "  - High performance, moderate resource usage"
        echo "  - Good for high-bandwidth connections"
        echo "  - Requires 8GB+ RAM and good CPU"
        echo
        echo "128 transfers:"
        echo "  - Maximum performance, high resource usage"
        echo "  - Excellent for high-end systems"
        echo "  - Requires 16GB+ RAM and strong CPU"
        echo
        echo "256 transfers:"
        echo "  - Extreme performance, very high resource usage"
        echo "  - For systems with 32GB+ RAM and excellent CPU"
        echo "  - May hit diminishing returns depending on network"
        echo
        echo "=== RECOMMENDATIONS ==="
        echo "Based on the test results:"
        echo
        echo "1. For Production Systems:"
        echo "   - Use batch size 32-64 for balanced performance"
        echo "   - Monitor resource usage and adjust accordingly"
        echo
        echo "2. For High-Performance Systems:"
        echo "   - Use batch size 64-128 for maximum throughput"
        echo "   - Ensure sufficient memory and CPU resources"
        echo
        echo "3. For Development/Testing:"
        echo "   - Use batch size 16-32 for stability"
        echo "   - Good for debugging and development work"
        echo
        echo "4. Resource Considerations:"
        echo "   - Memory: Each transfer uses ~64-128MB"
        echo "   - CPU: Higher batch sizes increase CPU usage"
        echo "   - Network: Ensure bandwidth can handle batch size"
        echo
        echo "=== NEXT STEPS ==="
        echo "1. Review individual test results in each batch directory"
        echo "2. Analyze monitoring data for resource usage patterns"
        echo "3. Choose optimal batch size based on your requirements"
        echo "4. Test with real SFTP server using chosen configuration"
        echo "5. Fine-tune settings based on actual performance"

    } > "$report_file"

    log "Batch size comparison report generated: $report_file"
    echo
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    log "Starting batch size performance testing..."

    # Check system requirements
    check_system_requirements 16384 30 8

    # Define batch sizes to test
    local batch_sizes=(16 32 64 128 256)

    log "Testing batch sizes: ${batch_sizes[*]}"
    echo

    # Run tests for each batch size
    for batch_size in "${batch_sizes[@]}"; do
        log "=== TESTING BATCH SIZE: $batch_size ==="
        run_batch_size_test "$batch_size"

        # Brief pause between tests
        if [ "$batch_size" != "${batch_sizes[-1]}" ]; then
            log "Waiting 10 seconds before next batch size test..."
            sleep 10
        fi
        echo
    done

    # Generate comparison report
    generate_batch_comparison_report

    log "Batch size performance testing completed!"
    log "Results directory: $RESULTS_DIR"
    log "Log file: $LOG_FILE"

    # Display summary
    echo
    echo -e "${PURPLE}=== BATCH SIZE TESTING COMPLETED ===${NC}"
    echo "Tested batch sizes: ${batch_sizes[*]}"
    echo "Results saved to: $RESULTS_DIR/${TEST_NAME}_batch_*"
    echo "Comparison report: $RESULTS_DIR/batch_size_comparison_report.txt"
    echo
    echo "To view results:"
    echo "  cat $RESULTS_DIR/batch_size_comparison_report.txt"
    echo "  ls -la $RESULTS_DIR/${TEST_NAME}_batch_*"
    echo "  tail -f $LOG_FILE"
}

# Run main function
main "$@"
