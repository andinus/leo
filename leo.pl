#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use Path::Tiny;
use IPC::Run3;

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
        Create an archive.}
}
