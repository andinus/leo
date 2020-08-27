#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use IPC::Run3;
use Path::Tiny;
use Getopt::Long qw/ GetOptions /;

my %options = ();
GetOptions(
    \%options,
    qw{ verbose encrypt sign delete }
) or die "Error in command line arguments\n";

my $gpg_fingerprint = "D9AE4AEEE1F1B3598E81D9DFB67D55D482A799FD";
my $archive_dir = "/tmp/archive";
my $ymd = ymd(); # YYYY-MM-DD.

# Dispatch table.
my %dispatch = (
    "documents" => sub {
        archive("$archive_dir/documents_$ymd.tar",
                "-C", "$ENV{HOME}/documents", ".");
    },
    "journal" => sub {
        archive("$archive_dir/journal_$ymd.tar",
                "-C", "$ENV{HOME}/documents",
                "andinus.org.gpg", "archive.org.gpg");
    },
    "ssh" => sub {
        archive("$archive_dir/ssh_$ymd.tar",
                "-C", "$ENV{HOME}/.ssh", ".");
    },
    "pass" => sub {
        archive("$archive_dir/pass_$ymd.tar",
                "-C", "$ENV{HOME}/.password-store", ".");
    },
);

# User must pass $tar_file first & `-C' optionally.
sub archive {
    my $tar_file = shift @_;

    my ( $cwd, @archive_paths );
    # Passing `-C' won't print "tar: Removing leading / from absolute
    # path names in the archive" to STDERR in some cases.
    if ( $_[0] eq "-C" ) {
        $cwd = $_[1];

        # Remove `-C' & cwd to get @archive_paths;
        my @tmp = @_;
        shift @tmp; shift @tmp;
        @archive_paths = @tmp;
    } else {
        @archive_paths = @_;
    }

    say "Archive: $tar_file";
    warn "[WARN] $tar_file exists, might overwrite.\n" if -e $tar_file;
    print "\n";

    tar_create($tar_file, @_);

    $? # tar returns 1 on errors.
        ? die "Archive creation failed :: $?\n"
        # Print absolute paths for all archived files/directories.
        : say path($_)->absolute($cwd), " archived."
        foreach @archive_paths;

    tar_list($tar_file) if $options{verbose};
    encrypt_sign($tar_file) if $options{encrypt} or $options{sign};
}

# Encrypt, Sign archives.
sub encrypt_sign() {
    my $file = shift @_;
    my @options = ("--recipient", $gpg_fingerprint);
    push @options, "--encrypt" if $options{encrypt};
    push @options, "--sign" if $options{sign};
    push @options, "--verbose" if $options{verbose};

    say "\nEncrypt/Sign: $file";
    run3 ["gpg2", "--yes", "-o", "$file.gpg", @options, $file];
    warn "[WARN] $file.gpg exists, might overwrite.\n" if -e "$file.gpg";
    say "\nOutput: $file.gpg";

    unlink $file and say "$file deleted."
        or warn "[WARN] Could not delete $file: $!\n";
}

sub HelpMessage {
    say qq{Archive files to $archive_dir.

Usage:
    documents
        Archive $ENV{HOME}/documents
    journal
        Archive $ENV{HOME}/documents/andinus.org.gpg,
                $ENV{HOME}/documents/archive.org.gpg
    ssh
        Archive $ENV{HOME}/.ssh
    pass
        Archive $ENV{HOME}/.password-store

Options:
    --encrypt
        Encrypt files with $gpg_fingerprint
    --sign
        Sign files with $gpg_fingerprint
    --delete
        Delete the archive after running gpg2
    --verbose};
}

if ( $ARGV[0] and $dispatch{ $ARGV[0] } ) {
    path($archive_dir)->mkpath; # Create archive directory.
    $dispatch{ $ARGV[0] }->();
} elsif ( scalar @ARGV == 0 ) {
    HelpMessage();
} else {
    die say "leo: no such option\n";
}

sub tar_create { run3 ["/bin/tar", "cf", @_]; }
sub tar_list { run3 ["/bin/tar", "tvf", @_]; }

sub ymd {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        localtime(time);

    $year += 1900; # $year contains the number of years since 1900.

    # $mon the month in the range 0..11 , with 0 indicating January
    # and 11 indicating December.
    my @months = qw( 01 02 03 04 05 06 07 08 09 10 11 12 );
    my $month = $months[$mon];

    return "$year-$month-$mday";
}
