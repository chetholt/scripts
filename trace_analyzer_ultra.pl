#!/usr/bin/perl

# Trace Log Analyzer - Ultra High Performance Version
# Optimized for very large trace files (100MB+) with maximum speed
#
# Usage: perl trace_analyzer_ultra.pl <log_file> <entry_pattern> <exit_pattern> <threshold_seconds>

use strict;
use warnings;

# Ultra-fast timestamp parsing using pre-compiled regex and direct calculation
my $timestamp_regex = qr/\[(\d+)\/(\d+)\/(\d+),\s*(\d+):(\d+):(\d+):(\d+)/;
my @month_days = (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);  # Cumulative days

sub parse_timestamp_ultra {
    my $ts = $_[0];
    return 0 unless $ts =~ /$timestamp_regex/;
    
    my ($month, $day, $year, $hour, $min, $sec, $ms) = ($1, $2, $3, $4, $5, $6, $7);
    $year += 2000 if $year < 100;
    
    # Ultra-fast date calculation using lookup table
    my $days = ($year - 1970) * 365 + int(($year - 1969) / 4) + $month_days[$month - 1] + $day - 1;
    return $days * 86400 + $hour * 3600 + $min * 60 + $sec + $ms * 0.001;
}

# Pre-compile regex patterns for maximum speed
my ($log_file, $entry_pattern, $exit_pattern, $threshold) = @ARGV;

die "Usage: $0 <log_file> <entry_pattern> <exit_pattern> <threshold>\n" unless @ARGV == 4;
die "File not found: $log_file\n" unless -f $log_file;
die "Invalid threshold: $threshold\n" unless $threshold =~ /^[\d.]+$/;

my $file_size = -s $log_file;
my $method_name = (split /\s+/, $entry_pattern, 2)[0];

# Pre-compile patterns for ultra-fast matching
my $line_regex = qr/(\[[^\]]+\])\s+([a-fA-F0-9]+)/;

print "Ultra-Fast Trace Analyzer\n";
print "File: $log_file (", sprintf("%.1f MB", $file_size / (1024*1024)), ")\n";
print "Method: $method_name, Threshold: ${threshold}s\n";
print "=" x 60, "\n";

# Single-pass processing with optimized data structures
my %entries;       # thread_id -> [timestamp, raw_timestamp]  
my @results;       # Results array
my ($total_pairs, $slow_ops, $entry_count, $exit_count, $line_count) = (0, 0, 0, 0, 0);

my $start = time;
my $last_progress = 0;

open my $fh, '<', $log_file or die "Cannot open: $!\n";

# Ultra-tight processing loop - every microsecond counts
while (defined(my $line = <$fh>)) {
    $line_count++;
    
    # Progress every 10K lines for minimal overhead
    if ($line_count - $last_progress >= 10000) {
        my $elapsed = time - $start;
        my $rate = $elapsed > 0 ? int($line_count / $elapsed) : 0;
        printf "\rProcessed: %d lines (%.0f lines/sec)          ", $line_count, $rate;
        $last_progress = $line_count;
    }
    
    # Skip empty lines quickly
    next if length($line) < 20;
    
    # Remove line numbers if present (single operation)
    $line =~ s/^\d+\|// if substr($line, 0, 1) =~ /\d/;
    
    # Fast pattern matching using index() - much faster than regex for literal strings
    my $has_entry = index($line, $entry_pattern) >= 0;
    my $has_exit = !$has_entry && index($line, $exit_pattern) >= 0;
    
    next unless $has_entry || $has_exit;
    
    # Extract timestamp and thread (only when needed)
    $line =~ /$line_regex/ or next;
    my ($timestamp_str, $thread_id) = ($1, $2);
    
    if ($has_entry) {
        my $timestamp = parse_timestamp_ultra($timestamp_str);
        $entries{$thread_id} = [$timestamp, $timestamp_str];
        $entry_count++;
    }
    elsif ($has_exit && exists $entries{$thread_id}) {
        my ($entry_time, $entry_timestamp_str) = @{$entries{$thread_id}};
        my $exit_time = parse_timestamp_ultra($timestamp_str);
        my $duration = $exit_time - $entry_time;
        
        $total_pairs++;
        
        if ($duration >= $threshold) {
            $slow_ops++;
            push @results, [$thread_id, $duration, $entry_timestamp_str, $timestamp_str];
        }
        
        delete $entries{$thread_id};
        $exit_count++;
    }
    elsif ($has_exit) {
        $exit_count++;
    }
}

close $fh;

my $total_time = time - $start;
my $rate = $total_time > 0 ? int($line_count / $total_time) : 0;
my $mb_rate = $total_time > 0 ? ($file_size / (1024*1024)) / $total_time : 0;

printf "\rProcessing complete: %d lines in %.1fs (%.0f lines/sec, %.1f MB/sec)\n", 
       $line_count, $total_time, $rate, $mb_rate;

print "\nResults:\n";
print "  Lines processed: $line_count\n";
print "  Entries found: $entry_count\n"; 
print "  Exits found: $exit_count\n";
print "  Matched pairs: $total_pairs\n";
print "  Slow operations (>= ${threshold}s): $slow_ops\n";

if ($slow_ops > 0) {
    print "\nSlow Operations (sorted by duration):\n";
    print "=" x 100, "\n";
    printf "%-12s %-12s %-30s %-30s\n", "Thread ID", "Duration(s)", "Entry Time", "Exit Time";
    print "=" x 100, "\n";
    
    # Sort by duration (descending) and display
    @results = sort { $b->[1] <=> $a->[1] } @results;
    
    foreach my $result (@results) {
        my ($thread, $duration, $entry_ts, $exit_ts) = @$result;
        # Clean timestamps
        $entry_ts =~ s/^\[|\].*$//g;
        $exit_ts =~ s/^\[|\].*$//g;
        
        printf "%-12s %-12.3f %-30s %-30s\n", $thread, $duration, $entry_ts, $exit_ts;
    }
    
    # Quick stats
    my @durations = map { $_->[1] } @results;
    my $min = $durations[-1];
    my $max = $durations[0];
    my $avg = 0;
    $avg += $_ foreach @durations;
    $avg /= @durations;
    
    printf "\nStatistics: Min=%.3fs, Max=%.3fs, Avg=%.3fs\n", $min, $max, $avg;
} else {
    print "No operations exceeded the ${threshold}s threshold.\n";
}

my $unmatched = keys %entries;
print "Unmatched entries: $unmatched\n" if $unmatched;

print "\nPerformance Summary:\n";
printf "  Total time: %.1f seconds\n", $total_time;
printf "  Processing rate: %.0f lines/second\n", $rate;
printf "  Throughput: %.1f MB/second\n", $mb_rate;
printf "  Memory usage: %d KB (estimated)\n", ($total_pairs + $unmatched) * 0.1;

# Performance predictions
if ($file_size > 10*1024*1024) {
    my $predicted_100mb = (100 * 1024 * 1024) / ($mb_rate * 1024 * 1024);
    printf "  Estimated time for 100MB file: %.0f seconds (%.1f minutes)\n", 
           $predicted_100mb, $predicted_100mb / 60;
}
