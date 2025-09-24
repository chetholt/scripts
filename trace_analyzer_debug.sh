#!/bin/bash

# Debug version to troubleshoot the matching issue

LOG_FILE="trace.log"
ENTRY_PATTERN="doRequest ENTRY"
EXIT_PATTERN="doRequest RETURN"

echo "=== DEBUG: Processing entries ==="
while IFS= read -r line; do
    if echo "$line" | grep -q "$ENTRY_PATTERN"; then
        echo "Found ENTRY line: $line"
        
        timestamp=$(echo "$line" | grep -o '\[[^]]*\]')
        thread_id=$(echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/')
        
        echo "  Timestamp: $timestamp"
        echo "  Thread ID: $thread_id"
        
        # Try timestamp conversion
        clean_ts=$(echo "$timestamp" | sed 's/^\[//' | sed 's/\]$//' | sed 's/ CDT$//')
        echo "  Clean timestamp: $clean_ts"
        
        date_part=$(echo "$clean_ts" | cut -d',' -f1)
        time_part=$(echo "$clean_ts" | cut -d',' -f2 | sed 's/^ *//')
        echo "  Date part: $date_part"
        echo "  Time part: $time_part"
        
        month=$(echo "$date_part" | cut -d'/' -f1)
        day=$(echo "$date_part" | cut -d'/' -f2)
        year="20$(echo "$date_part" | cut -d'/' -f3)"
        
        month=$(printf "%02d" "$month")
        day=$(printf "%02d" "$day")
        
        time_no_ms=$(echo "$time_part" | cut -d':' -f1-3)
        milliseconds=$(echo "$time_part" | cut -d':' -f4)
        
        full_timestamp="${year}-${month}-${day} ${time_no_ms}"
        echo "  Full timestamp: $full_timestamp"
        
        seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$full_timestamp" "+%s" 2>/dev/null)
        if [ $? -eq 0 ]; then
            final_seconds="${seconds}.${milliseconds}"
            echo "  Final seconds: $final_seconds"
        else
            echo "  ERROR: Date conversion failed"
        fi
        
        echo ""
    fi
done < "$LOG_FILE"

echo "=== DEBUG: Processing exits ==="
while IFS= read -r line; do
    if echo "$line" | grep -q "$EXIT_PATTERN"; then
        echo "Found EXIT line: $line"
        
        timestamp=$(echo "$line" | grep -o '\[[^]]*\]')
        thread_id=$(echo "$line" | sed 's/.*\] *\([^ ]*\) .*/\1/')
        
        echo "  Timestamp: $timestamp"
        echo "  Thread ID: $thread_id"
        
        # Try timestamp conversion
        clean_ts=$(echo "$timestamp" | sed 's/^\[//' | sed 's/\]$//' | sed 's/ CDT$//')
        echo "  Clean timestamp: $clean_ts"
        
        date_part=$(echo "$clean_ts" | cut -d',' -f1)
        time_part=$(echo "$clean_ts" | cut -d',' -f2 | sed 's/^ *//')
        echo "  Date part: $date_part"
        echo "  Time part: $time_part"
        
        month=$(echo "$date_part" | cut -d'/' -f1)
        day=$(echo "$date_part" | cut -d'/' -f2)
        year="20$(echo "$date_part" | cut -d'/' -f3)"
        
        month=$(printf "%02d" "$month")
        day=$(printf "%02d" "$day")
        
        time_no_ms=$(echo "$time_part" | cut -d':' -f1-3)
        milliseconds=$(echo "$time_part" | cut -d':' -f4)
        
        full_timestamp="${year}-${month}-${day} ${time_no_ms}"
        echo "  Full timestamp: $full_timestamp"
        
        seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$full_timestamp" "+%s" 2>/dev/null)
        if [ $? -eq 0 ]; then
            final_seconds="${seconds}.${milliseconds}"
            echo "  Final seconds: $final_seconds"
        else
            echo "  ERROR: Date conversion failed"
        fi
        
        echo ""
    fi
done < "$LOG_FILE"
