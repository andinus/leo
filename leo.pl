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
    qw{ verbose }
) or die "Error in command line arguments\n";


# There will be multiple dispatch tables, to avoid confusion the main
# one is named %dispatch & others will be named like %archive_dispatch
# & so on.
my %dispatch = (
    "archive" => \&archive,
);

if ( $ARGV[0]
         and $dispatch{ $ARGV[0] } ) {
    $dispatch{ $ARGV[0] }->();
} elsif ( scalar @ARGV == 0 ) {
    HelpMessage();
} else {
    say "leo: no such option";
}

sub HelpMessage {
    say qq{Usage:
    archive
        Create an archive.};
}

sub rsync { run3 ["openrsync", @_]; }

# User must pass $tar_file first & `-C' optionally.
sub tar_create {
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

    say "Archive file: $tar_file\n";
    run3 ["/bin/tar", "cf", $tar_file, @_];

    $? # tar returns 1 on errors.
        ? die "Archive creation failed :: $?\n"
        # Print absolute paths for all archived files/directories.
        : say path($_)->absolute($cwd), " archived."
        foreach @archive_paths;

    print "\n" and tar_list($tar_file) if $options{verbose};
}
sub tar_list { run3 ["/bin/tar", "tvf", @_]; }

# Creating tars of files.
sub archive {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        localtime(time);

    $year += 1900; # $year contains the number of years since 1900.

    # $mon the month in the range 0..11 , with 0 indicating January
    # and 11 indicating December.
    my @months = qw( 01 02 03 04 05 06 07 08 09 10 11 12 );
    my $month = $months[$mon];

    my $ymd = "$year-$month-$mday";

    my %archive_dispatch = (
        "documents" => sub {
            tar_create("/tmp/archive/documents_$ymd.tar",
                       "-C", "$ENV{HOME}/documents", ".");
        },
        "journal" => sub {
            tar_create("/tmp/archive/journal_$ymd.tar",
                       "-C", "$ENV{HOME}/documents",
                       "andinus.org.gpg", "archive.org.gpg");
        },
        "ssh" => sub {
            tar_create("/tmp/archive/ssh_$ymd.tar",
                       "-C", "$ENV{HOME}/.ssh", ".");
        },
    );

    shift @ARGV;
    if ( $ARGV[0]
             and $archive_dispatch{ $ARGV[0] } ) {
        path("/tmp/archive")->mkpath; # Create archive directory.
        $archive_dispatch{ $ARGV[0] }->();
    } elsif ( scalar @ARGV == 0 ) {
        archive_HelpMessage();
    } else {
        say "leo/archive: no such option";
    }

    sub archive_HelpMessage {
        say qq{Archive files to /tmp/archive.

Usage:
    documents
        Archive $ENV{HOME}/documents
    journal
        Archive $ENV{HOME}/documents/andinus.org.gpg,
                $ENV{HOME}/documents/archive.org.gpg
    ssh
        Archive $ENV{HOME}/.ssh};
    }
}
