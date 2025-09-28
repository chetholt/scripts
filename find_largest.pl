#!/usr/bin/perl -w

use strict;
use File::Find;
use File::Basename;
use Getopt::Long;

# Global variables
my @files = ();
my %dir_sizes = ();
my $search_dir = '.';
my $num_results = 20;
my $help = 0;

# Parse command line options
GetOptions(
    'directory|d=s' => \$search_dir,
    'number|n=i'    => \$num_results,
    'help|h'        => \$help
) or die "Error parsing options!\n";

if ($help) {
    print_usage();
    exit 0;
}

# Use first argument as directory if not specified with option
if (@ARGV && !$help) {
    $search_dir = $ARGV[0];
    $num_results = $ARGV[1] if defined $ARGV[1];
}

# Check if directory exists
die "Error: Directory '$search_dir' does not exist or is not accessible.\n" 
    unless -d $search_dir;

print "Searching for largest files and directories in: $search_dir\n";
print "Showing top $num_results results...\n\n";

# Start timing
my $start_time = time();

# Find all files and directories
print "Scanning files and directories...\n";

find(\&process_item, $search_dir);

my $scan_time = time() - $start_time;
print "Scan completed in $scan_time seconds.\n\n";

# Sort files by size (descending)
@files = sort { $b->[0] <=> $a->[0] } @files;

# Calculate directory sizes by summing up file sizes
print "Calculating directory sizes...\n";
calculate_directory_sizes();

# Sort directories by size (descending)
my @sorted_dirs = sort { $dir_sizes{$b} <=> $dir_sizes{$a} } keys %dir_sizes;

# Display results
print_results();

# Print usage information
sub print_usage {
    print <<EOF;
Usage: $0 [options] [directory] [number_of_results]

Options:
    -d, --directory DIR    Directory to search (default: current directory)
    -n, --number NUM       Number of results to show (default: 20)
    -h, --help            Show this help message

Examples:
    $0                          # Search current directory, show top 20
    $0 /path/to/dir             # Search specific directory
    $0 /path/to/dir 10          # Search directory, show top 10
    $0 -d /path/to/dir -n 15    # Using options
EOF
}

# Process each file/directory found
sub process_item {
    my $full_path = $File::Find::name;
    my $relative_path = $full_path;
    
    # Convert absolute path to relative if we're searching current directory
    if ($search_dir eq '.') {
        $relative_path =~ s/^.\///;
    }
    
    # Get file stats
    my @stat = lstat($full_path);
    return unless @stat;  # Skip if we can't stat the file
    
    my $size = $stat[7];
    my $is_dir = -d $full_path;
    
    # Store file information (including directories as files for now)
    unless ($is_dir) {
        push @files, [$size, $relative_path, 'file'];
    }
    
    # Initialize directory size tracking
    if ($is_dir) {
        $dir_sizes{$relative_path} = 0 unless exists $dir_sizes{$relative_path};
    }
}

# Calculate directory sizes by summing up contained files
sub calculate_directory_sizes {
    # First, add all file sizes to their containing directories
    foreach my $file_ref (@files) {
        my ($size, $path, $type) = @$file_ref;
        
        # Get all parent directories of this file
        my $dir = dirname($path);
        
        # Add file size to all parent directories
        while ($dir && $dir ne '.' && $dir ne '/') {
            $dir_sizes{$dir} += $size if exists $dir_sizes{$dir};
            $dir = dirname($dir);
        }
        
        # Also add to root search directory if it's not '.'
        if ($search_dir ne '.') {
            $dir_sizes{$search_dir} += $size if exists $dir_sizes{$search_dir};
        }
    }
}

# Convert bytes to human readable format
sub human_readable {
    my $size = shift;
    
    if ($size >= 1073741824) {
        return sprintf("%.1fG", $size / 1073741824);
    } elsif ($size >= 1048576) {
        return sprintf("%.1fM", $size / 1048576);
    } elsif ($size >= 1024) {
        return sprintf("%.1fK", $size / 1024);
    } else {
        return "${size}B";
    }
}

# Print all results
sub print_results {
    # Print largest files
    print "=" x 50 . "\n";
    print "LARGEST FILES:\n";
    print "=" x 50 . "\n";
    printf "%-12s %s\n", "SIZE", "FILE";
    print "-" x 50 . "\n";
    
    my $count = 0;
    foreach my $file_ref (@files) {
        last if $count >= $num_results;
        my ($size, $path, $type) = @$file_ref;
        printf "%-12s %s\n", human_readable($size), $path;
        $count++;
    }
    
    # Print largest directories
    print "\n" . "=" x 50 . "\n";
    print "LARGEST DIRECTORIES:\n";
    print "=" x 50 . "\n";
    printf "%-12s %s\n", "SIZE", "DIRECTORY";
    print "-" x 50 . "\n";
    
    $count = 0;
    foreach my $dir (@sorted_dirs) {
        last if $count >= $num_results;
        # Skip the root directory itself unless it's not '.'
        next if ($dir eq '.' || $dir eq $search_dir);
        printf "%-12s %s\n", human_readable($dir_sizes{$dir}), $dir;
        $count++;
    }
    
    # Combined summary
    print "\n" . "=" x 60 . "\n";
    print "COMBINED SUMMARY (TOP $num_results):\n";
    print "=" x 60 . "\n";
    printf "%-12s %-6s %s\n", "SIZE", "TYPE", "NAME";
    print "-" x 60 . "\n";
    
    # Create combined array with type indicators
    my @combined = ();
    
    # Add files
    foreach my $file_ref (@files) {
        my ($size, $path, $type) = @$file_ref;
        push @combined, [$size, 'FILE', $path];
    }
    
    # Add directories (skip root)
    foreach my $dir (@sorted_dirs) {
        next if ($dir eq '.' || $dir eq $search_dir);
        push @combined, [$dir_sizes{$dir}, 'DIR', $dir];
    }
    
    # Sort combined list and show top results
    @combined = sort { $b->[0] <=> $a->[0] } @combined;
    
    $count = 0;
    foreach my $item (@combined) {
        last if $count >= $num_results;
        my ($size, $type, $name) = @$item;
        printf "%-12s %-6s %s\n", human_readable($size), $type, $name;
        $count++;
    }
    
    # Summary statistics
    my $total_files = scalar @files;
    my $total_dirs = scalar keys %dir_sizes;
    my $total_time = time() - $start_time;
    
    print "\n";
    print "Summary: Found $total_files files and $total_dirs directories in $total_time seconds\n";
    
    # Show total size
    my $total_size = 0;
    $total_size += $_->[0] foreach @files;
    print "Total size of files: " . human_readable($total_size) . "\n";
}