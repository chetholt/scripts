# Trace Log Analyzer Scripts

These scripts parse trace log files to track thread entry and exit points, calculate timing differences, and report methods that exceed a specified threshold.

## Files

- `trace_analyzer.sh` - Bash version (works without Python dependencies)
- `trace_analyzer.py` - Python version (more advanced features, requires Python 3)
- `trace_analyzer_debug.sh` - Debug version for troubleshooting

## Usage

### Bash Script (Recommended)
```bash
./trace_analyzer.sh <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>
```

### Python Script
```bash
python3 trace_analyzer.py <log_file> --entry <entry_pattern> --exit <exit_pattern> --threshold <threshold_seconds>
```

## Examples

### Basic Usage
```bash
# Look for doRequest operations taking longer than 3 seconds
./trace_analyzer.sh trace.log "doRequest ENTRY" "doRequest RETURN" 3

# Look for any operations taking longer than 1.5 seconds  
./trace_analyzer.sh trace.log "processRequest ENTRY" "processRequest RETURN" 1.5

# Find operations with very low threshold (0.01 seconds = 10ms)
./trace_analyzer.sh trace.log "authenticate ENTRY" "authenticate RETURN" 0.01
```

## Log Format

The scripts expect log lines in this format:
```
[9/12/25, 13:25:29:271 CDT] 000001a7 id=00000000 com.tivoli.am.fim.fedmgr2.servlet.SSOPSServletBase           > doRequest ENTRY
[9/12/25, 13:25:29:284 CDT] 000001a7 id=00000000 com.tivoli.am.fim.fedmgr2.servlet.SSOPSServletBase           < doRequest RETURN
```

Where:
- `[9/12/25, 13:25:29:271 CDT]` - Timestamp with milliseconds
- `000001a7` - Thread ID (hex format)
- `> methodName ENTRY` - Entry point indicator
- `< methodName RETURN` - Exit point indicator

## Output

The script provides:
1. **Summary** - Total matched entry/exit pairs
2. **Slow Operations** - Operations exceeding the threshold, sorted by duration (descending)
3. **Statistics** - Min, max, and average duration for slow operations
4. **Warnings** - Unmatched entry points (entries without corresponding exits)

### Sample Output
```
Analyzing trace file: trace.log
Looking for entry pattern: 'doRequest ENTRY'
Looking for exit pattern: 'doRequest RETURN'  
Threshold: 0.001 seconds
================================================================================
Processing log file...
Matching entry/exit pairs...

Analysis Results:
Total matched entry/exit pairs: 1

Operations exceeding 0.001 seconds threshold:
========================================================================================================================
Thread ID  Method                         Duration (s) Entry Time                Exit Time                
========================================================================================================================
000001a7   doRequest                      0.013        9/12/25, 13:25:29:271 CDT 9/12/25, 13:25:29:284 CDT

Timing Statistics (for operations above threshold):
  Minimum duration: 0.013 seconds
  Maximum duration: 0.013 seconds
  Average duration: 0.013 seconds

Analysis complete.
```

## Key Features

1. **Thread Correlation** - Matches entry/exit points by thread ID and method name
2. **Flexible Patterns** - Specify any entry/exit patterns to match
3. **Accurate Timing** - Calculates durations including millisecond precision
4. **Configurable Threshold** - Only reports operations exceeding your specified time
5. **Statistical Analysis** - Provides min/max/average timing statistics
6. **Error Handling** - Reports unmatched entries and handles malformed timestamps

## Pattern Matching Tips

1. **Method-specific patterns**: Use `"methodName ENTRY"` and `"methodName RETURN"` for specific methods
2. **Method name extraction**: The script extracts the method name from the first word of your pattern
3. **Case sensitive**: Patterns are case-sensitive
4. **Exact matching**: The pattern must match exactly as it appears in the log

## Troubleshooting

1. **No matches found**: 
   - Check that your patterns exactly match what's in the log file
   - Verify the log file exists and is readable
   - Use the debug script to see what's being extracted

2. **Unmatched entries**:
   - This is normal for long-running operations that don't complete within the log window
   - May indicate incomplete logging or application crashes

3. **Date parsing errors**:
   - Check that timestamps follow the expected format
   - Ensure timezone information is consistent

## Dependencies

### Bash Script
- bash 3.2+ (macOS default)
- Standard Unix utilities: grep, sed, awk, cut, bc, date

### Python Script  
- Python 3.6+
- No external dependencies (uses only standard library)

## Performance

- Both scripts can handle large log files efficiently
- Memory usage scales with the number of unmatched entries
- Processing time is roughly linear with file size
