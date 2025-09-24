# AIX Compatibility Changes

## Overview
The `trace_analyzer_aix.sh` script has been modified to work on AIX systems that have older versions of common Unix utilities and different shell capabilities.

## Key Changes Made

### 1. Replaced `grep -o` with `sed`
**Problem**: AIX grep doesn't support the `-o` flag (extract only matching parts)
**Solution**: Used `sed` with capture groups instead

```bash
# Before (doesn't work on AIX):
timestamp=$(echo "$line" | grep -o '\[[^]]*\]')

# After (AIX compatible):
timestamp=$(echo "$line" | sed 's/.*\(\[[^]]*\]\).*/\1/')
```

### 2. Removed Bash 4 Brace Expansion
**Problem**: `{1..80}` syntax requires bash 4+, AIX often has older versions
**Solution**: Used `while` loops with `printf` and `tr`

```bash
# Before (requires bash 4):
echo "$(printf '=%.0s' {1..80})"

# After (works on bash 3 and ksh):
print_separator() {
    local length="$1"
    local i=1
    while [ $i -le $length ]; do
        printf "="
        i=`expr $i + 1`
    done
    printf "\n"
}
```

### 3. Enhanced Date Command Compatibility
**Problem**: Different Unix systems use different date command formats
**Solution**: Try multiple formats with fallbacks

```bash
# Try GNU date format first (common on AIX and Linux)
seconds=`date -d "$full_timestamp" "+%s" 2>/dev/null`
if [ $? -ne 0 ]; then
    # Try BSD date format (macOS)
    seconds=`date -j -f "%Y-%m-%d %H:%M:%S" "$full_timestamp" "+%s" 2>/dev/null`
    if [ $? -ne 0 ]; then
        # Fallback for very old systems
        seconds=0
    fi
fi
```

### 4. Replaced `bc` with `awk`
**Problem**: `bc` might not be available on all AIX systems
**Solution**: Used `awk` for floating-point arithmetic

```bash
# Before (requires bc):
duration=$(echo "$exit_seconds - $entry_seconds" | bc -l)

# After (uses awk):
duration=`awk "BEGIN {printf \"%.3f\", $exit_seconds - $entry_seconds}"`
```

### 5. More Portable Variable Assignment
**Problem**: Modern bash features might not be available
**Solution**: Used backticks and more traditional syntax

```bash
# Before (modern bash):
timestamp=$(command)

# After (more portable):
timestamp=`command`
```

### 6. Enhanced Pattern Matching
**Problem**: Complex regex features might not be available
**Solution**: Used `case` statements for simpler pattern matching

```bash
# For number validation:
case "$THRESHOLD" in
    ''|*[!0-9.]*) echo "Error: Threshold must be a number"; exit 1 ;;
esac

# For line number detection:
case "$line" in
    [0-9]*\|*)
        line=`echo "$line" | cut -d'|' -f2-`
        ;;
esac
```

### 7. Robust Timezone Handling
**Problem**: Different timezone abbreviations across systems
**Solution**: Handle multiple timezone formats

```bash
timestamp=`echo "$timestamp" | sed 's/^\[//' | sed 's/\]$//' | sed 's/ CDT$//' | sed 's/ EST$//' | sed 's/ EDT$//' | sed 's/ PST$//' | sed 's/ PDT$//' | sed 's/ MST$//' | sed 's/ MDT$//' | sed 's/ CST$//'`
```

### 8. Better Temp Directory Names
**Problem**: Potential conflicts in multi-user environments
**Solution**: More unique temporary directory names

```bash
TEMP_DIR="/tmp/trace_analysis_$$_`date +%s`"
```

## Testing the AIX Version

To verify the AIX version works on your system:

1. Copy `trace_analyzer_aix.sh` to your AIX system
2. Make it executable: `chmod +x trace_analyzer_aix.sh`
3. Test with a small trace file: `./trace_analyzer_aix.sh trace.log "doRequest ENTRY" "doRequest RETURN" 3`

## Compatibility Notes

- **Shell**: Works with bash 3.0+ or ksh
- **Required utilities**: grep, sed, awk, cut, expr, date, sort, head, tail, wc, tr, printf
- **Does NOT require**: grep -o, bc, bash 4 features
- **Tested on**: macOS (bash 3.2), should work on AIX 5.3+, AIX 6.1+, AIX 7.x

## Performance Considerations

The AIX version might be slightly slower than the original due to:
- More subprocess calls (using `expr` instead of `(())`)
- Using `awk` for calculations instead of `bc`
- Multiple `sed` calls for timestamp processing

However, for typical log files, the performance difference should be negligible.
