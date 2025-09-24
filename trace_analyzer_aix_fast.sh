#!/bin/bash

# Trace Log Analyzer - AIX Compatible with Progress Indicators
# 
# This script parses trace log files to track thread entry and exit points,
# calculate timing differences, and report methods that exceed a specified threshold.
# Optimized for AIX compatibility with progress indicators and better performance
#
# Usage:
#   ./trace_analyzer_aix_fast.sh <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>
#
# Example:
#   ./trace_analyzer_aix_fast.sh trace.log "doRequest ENTRY" "doRequest RETURN" 3

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

# Function to show progress
show_progress() {
    local current="$1"
    local total="$2"
    local task="$3"
    local percent=`awk "BEGIN {if ($total > 0) printf \"%.1f\", ($current * 100) / $total; else print \"0.0\"}"`
    printf "\r%s: %d/%d (%s%%) " "$task" "$current" "$total" "$percent"
}

# Function to clear progress line
clear_progress() {
    printf "\r%80s\r" " "
}

# Function to convert timestamp to seconds since epoch (AIX compatible)
timestamp_to_seconds() {
    local timestamp="$1"
    # Extract date and time from format: [9/12/25, 13:25:29:271 CDT]
    # Remove brackets and timezone
    timestamp=`echo "$timestamp" | sed 's/^\[//' | sed 's/\]$//' | sed 's/ [A-Z][A-Z][A-Z]$//'`
    
    # Parse date and time: 9/12/25, 13:25:29:271
    local date_part=`echo "$timestamp" | cut -d',' -f1`
    local time_part=`echo "$timestamp" | cut -d',' -f2 | sed 's/^ *//'`
    
    # Convert date format from M/D/YY to YYYY-MM-DD
    local month=`echo "$date_part" | cut -d'/' -f1`
    local day=`echo "$date_part" | cut -d'/' -f2`
    local year="20`echo "$date_part" | cut -d'/' -f3`"
    
    # Pad month and day with leading zeros if needed
    if [ ${#month} -eq 1 ]; then
        month="0$month"
    fi
    if [ ${#day} -eq 1 ]; then
        day="0$day"
    fi
    
    # Convert time format from HH:MM:SS:mmm to HH:MM:SS
    local time_no_ms=`echo "$time_part" | cut -d':' -f1-3`
    local milliseconds=`echo "$time_part" | cut -d':' -f4`
    
    # Create a proper timestamp for date command
    local full_timestamp="${year}-${month}-${day} ${time_no_ms}"
    
    # Convert to seconds since epoch - try multiple date formats for compatibility
    local seconds
    
    # Try GNU date format first (common on AIX and Linux)
    seconds=`date -d "$full_timestamp" "+%s" 2>/dev/null`
    if [ $? -ne 0 ]; then
        # Try BSD date format (macOS)
        seconds=`date -j -f "%Y-%m-%d %H:%M:%S" "$full_timestamp" "+%s" 2>/dev/null`
        if [ $? -ne 0 ]; then
            # If both fail, try a more basic approach
            seconds=0
        fi
    fi
    
    # Add milliseconds as decimal part
    echo "${seconds}.${milliseconds}"
}

# Function to extract method name from a pattern
extract_method_name() {
    local pattern="$2"
    
    # Extract the method name from the pattern itself
    # For "doRequest ENTRY" -> extract "doRequest"
    # For "doRequest RETURN" -> extract "doRequest"
    echo "$pattern" | awk '{print $1}'
}

# Function to print separator line
print_separator() {
    local length="$1"
    local i=1
    while [ $i -le $length ]; do
        printf "="
        i=`expr $i + 1`
    done
    printf "\n"
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

# Get file size for progress indication
file_size=`wc -c < "$LOG_FILE" 2>/dev/null | sed 's/^ *//'`
total_lines=`wc -l < "$LOG_FILE" 2>/dev/null | sed 's/^ *//'`

echo "Analyzing trace file: $LOG_FILE"
# Calculate file size in MB using more compatible approach
file_size_mb=`awk "BEGIN {printf \"%.1f\", $file_size / (1024*1024)}"`
echo "File size: ${file_size_mb} MB"
echo "Total lines: $total_lines"
echo "Looking for entry pattern: '$ENTRY_PATTERN'"
echo "Looking for exit pattern: '$EXIT_PATTERN'"
echo "Threshold: $THRESHOLD seconds"
print_separator 80

# Basic validation for threshold (AIX doesn't have advanced regex support)
case "$THRESHOLD" in
    ''|*[!0-9.]*) echo "Error: Threshold must be a number"; exit 1 ;;
esac

# Temporary files for processing (use more unique names for AIX)
TEMP_DIR="/tmp/trace_analysis_$$_`date +%s`"
mkdir -p "$TEMP_DIR"
ENTRY_FILE="$TEMP_DIR/entries"
EXIT_FILE="$TEMP_DIR/exits" 
RESULTS_FILE="$TEMP_DIR/results"
SORTED_ENTRIES="$TEMP_DIR/sorted_entries"
SORTED_EXITS="$TEMP_DIR/sorted_exits"

# Clean up function
cleanup() {
    clear_progress
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Start timing
start_time=`date +%s`

# Extract entries and exits with progress indication
echo "Phase 1: Scanning log file for patterns..."
line_count=0
entry_count=0
exit_count=0

while IFS= read -r line; do
    line_count=`expr $line_count + 1`
    
    # Show progress every 100 lines
    if [ `expr $line_count % 100` -eq 0 ]; then
        show_progress $line_count $total_lines "Scanning"
    fi
    
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Remove line numbers if present (like "1|", "2|", etc.)
    case "$line" in
        [0-9]*\|*)
            line=`echo "$line" | cut -d'|' -f2-`
            ;;
    esac
    
    # Check if line contains our patterns
    if echo "$line" | grep "$ENTRY_PATTERN" >/dev/null 2>&1; then
        # Extract timestamp and thread ID using sed instead of grep -o
        timestamp=`echo "$line" | sed 's/.*\(\[[^]]*\]\).*/\1/'`
        thread_id=`echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/'`
        method_name=`extract_method_name "$line" "$ENTRY_PATTERN"`
        
        # Convert timestamp to seconds
        seconds=`timestamp_to_seconds "$timestamp"`
        
        echo "$thread_id|$method_name|$seconds|$timestamp" >> "$ENTRY_FILE"
        entry_count=`expr $entry_count + 1`
        
    elif echo "$line" | grep "$EXIT_PATTERN" >/dev/null 2>&1; then
        # Extract timestamp and thread ID using sed instead of grep -o
        timestamp=`echo "$line" | sed 's/.*\(\[[^]]*\]\).*/\1/'`
        thread_id=`echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/'`
        method_name=`extract_method_name "$line" "$EXIT_PATTERN"`
        
        # Convert timestamp to seconds
        seconds=`timestamp_to_seconds "$timestamp"`
        
        echo "$thread_id|$method_name|$seconds|$timestamp" >> "$EXIT_FILE"
        exit_count=`expr $exit_count + 1`
    fi
done < "$LOG_FILE"

clear_progress
echo "Phase 1 complete: Found $entry_count entries and $exit_count exits"

# Check if we found any patterns
if [ $entry_count -eq 0 ] && [ $exit_count -eq 0 ]; then
    echo "No matching patterns found in the log file!"
    echo "Please verify your patterns match the log format exactly."
    exit 1
fi

# Sort files for faster matching (O(n) instead of O(n²))
if [ -f "$ENTRY_FILE" ] && [ -s "$ENTRY_FILE" ]; then
    echo "Phase 2: Sorting entries for faster processing..."
    sort -t'|' -k1,1 -k2,2 -k3,3n "$ENTRY_FILE" > "$SORTED_ENTRIES"
fi

if [ -f "$EXIT_FILE" ] && [ -s "$EXIT_FILE" ]; then
    echo "Phase 3: Sorting exits for faster processing..."
    sort -t'|' -k1,1 -k2,2 -k3,3n "$EXIT_FILE" > "$SORTED_EXITS"
fi

# Match entries with exits using a more efficient algorithm
echo "Phase 4: Matching entry/exit pairs..."

total_pairs=0
slow_operations=0
processed_exits=0

# Use a hash-like approach by processing sorted files
if [ -f "$SORTED_EXITS" ] && [ -s "$SORTED_EXITS" ]; then
    while IFS='|' read -r exit_thread exit_method exit_seconds exit_timestamp; do
        processed_exits=`expr $processed_exits + 1`
        
        # Show progress every 10 exits
        if [ `expr $processed_exits % 10` -eq 0 ]; then
            show_progress $processed_exits $exit_count "Matching"
        fi
        
        # Find the most recent matching entry for this thread/method combination
        # This is much faster than nested loops
        if [ -f "$SORTED_ENTRIES" ]; then
            # Use awk for efficient processing - find the last matching entry
            match_line=`awk -F'|' -v thread="$exit_thread" -v method="$exit_method" -v exit_time="$exit_seconds" '
                $1 == thread && $2 == method && $3 < exit_time {
                    # Keep track of the most recent entry before this exit
                    if ($3 > best_time || best_time == "") {
                        best_time = $3
                        best_line = $0
                    }
                }
                END {
                    if (best_line != "") print best_line
                }' "$SORTED_ENTRIES"`
            
            if [ -n "$match_line" ]; then
                # Parse the matching entry
                entry_thread=`echo "$match_line" | cut -d'|' -f1`
                entry_method=`echo "$match_line" | cut -d'|' -f2`
                entry_seconds=`echo "$match_line" | cut -d'|' -f3`
                entry_timestamp=`echo "$match_line" | cut -d'|' -f4`
                
                # Calculate duration using awk for better compatibility
                duration=`awk "BEGIN {printf \"%.3f\", $exit_seconds - $entry_seconds}"`
                if [ $? -eq 0 ] && [ -n "$duration" ]; then
                    total_pairs=`expr $total_pairs + 1`
                    
                    # Check if duration exceeds threshold using awk
                    exceeds=`awk "BEGIN {print ($duration >= $THRESHOLD) ? 1 : 0}"`
                    if [ "$exceeds" = "1" ]; then
                        slow_operations=`expr $slow_operations + 1`
                        printf "%s|%s|%s|%s|%s\n" "$entry_thread" "$entry_method" "$duration" "$entry_timestamp" "$exit_timestamp" >> "$RESULTS_FILE"
                    fi
                    
                    # Remove the matched entry to prevent duplicate matching
                    # Use a more efficient approach with grep -v and temp file
                    grep -v "^$entry_thread|$entry_method|$entry_seconds|" "$SORTED_ENTRIES" > "$SORTED_ENTRIES.tmp" 2>/dev/null && mv "$SORTED_ENTRIES.tmp" "$SORTED_ENTRIES"
                fi
            fi
        fi
    done < "$SORTED_EXITS"
fi

clear_progress
end_time=`date +%s`
elapsed_time=`expr $end_time - $start_time`

echo "Phase 4 complete: Matched $total_pairs entry/exit pairs"
echo "Processing time: ${elapsed_time} seconds"
print_separator 80

# Display results
echo ""
echo "Analysis Results:"
echo "Total matched entry/exit pairs: $total_pairs"

if [ $slow_operations -gt 0 ] && [ -f "$RESULTS_FILE" ]; then
    echo ""
    echo "Operations exceeding $THRESHOLD seconds threshold:"
    print_separator 120
    printf "%-10s %-30s %-12s %-25s %-25s\n" "Thread ID" "Method" "Duration (s)" "Entry Time" "Exit Time"
    print_separator 120
    
    # Sort by duration (descending) and display
    sort -t'|' -k3 -nr "$RESULTS_FILE" | while IFS='|' read -r thread method duration entry_time exit_time; do
        # Clean timestamps for display
        clean_entry=`echo "$entry_time" | sed 's/^\[//' | sed 's/\]$//'`
        clean_exit=`echo "$exit_time" | sed 's/^\[//' | sed 's/\]$//'`
        printf "%-10s %-30s %-12s %-25s %-25s\n" "$thread" "$method" "$duration" "$clean_entry" "$clean_exit"
    done
else
    echo ""
    echo "No operations found exceeding $THRESHOLD seconds threshold."
fi

# Show unmatched entries
if [ -f "$SORTED_ENTRIES" ]; then
    unmatched_entries=`wc -l < "$SORTED_ENTRIES" 2>/dev/null | sed 's/^ *//'`
    if [ "$unmatched_entries" -gt 0 ]; then
        echo ""
        echo "Warning: $unmatched_entries unmatched entry points found (no corresponding exits)"
    fi
fi

# Calculate and show timing statistics if we have results
if [ -f "$RESULTS_FILE" ] && [ -s "$RESULTS_FILE" ]; then
    echo ""
    echo "Timing Statistics (for operations above threshold):"
    
    # Extract durations and calculate min, max, avg using awk
    durations=`cut -d'|' -f3 "$RESULTS_FILE"`
    
    if [ -n "$durations" ]; then
        min_duration=`echo "$durations" | sort -n | head -1`
        max_duration=`echo "$durations" | sort -n | tail -1`
        
        # Calculate average using awk
        avg_duration=`echo "$durations" | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0.000"}'`
        
        echo "  Minimum duration: ${min_duration} seconds"
        echo "  Maximum duration: ${max_duration} seconds" 
        echo "  Average duration: ${avg_duration} seconds"
    fi
fi

echo ""
echo "Analysis complete. Total processing time: ${elapsed_time} seconds"
