#!/bin/bash

# Script to find largest files and directories
# Compatible with AIX 7 and bash
# Usage: ./find_largest.sh [directory] [number_of_results]

# Default values
SEARCH_DIR="${1:-.}"
NUM_RESULTS="${2:-20}"
TEMP_DIR="/tmp"
TEMP_FILE="$TEMP_DIR/largest_items_$$"

# Check if directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory '$SEARCH_DIR' does not exist or is not accessible."
    exit 1
fi

# Function to convert size to human readable format
human_readable() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        echo "$(($size / 1073741824))G"
    elif [ $size -ge 1048576 ]; then
        echo "$(($size / 1048576))M"
    elif [ $size -ge 1024 ]; then
        echo "$(($size / 1024))K"
    else
        echo "${size}B"
    fi
}

# Function to get directory size (AIX compatible)
get_dir_size() {
    local dir="$1"
    # Use du with -k for kilobytes (more portable than -b)
    # AIX du doesn't have --max-depth, so we use find with -prune
    du -sk "$dir" 2>/dev/null | awk '{print $1 * 1024}'
}

# Function to clean up temp files
cleanup() {
    rm -f "$TEMP_FILE"*
}

# Set up cleanup on exit
trap cleanup EXIT

echo "Searching for largest files and directories in: $SEARCH_DIR"
echo "Showing top $NUM_RESULTS results..."
echo ""

# Create temp files for results
FILES_TEMP="${TEMP_FILE}_files"
DIRS_TEMP="${TEMP_FILE}_dirs"

# Find all files with sizes (excluding directories)
echo "Scanning files..."
find "$SEARCH_DIR" -type f -exec ls -l {} \; 2>/dev/null | \
    awk '{
        # Handle filenames with spaces by reconstructing from field 9 onwards
        filename = ""
        for(i=9; i<=NF; i++) {
            filename = filename $i
            if(i < NF) filename = filename " "
        }
        print $5 "\t" filename
    }' | sort -nr > "$FILES_TEMP"

# Find all directories and calculate their sizes
echo "Scanning directories..."
find "$SEARCH_DIR" -type d 2>/dev/null | while read dir; do
    # Skip the search directory itself if it's "."
    if [ "$dir" = "." ]; then
        continue
    fi
    
    size=$(get_dir_size "$dir")
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        echo -e "$size\t$dir"
    fi
done | sort -nr > "$DIRS_TEMP"

# Display results
echo "================================"
echo "LARGEST FILES:"
echo "================================"
printf "%-12s %s\n" "SIZE" "FILE"
echo "--------------------------------"

head -n "$NUM_RESULTS" "$FILES_TEMP" | while IFS=$'\t' read size filename; do
    human_size=$(human_readable "$size")
    printf "%-12s %s\n" "$human_size" "$filename"
done

echo ""
echo "================================"
echo "LARGEST DIRECTORIES:"
echo "================================"
printf "%-12s %s\n" "SIZE" "DIRECTORY"
echo "--------------------------------"

head -n "$NUM_RESULTS" "$DIRS_TEMP" | while IFS=$'\t' read size dirname; do
    human_size=$(human_readable "$size")
    printf "%-12s %s\n" "$human_size" "$dirname"
done

echo ""
echo "================================"
echo "COMBINED SUMMARY (TOP $NUM_RESULTS):"
echo "================================"
printf "%-12s %-6s %s\n" "SIZE" "TYPE" "NAME"
echo "--------------------------------"

# Combine files and directories, sort by size, and show top results
(
    # Add type indicator to files
    head -n "$NUM_RESULTS" "$FILES_TEMP" | sed 's/^/FILE\t/'
    # Add type indicator to directories  
    head -n "$NUM_RESULTS" "$DIRS_TEMP" | sed 's/^/DIR\t/'
) | sort -k2,2nr | head -n "$NUM_RESULTS" | while IFS=$'\t' read type size name; do
    human_size=$(human_readable "$size")
    printf "%-12s %-6s %s\n" "$human_size" "$type" "$name"
done

# Show summary statistics
if [ -f "$FILES_TEMP" ] && [ -f "$DIRS_TEMP" ]; then
    total_files=$(wc -l < "$FILES_TEMP" 2>/dev/null || echo "0")
    total_dirs=$(wc -l < "$DIRS_TEMP" 2>/dev/null || echo "0")
    
    echo ""
    echo "Summary: Found $total_files files and $total_dirs directories"
fi