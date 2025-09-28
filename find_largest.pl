#!/usr/bin/perl -w

use strict;
use File::Find;
use File::Basename;
use Getopt::Long;

# Global variables
my @files = ();
my %dir_sizes = ();
my @directories = ();
my $search_dir = '.';
my $num_results = 20;
my $help = 0;
my $verbose = 0;
my $max_depth = 0;
my $file_count = 0;
my $dir_count = 0;

# Parse command line options
GetOptions(
    'directory|d=s' => \$search_dir,
    'number|n=i'    => \$num_results,
    'verbose|v'     => \$verbose,
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
print "Scanning files and directories recursively...\n";
if ($verbose) {
    print "Starting recursive scan from: $search_dir\n";
}

# Use File::Find with explicit options to ensure full recursion
find({
    wanted => \&process_item,
    follow => 0,        # Don't follow symbolic links
    no_chdir => 1,     # Don't change directory during traversal
}, $search_dir);

my $scan_time = time() - $start_time;
print "Scan completed in $scan_time seconds.\n";
print "Found $file_count files and $dir_count directories\n";
print "Maximum directory depth: $max_depth\n" if $verbose;
print "\n";

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
    -v, --verbose         Show verbose output with progress information
    -h, --help            Show this help message

Examples:
    $0                          # Search current directory, show top 20
    $0 /path/to/dir             # Search specific directory
    $0 /path/to/dir 10          # Search directory, show top 10
    $0 -d /path/to/dir -n 15    # Using options
    $0 -v /path/to/dir          # Verbose mode
EOF
}

# Process each file/directory found
sub process_item {
    my $full_path = $File::Find::name;
    my $relative_path = $full_path;
    
    # Convert to relative path if searching current directory
    if ($search_dir eq '.') {
        $relative_path =~ s/^.\/;//;
    } elsif ($search_dir ne '/') {
        # Remove the search directory prefix for cleaner output
        my $search_prefix = $search_dir;
        $search_prefix =~ s/\/$//;  # Remove trailing slash
        $relative_path =~ s/^\Q$search_prefix\E\/?//;
    }
    
    # Calculate directory depth for statistics
    my $depth = ($relative_path =~ tr/\//\//);  # Count forward slashes
    $max_depth = $depth if $depth > $max_depth;
    
    # Get file stats
    my @stat = lstat($full_path);
    unless (@stat) {
        print "Warning: Cannot access $full_path\n" if $verbose;
        return;
    }
    
    my $size = $stat[7];
    my $is_dir = -d $full_path;
    
    if ($is_dir) {
        $dir_count++;
        # Store directory info
        push @directories, [$relative_path, $full_path];
        $dir_sizes{$relative_path} = 0;
        
        # Progress output for verbose mode
        if ($verbose && $dir_count % 1000 == 0) {
            print "Processed $dir_count directories, $file_count files...\n";
        }
    } else {
        $file_count++;
        # Store file information
        push @files, [$size, $relative_path, 'file'];
        
        # Progress output for verbose mode
        if ($verbose && $file_count % 10000 == 0) {
            print "Processed $file_count files, $dir_count directories...\n";
        }
    }
}

# Calculate directory sizes by summing up contained files
sub calculate_directory_sizes {
    print "Calculating directory sizes...\n";
    
    # Initialize all directories to 0
    foreach my $dir_ref (@directories) {
        my ($rel_path, $full_path) = @$dir_ref;
        $dir_sizes{$rel_path} = 0;
    }
    
    # Add each file's size to all its parent directories
    my $processed = 0;
    foreach my $file_ref (@files) {
        my ($size, $file_path, $type) = @$file_ref;
        
        # Get the directory containing this file
        my $file_dir = dirname($file_path);
        
        # Add file size to this directory and all parent directories
        my $current_dir = $file_dir;
        while ($current_dir && $current_dir ne '.' && $current_dir ne '/' && $current_dir ne '') {
            if (exists $dir_sizes{$current_dir}) {
                $dir_sizes{$current_dir} += $size;
            }
            # Move to parent directory
            my $parent = dirname($current_dir);
            last if $parent eq $current_dir; # Avoid infinite loop
            $current_dir = $parent;
        }
        
        # Also add to root directory if we have files in the root
        if ($file_dir eq '.' || $file_dir eq '') {
            # This file is in the root of our search, add to search directory
            my $root_key = '';
            foreach my $dir_ref (@directories) {
                my ($rel_path, $full_path) = @$dir_ref;
                if ($rel_path eq '' || $rel_path eq '.') {
                    $dir_sizes{$rel_path} += $size;
                    last;
                }
            }
        }
        
        $processed++;
        if ($verbose && $processed % 50000 == 0) {
            print "Calculated sizes for $processed files...\n";
        }
    }
    
    # Remove directories with zero size (they might be empty or inaccessible)
    foreach my $dir (keys %dir_sizes) {
        delete $dir_sizes{$dir} if $dir_sizes{$dir} == 0;
    }
    
    if ($verbose) {
        my $dir_with_sizes = scalar(keys %dir_sizes);
        print "Found $dir_with_sizes directories with content\n";
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