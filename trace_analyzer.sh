#!/bin/bash

# Trace Log Analyzer - Bash Version
# 
# This script parses trace log files to track thread entry and exit points,
# calculate timing differences, and report methods that exceed a specified threshold.
#
# Usage:
#   ./trace_analyzer.sh <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>
#
# Example:
#   ./trace_analyzer.sh trace.log "doRequest ENTRY" "doRequest RETURN" 3

# Function to show usage
usage() {
    echo "Usage: $0 <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>"
    echo ""
    echo "Example:"
    echo "  $0 trace.log \"doRequest ENTRY\" \"doRequest RETURN\" 3"
    echo ""
    echo "Arguments:"
    echo "  log_file        - Path to the trace log file"
    echo "  entry_pattern   - Pattern to search for entry points (e.g., 'doRequest ENTRY')"
    echo "  exit_pattern    - Pattern to search for exit points (e.g., 'doRequest RETURN')"
    echo "  threshold_seconds - Time threshold in seconds to report slow operations"
    exit 1
}

# Function to convert timestamp to seconds since epoch
timestamp_to_seconds() {
    local timestamp="$1"
    # Extract date and time from format: [9/12/25, 13:25:29:271 CDT]
    # Remove brackets and timezone
    timestamp=$(echo "$timestamp" | sed 's/^\[//' | sed 's/\]$//' | sed 's/ CDT$//')
    
    # Parse date and time: 9/12/25, 13:25:29:271
    local date_part=$(echo "$timestamp" | cut -d',' -f1)
    local time_part=$(echo "$timestamp" | cut -d',' -f2 | sed 's/^ *//')
    
    # Convert date format from M/D/YY to YYYY-MM-DD
    local month=$(echo "$date_part" | cut -d'/' -f1)
    local day=$(echo "$date_part" | cut -d'/' -f2)
    local year="20$(echo "$date_part" | cut -d'/' -f3)"
    
    # Pad month and day with leading zeros if needed
    month=$(printf "%02d" "$month")
    day=$(printf "%02d" "$day")
    
    # Convert time format from HH:MM:SS:mmm to HH:MM:SS
    local time_no_ms=$(echo "$time_part" | cut -d':' -f1-3)
    local milliseconds=$(echo "$time_part" | cut -d':' -f4)
    
    # Create a proper timestamp for date command
    local full_timestamp="${year}-${month}-${day} ${time_no_ms}"
    
    # Convert to seconds since epoch and add milliseconds
    local seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$full_timestamp" "+%s" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "0"
        return
    fi
    
    # Add milliseconds as decimal part
    echo "${seconds}.${milliseconds}"
}

# Function to extract method name from a line
extract_method_name() {
    local line="$1"
    local pattern="$2"
    
    # Extract the method name from the pattern itself
    # For "doRequest ENTRY" -> extract "doRequest"
    # For "doRequest RETURN" -> extract "doRequest"
    echo "$pattern" | awk '{print $1}'
}

# Check arguments
if [ $# -ne 4 ]; then
    usage
fi

LOG_FILE="$1"
ENTRY_PATTERN="$2"
EXIT_PATTERN="$3"
THRESHOLD="$4"

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file '$LOG_FILE' not found"
    exit 1
fi

# Validate threshold is a number
if ! [[ "$THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: Threshold must be a number"
    exit 1
fi

echo "Analyzing trace file: $LOG_FILE"
echo "Looking for entry pattern: '$ENTRY_PATTERN'"
echo "Looking for exit pattern: '$EXIT_PATTERN'"
echo "Threshold: $THRESHOLD seconds"
echo "$(printf '=%.0s' {1..80})"

# Temporary files for processing
TEMP_DIR="/tmp/trace_analysis_$$"
mkdir -p "$TEMP_DIR"
ENTRY_FILE="$TEMP_DIR/entries"
EXIT_FILE="$TEMP_DIR/exits"
RESULTS_FILE="$TEMP_DIR/results"

# Clean up function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Process the log file
echo "Processing log file..."

# Extract entries and exits
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Remove line numbers if present (like "1|", "2|", etc.)
    if echo "$line" | grep -q '^[0-9]*|'; then
        line=$(echo "$line" | cut -d'|' -f2-)
    fi
    
    # Check if line contains our patterns
    if echo "$line" | grep -q "$ENTRY_PATTERN"; then
        # Extract timestamp and thread ID
        timestamp=$(echo "$line" | grep -o '\[[^]]*\]')
        thread_id=$(echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/')
        method_name=$(extract_method_name "$line" "$ENTRY_PATTERN")
        
        # Convert timestamp to seconds
        seconds=$(timestamp_to_seconds "$timestamp")
        
        echo "$thread_id|$method_name|$seconds|$timestamp" >> "$ENTRY_FILE"
        
    elif echo "$line" | grep -q "$EXIT_PATTERN"; then
        # Extract timestamp and thread ID
        timestamp=$(echo "$line" | grep -o '\[[^]]*\]')
        thread_id=$(echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/')
        method_name=$(extract_method_name "$line" "$EXIT_PATTERN")
        
        # Convert timestamp to seconds
        seconds=$(timestamp_to_seconds "$timestamp")
        
        echo "$thread_id|$method_name|$seconds|$timestamp" >> "$EXIT_FILE"
    fi
done < "$LOG_FILE"

# Match entries with exits
echo "Matching entry/exit pairs..."

total_pairs=0
slow_operations=0

# Process each exit and find matching entry
if [ -f "$EXIT_FILE" ]; then
    while IFS='|' read -r exit_thread exit_method exit_seconds exit_timestamp; do
        # Find matching entry
        if [ -f "$ENTRY_FILE" ]; then
            while IFS='|' read -r entry_thread entry_method entry_seconds entry_timestamp; do
                if [ "$exit_thread" = "$entry_thread" ] && [ "$exit_method" = "$entry_method" ]; then
                    # Calculate duration
                    duration=$(echo "$exit_seconds - $entry_seconds" | bc -l 2>/dev/null)
                    if [ $? -eq 0 ] && [ -n "$duration" ]; then
                        total_pairs=$((total_pairs + 1))
                        
                        # Check if duration exceeds threshold
                        if [ $(echo "$duration >= $THRESHOLD" | bc -l 2>/dev/null) -eq 1 ]; then
                            slow_operations=$((slow_operations + 1))
                            printf "%s|%s|%.3f|%s|%s\n" "$entry_thread" "$entry_method" "$duration" "$entry_timestamp" "$exit_timestamp" >> "$RESULTS_FILE"
                        fi
                        
                        # Remove the matched entry to prevent duplicate matching
                        grep -v "^$entry_thread|$entry_method|$entry_seconds|$entry_timestamp$" "$ENTRY_FILE" > "$ENTRY_FILE.tmp" && mv "$ENTRY_FILE.tmp" "$ENTRY_FILE"
                    fi
                    break
                fi
            done < "$ENTRY_FILE"
        fi
    done < "$EXIT_FILE"
fi

# Display results
echo ""
echo "Analysis Results:"
echo "Total matched entry/exit pairs: $total_pairs"

if [ $slow_operations -gt 0 ] && [ -f "$RESULTS_FILE" ]; then
    echo ""
    echo "Operations exceeding $THRESHOLD seconds threshold:"
    echo "$(printf '=%.0s' {1..120})"
    printf "%-10s %-30s %-12s %-25s %-25s\n" "Thread ID" "Method" "Duration (s)" "Entry Time" "Exit Time"
    echo "$(printf '=%.0s' {1..120})"
    
    # Sort by duration (descending) and display
    sort -t'|' -k3 -nr "$RESULTS_FILE" | while IFS='|' read -r thread method duration entry_time exit_time; do
        # Clean timestamps for display
        clean_entry=$(echo "$entry_time" | sed 's/^\[//' | sed 's/\]$//')
        clean_exit=$(echo "$exit_time" | sed 's/^\[//' | sed 's/\]$//')
        printf "%-10s %-30s %-12s %-25s %-25s\n" "$thread" "$method" "$duration" "$clean_entry" "$clean_exit"
    done
else
    echo ""
    echo "No operations found exceeding $THRESHOLD seconds threshold."
fi

# Show unmatched entries
if [ -f "$ENTRY_FILE" ]; then
    unmatched_entries=$(wc -l < "$ENTRY_FILE" 2>/dev/null || echo 0)
    if [ "$unmatched_entries" -gt 0 ]; then
        echo ""
        echo "Warning: $unmatched_entries unmatched entry points found (no corresponding exits)"
    fi
fi

# Calculate and show timing statistics if we have results
if [ -f "$RESULTS_FILE" ] && [ -s "$RESULTS_FILE" ]; then
    echo ""
    echo "Timing Statistics (for operations above threshold):"
    
    # Extract durations and calculate min, max, avg
    durations=$(cut -d'|' -f3 "$RESULTS_FILE")
    
    if [ -n "$durations" ]; then
        min_duration=$(echo "$durations" | sort -n | head -1)
        max_duration=$(echo "$durations" | sort -n | tail -1)
        
        # Calculate average
        sum=$(echo "$durations" | awk '{sum+=$1} END {print sum}')
        count=$(echo "$durations" | wc -l)
        avg_duration=$(echo "scale=3; $sum / $count" | bc -l 2>/dev/null)
        
        echo "  Minimum duration: ${min_duration} seconds"
        echo "  Maximum duration: ${max_duration} seconds" 
        echo "  Average duration: ${avg_duration} seconds"
    fi
fi

echo ""
echo "Analysis complete."
