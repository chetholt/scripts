#!/usr/bin/env python3
"""
Trace Log Analyzer

This script parses trace log files to track thread entry and exit points,
calculate timing differences, and report methods that exceed a specified threshold.

Usage:
    python3 trace_analyzer.py <log_file> --entry "ENTRY_STRING" --exit "EXIT_STRING" --threshold SECONDS

Example:
    python3 trace_analyzer.py trace.log --entry "doRequest ENTRY" --exit "doRequest RETURN" --threshold 3
"""

import re
import argparse
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import sys


class TraceEntry:
    def __init__(self, timestamp_str: str, thread_id: str, method_name: str, entry_type: str, raw_line: str):
        self.timestamp_str = timestamp_str
        self.thread_id = thread_id
        self.method_name = method_name
        self.entry_type = entry_type
        self.raw_line = raw_line
        self.timestamp = self._parse_timestamp(timestamp_str)
    
    def _parse_timestamp(self, timestamp_str: str) -> datetime:
        """Parse timestamp from format: [9/12/25, 13:25:29:271 CDT]"""
        # Remove brackets and timezone
        clean_ts = timestamp_str.strip('[]').rsplit(' ', 1)[0]
        # Parse the datetime
        return datetime.strptime(clean_ts, "%m/%d/%y, %H:%M:%S:%f")


class TraceAnalyzer:
    def __init__(self, entry_pattern: str, exit_pattern: str, threshold_seconds: float):
        self.entry_pattern = entry_pattern
        self.exit_pattern = exit_pattern
        self.threshold_seconds = threshold_seconds
        self.trace_pattern = re.compile(
            r'\[([^\]]+)\]\s+(\w+)\s+id=\w+\s+[\w.]+\s+[><]\s+(.+)'
        )
        # Track open entries by thread_id and method_name
        self.open_entries: Dict[str, Dict[str, TraceEntry]] = {}
        self.completed_pairs: List[Tuple[TraceEntry, TraceEntry, float]] = []
        
    def parse_line(self, line: str) -> Optional[TraceEntry]:
        """Parse a single log line and extract trace information"""
        line = line.strip()
        if not line:
            return None
            
        # Remove line numbers if present (like "1|", "2|", etc.)
        if '|' in line and line.split('|')[0].isdigit():
            line = '|'.join(line.split('|')[1:])
            
        match = self.trace_pattern.match(line)
        if not match:
            return None
            
        timestamp_str, thread_id, rest_of_line = match.groups()
        
        # Extract method name - it's typically the last word before ENTRY/RETURN
        parts = rest_of_line.split()
        if len(parts) < 2:
            return None
            
        # Look for our entry/exit patterns
        if self.entry_pattern in rest_of_line:
            method_name = self._extract_method_name(rest_of_line, self.entry_pattern)
            return TraceEntry(timestamp_str, thread_id, method_name, 'ENTRY', line)
        elif self.exit_pattern in rest_of_line:
            method_name = self._extract_method_name(rest_of_line, self.exit_pattern)
            return TraceEntry(timestamp_str, thread_id, method_name, 'EXIT', line)
            
        return None
        
    def _extract_method_name(self, line: str, pattern: str) -> str:
        """Extract method name from the pattern"""
        # Extract the method name from the pattern itself
        # For "doRequest ENTRY" -> extract "doRequest"
        # For "doRequest RETURN" -> extract "doRequest"
        words = pattern.split()
        if words:
            return words[0]
        return "unknown"
        
    def process_entry(self, entry: TraceEntry):
        """Process an entry trace"""
        if entry.thread_id not in self.open_entries:
            self.open_entries[entry.thread_id] = {}
            
        # Store the entry, keyed by method name
        self.open_entries[entry.thread_id][entry.method_name] = entry
        
    def process_exit(self, exit_entry: TraceEntry):
        """Process an exit trace and match with corresponding entry"""
        thread_id = exit_entry.thread_id
        method_name = exit_entry.method_name
        
        if (thread_id in self.open_entries and 
            method_name in self.open_entries[thread_id]):
            
            entry_trace = self.open_entries[thread_id][method_name]
            
            # Calculate time difference in seconds
            time_diff = (exit_entry.timestamp - entry_trace.timestamp).total_seconds()
            
            self.completed_pairs.append((entry_trace, exit_entry, time_diff))
            
            # Remove the matched entry
            del self.open_entries[thread_id][method_name]
            if not self.open_entries[thread_id]:
                del self.open_entries[thread_id]
                
    def analyze_file(self, filename: str):
        """Analyze a trace log file"""
        print(f"Analyzing trace file: {filename}")
        print(f"Looking for entry pattern: '{self.entry_pattern}'")
        print(f"Looking for exit pattern: '{self.exit_pattern}'")
        print(f"Threshold: {self.threshold_seconds} seconds")
        print("-" * 80)
        
        try:
            with open(filename, 'r') as file:
                line_num = 0
                for line in file:
                    line_num += 1
                    entry = self.parse_line(line)
                    
                    if entry:
                        if entry.entry_type == 'ENTRY':
                            self.process_entry(entry)
                        elif entry.entry_type == 'EXIT':
                            self.process_exit(entry)
                            
        except FileNotFoundError:
            print(f"Error: File '{filename}' not found")
            sys.exit(1)
        except Exception as e:
            print(f"Error reading file '{filename}': {e}")
            sys.exit(1)
            
    def report_results(self):
        """Generate and display the analysis results"""
        print(f"\nAnalysis Results:")
        print(f"Total matched entry/exit pairs: {len(self.completed_pairs)}")
        
        # Filter pairs that exceed the threshold
        slow_operations = [
            (entry, exit, duration) for entry, exit, duration in self.completed_pairs
            if duration >= self.threshold_seconds
        ]
        
        if slow_operations:
            print(f"\nOperations exceeding {self.threshold_seconds} seconds threshold:")
            print("-" * 120)
            print(f"{'Thread ID':<10} {'Method':<30} {'Duration (s)':<12} {'Entry Time':<25} {'Exit Time':<25}")
            print("-" * 120)
            
            for entry, exit, duration in sorted(slow_operations, key=lambda x: x[2], reverse=True):
                print(f"{entry.thread_id:<10} {entry.method_name:<30} {duration:<12.3f} "
                      f"{entry.timestamp.strftime('%H:%M:%S.%f')[:-3]:<25} "
                      f"{exit.timestamp.strftime('%H:%M:%S.%f')[:-3]:<25}")
        else:
            print(f"\nNo operations found exceeding {self.threshold_seconds} seconds threshold.")
            
        # Report unmatched entries
        unmatched_count = sum(len(methods) for methods in self.open_entries.values())
        if unmatched_count > 0:
            print(f"\nWarning: {unmatched_count} unmatched entry points found (no corresponding exits)")
            
        # Show summary statistics
        if self.completed_pairs:
            durations = [duration for _, _, duration in self.completed_pairs]
            print(f"\nTiming Statistics:")
            print(f"  Minimum duration: {min(durations):.3f} seconds")
            print(f"  Maximum duration: {max(durations):.3f} seconds")
            print(f"  Average duration: {sum(durations)/len(durations):.3f} seconds")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze trace logs for entry/exit timing patterns",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze doRequest timing with 3 second threshold
  python3 trace_analyzer.py trace.log --entry "doRequest ENTRY" --exit "doRequest RETURN" --threshold 3
  
  # Analyze any method with custom patterns
  python3 trace_analyzer.py trace.log --entry "ENTRY" --exit "RETURN" --threshold 1.5
        """
    )
    
    parser.add_argument('logfile', help='Path to the trace log file')
    parser.add_argument('--entry', required=True, 
                       help='Entry pattern to search for (e.g., "doRequest ENTRY")')
    parser.add_argument('--exit', required=True,
                       help='Exit pattern to search for (e.g., "doRequest RETURN")')
    parser.add_argument('--threshold', type=float, required=True,
                       help='Time threshold in seconds to report slow operations')
    
    args = parser.parse_args()
    
    analyzer = TraceAnalyzer(args.entry, args.exit, args.threshold)
    analyzer.analyze_file(args.logfile)
    analyzer.report_results()


if __name__ == "__main__":
    main()
