#!/usr/bin/perl

# Trace Log Analyzer - High Performance Perl Version
# Optimized for very large trace files (100MB+)
#
# Usage: perl trace_analyzer.pl <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>
# Example: perl trace_analyzer.pl trace.log "doRequest ENTRY" "doRequest RETURN" 3

use strict;
use warnings;
use Time::HiRes qw(time);

# Configuration
my $PROGRESS_INTERVAL = 5000;  # Show progress every N lines
my $MATCH_PROGRESS_INTERVAL = 500;  # Show matching progress every N matches

sub usage {
    print "Usage: $0 <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>\n\n";
    print "Example:\n";
    print "  $0 trace.log \"doRequest ENTRY\" \"doRequest RETURN\" 3\n\n";
    print "Arguments:\n";
    print "  log_file        - Path to the trace log file\n";
    print "  entry_pattern   - Pattern to search for entry points\n";
    print "  exit_pattern    - Pattern to search for exit points\n";
    print "  threshold_seconds - Time threshold in seconds to report slow operations\n";
    exit 1;
}

sub format_size {
    my $bytes = shift;
    if ($bytes >= 1024*1024*1024) {
        return sprintf("%.1f GB", $bytes / (1024*1024*1024));
    } elsif ($bytes >= 1024*1024) {
        return sprintf("%.1f MB", $bytes / (1024*1024));
    } elsif ($bytes >= 1024) {
        return sprintf("%.1f KB", $bytes / 1024);
    } else {
        return "$bytes bytes";
    }
}

sub show_progress {
    my ($current, $total, $task, $start_time) = @_;
    my $percent = $total > 0 ? ($current * 100.0 / $total) : 0;
    my $elapsed = time() - $start_time;
    my $rate = $elapsed > 0 ? $current / $elapsed : 0;
    my $eta = $rate > 0 ? ($total - $current) / $rate : 0;
    
    printf "\r%s: %d/%d (%.1f%%) - %.1f lines/sec - ETA: %.0fs", 
           $task, $current, $total, $percent, $rate, $eta;
}

sub clear_progress {
    print "\r" . " " x 80 . "\r";
}

sub parse_timestamp {
    my $timestamp_str = shift;
    
    # Parse format: [9/12/25, 13:25:29:271 CDT]
    if ($timestamp_str =~ /\[(\d+)\/(\d+)\/(\d+),\s*(\d+):(\d+):(\d+):(\d+)\s+[A-Z]{3}\]/) {
        my ($month, $day, $year, $hour, $min, $sec, $ms) = ($1, $2, $3, $4, $5, $6, $7);
        $year = 2000 + $year if $year < 100;
        
        # Convert to seconds since epoch (simplified calculation)
        # This is approximate but consistent for duration calculations
        my $days_since_epoch = ($year - 1970) * 365 + int(($year - 1969) / 4);  # Rough estimate
        $days_since_epoch += ($month - 1) * 30.5 + $day;  # Rough month calculation
        
        my $seconds = $days_since_epoch * 86400 + $hour * 3600 + $min * 60 + $sec;
        return $seconds + ($ms / 1000.0);
    }
    return 0;
}

sub extract_method_name {
    my $pattern = shift;
    my ($method) = split /\s+/, $pattern, 2;
    return $method || "unknown";
}

# Check arguments
if (@ARGV != 4) {
    usage();
}

my ($log_file, $entry_pattern, $exit_pattern, $threshold) = @ARGV;

# Validate arguments
unless (-f $log_file) {
    die "Error: Log file '$log_file' not found\n";
}

unless ($threshold =~ /^[\d.]+$/) {
    die "Error: Threshold must be a number\n";
}

# Get file info
my $file_size = -s $log_file;
print "Analyzing trace file: $log_file\n";
print "File size: " . format_size($file_size) . "\n";
print "Entry pattern: '$entry_pattern'\n";
print "Exit pattern: '$exit_pattern'\n";
print "Threshold: ${threshold} seconds\n";
print "=" x 80 . "\n";

my $method_name = extract_method_name($entry_pattern);

# Data structures for fast lookups
my %thread_entries = ();  # Hash of hashes: thread_id -> method -> [timestamp, raw_timestamp, line_data]
my @results = ();         # Array of results exceeding threshold
my $total_pairs = 0;
my $slow_operations = 0;
my $entry_count = 0;
my $exit_count = 0;

# Phase 1: Process the log file
print "Phase 1: Reading and processing log file...\n";
my $start_time = time();
my $line_count = 0;

open my $fh, '<', $log_file or die "Cannot open $log_file: $!\n";

while (my $line = <$fh>) {
    $line_count++;
    
    # Show progress
    if ($line_count % $PROGRESS_INTERVAL == 0) {
        show_progress($line_count, 0, "Processing", $start_time);  # Don't know total lines yet
    }
    
    chomp $line;
    next unless $line;
    
    # Remove line numbers if present
    $line =~ s/^\d+\|//;
    
    # Extract timestamp and thread ID using regex (much faster than multiple operations)
    next unless $line =~ /(\[[^\]]+\])\s+([a-fA-F0-9]+)\s+/;
    my ($timestamp_str, $thread_id) = ($1, $2);
    
    if (index($line, $entry_pattern) >= 0) {
        # Process entry
        my $timestamp = parse_timestamp($timestamp_str);
        $thread_entries{$thread_id} = {} unless exists $thread_entries{$thread_id};
        $thread_entries{$thread_id}{$method_name} = [$timestamp, $timestamp_str, $line];
        $entry_count++;
        
    } elsif (index($line, $exit_pattern) >= 0) {
        # Process exit - try to match with existing entry
        if (exists $thread_entries{$thread_id} && 
            exists $thread_entries{$thread_id}{$method_name}) {
            
            my ($entry_time, $entry_timestamp_str, $entry_line) = 
                @{$thread_entries{$thread_id}{$method_name}};
            
            my $exit_time = parse_timestamp($timestamp_str);
            my $duration = $exit_time - $entry_time;
            
            $total_pairs++;
            
            if ($duration >= $threshold) {
                $slow_operations++;
                push @results, {
                    thread_id => $thread_id,
                    method => $method_name,
                    duration => $duration,
                    entry_time => $entry_timestamp_str,
                    exit_time => $timestamp_str,
                    entry_line => $entry_line,
                    exit_line => $line
                };
            }
            
            # Remove the matched entry to prevent duplicate matching
            delete $thread_entries{$thread_id}{$method_name};
            delete $thread_entries{$thread_id} unless keys %{$thread_entries{$thread_id}};
        }
        $exit_count++;
    }
}

close $fh;
clear_progress();

my $processing_time = time() - $start_time;

print "Phase 1 complete:\n";
print "  Total lines processed: $line_count\n";
print "  Found $entry_count entries and $exit_count exits\n";
print "  Matched $total_pairs entry/exit pairs\n";
print "  Processing time: " . sprintf("%.1f", $processing_time) . " seconds\n";
print "  Processing rate: " . sprintf("%.0f", $line_count / $processing_time) . " lines/second\n";

# Check if we found any patterns
if ($entry_count == 0 && $exit_count == 0) {
    print "\nNo matching patterns found in the log file!\n";
    print "Please verify your patterns match the log format exactly.\n";
    exit 1;
}

# Phase 2: Sort and display results
print "\nPhase 2: Sorting results...\n";

# Sort results by duration (descending)
@results = sort { $b->{duration} <=> $a->{duration} } @results;

print "=" x 80 . "\n";
print "\nAnalysis Results:\n";
print "Total matched entry/exit pairs: $total_pairs\n";

if ($slow_operations > 0) {
    print "\nOperations exceeding ${threshold} seconds threshold:\n";
    print "=" x 120 . "\n";
    printf "%-10s %-30s %-12s %-25s %-25s\n", 
           "Thread ID", "Method", "Duration (s)", "Entry Time", "Exit Time";
    print "=" x 120 . "\n";
    
    foreach my $result (@results) {
        # Clean timestamps for display
        my $clean_entry = $result->{entry_time};
        my $clean_exit = $result->{exit_time};
        $clean_entry =~ s/^\[|\]$//g;
        $clean_exit =~ s/^\[|\]$//g;
        
        printf "%-10s %-30s %-12.3f %-25s %-25s\n",
               $result->{thread_id}, $result->{method}, $result->{duration},
               $clean_entry, $clean_exit;
    }
    
    # Calculate statistics
    my @durations = map { $_->{duration} } @results;
    my $min_duration = $durations[-1];  # Last element (smallest after sorting desc)
    my $max_duration = $durations[0];   # First element (largest)
    my $sum = 0;
    $sum += $_ for @durations;
    my $avg_duration = @durations > 0 ? $sum / @durations : 0;
    
    print "\nTiming Statistics (for operations above threshold):\n";
    printf "  Minimum duration: %.3f seconds\n", $min_duration;
    printf "  Maximum duration: %.3f seconds\n", $max_duration;
    printf "  Average duration: %.3f seconds\n", $avg_duration;
} else {
    print "\nNo operations found exceeding ${threshold} seconds threshold.\n";
}

# Show unmatched entries
my $unmatched_count = 0;
foreach my $thread (keys %thread_entries) {
    $unmatched_count += keys %{$thread_entries{$thread}};
}

if ($unmatched_count > 0) {
    print "\nWarning: $unmatched_count unmatched entry points found (no corresponding exits)\n";
}

my $total_time = time() - $start_time;
print "\nAnalysis complete.\n";
print "Total processing time: " . sprintf("%.1f", $total_time) . " seconds\n";
print "Overall rate: " . sprintf("%.0f", $line_count / $total_time) . " lines/second\n";

if ($file_size > 50*1024*1024) {  # For files > 50MB
    my $mb_per_sec = ($file_size / (1024*1024)) / $total_time;
    printf "File processing rate: %.1f MB/second\n", $mb_per_sec;
}

print "\nPerformance Summary:\n";
printf "  File size: %s\n", format_size($file_size);
printf "  Processing time: %.1f seconds\n", $total_time;
printf "  Memory usage: Minimal (streaming processing)\n";
printf "  Algorithm: Single-pass O(n) with hash lookups\n";
