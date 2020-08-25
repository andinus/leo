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
sub tar_create { run3 ["/bin/tar", "cf", @_]; }
sub tar_list { run3 ["/bin/tar", "tvf", @_]; }

# Creating tars of files.
sub archive {
    my %archive_dispatch = (
        "documents" => sub {
            tar_create("/tmp/archive/documents.tar",
                       # Won't print "tar: Removing leading / from
                       # absolute path names in the archive" to
                       # STDERR.
                       "-C", "$ENV{HOME}/documents", ".");

            $? # tar returns 1 on errors.
                ? die "Archive creation failed :: $?\n"
                : say "$ENV{HOME}/documents archived.";
            tar_list("/tmp/archive/documents.tar") if $options{verbose};
        },
        "journal" => sub {
            tar_create("/tmp/archive/journal.tar",
                       "-C", "$ENV{HOME}/documents",
                       "andinus.org.gpg", "archive.org.gpg");

            $?
                ? die "Archive creation failed :: $?\n"
                : say "$ENV{HOME}/documents/andinus.org.gpg,
$ENV{HOME}/documents/archive.org.gpg archived.";
            tar_list("/tmp/archive/journal.tar") if $options{verbose};
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
                $ENV{HOME}/documents/archive.org.gpg};
    }
}
