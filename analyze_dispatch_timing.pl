#!/usr/bin/perl
use strict;
use warnings;

# Hash to store ENTRY timestamps by thread ID
my %entries;
# Array to store completed transactions with their durations
my @results;

# Read input from grep command (either piped or from files)
while (<STDIN>) {
    chomp;
    
    # Parse the log line
    # Example: trace_25.06.09_18.49.04.0.log:[11/20/24, 16:19:35:485 CST] 00051d2d id=00000000 ...
    if (m{^(.+?):\[(.+?)\]\s+(\w+)\s+.*FimWsTrustStsDispatcher\s+([><])\s+dispatch\s+(ENTRY|RETURN)}) {
        my ($file, $timestamp, $thread_id, $direction, $type) = ($1, $2, $3, $4, $5);
        
        if ($type eq 'ENTRY') {
            # Store the entry information
            $entries{$thread_id} = {
                file => $file,
                timestamp => $timestamp,
                time_ms => parse_timestamp($timestamp)
            };
        } elsif ($type eq 'RETURN' && exists $entries{$thread_id}) {
            # Calculate duration
            my $entry = $entries{$thread_id};
            my $return_ms = parse_timestamp($timestamp);
            my $duration_ms = $return_ms - $entry->{time_ms};
            
            push @results, {
                thread_id => $thread_id,
                file => $entry->{file},
                entry_time => $entry->{timestamp},
                return_time => $timestamp,
                duration_ms => $duration_ms
            };
            
            # Clean up the entry
            delete $entries{$thread_id};
        }
    }
}

# Sort by duration (descending - longest first)
@results = sort { $b->{duration_ms} <=> $a->{duration_ms} } @results;

# Print header
printf "%-10s %-35s %-28s %-28s %10s\n", 
    "Thread ID", "File", "Entry Time", "Return Time", "Duration(ms)";
print "=" x 120 . "\n";

# Print results
foreach my $result (@results) {
    printf "%-10s %-35s %-28s %-28s %10d\n",
        $result->{thread_id},
        $result->{file},
        $result->{entry_time},
        $result->{return_time},
        $result->{duration_ms};
}

# Report any unmatched entries
if (keys %entries) {
    print "\nWarning: Found ENTRY records without matching RETURN:\n";
    foreach my $thread_id (keys %entries) {
        printf "  Thread %s at %s\n", $thread_id, $entries{$thread_id}->{timestamp};
    }
}

# Parse timestamp to milliseconds since start of day
# Format: 11/20/24, 16:19:35:485 CST
sub parse_timestamp {
    my ($ts) = @_;
    
    # Extract time components
    if ($ts =~ m{(\d+)/(\d+)/(\d+),\s+(\d+):(\d+):(\d+):(\d+)}) {
        my ($month, $day, $year, $hour, $min, $sec, $ms) = ($1, $2, $3, $4, $5, $6, $7);
        
        # Convert to total milliseconds (simple approximation based on time of day)
        # This works for calculating durations within the same day
        return ($hour * 3600000) + ($min * 60000) + ($sec * 1000) + $ms;
    }
    
    return 0;
}
