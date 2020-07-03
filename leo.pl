#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use lib::relative 'lib';
use Emacs;

use FindBin;
use Path::Tiny;
use IPC::Run3;
use Getopt::Long qw/ GetOptions /;
use Term::ANSIColor qw/ :pushpop colored color /;

local $SIG{__WARN__} = sub { print colored( $_[0], 'yellow' ); };

my %options = ();
GetOptions(
    \%options,
    qw{ verbose debug }
) or die "Error in command line arguments\n";

my %dispatch = (
    "sync emacs" => sub { Emacs::sync(\%options) },
);

if ( $dispatch{ "@ARGV" } ) {
    $dispatch{ "@ARGV" }->();
} else {
    my $file = path($FindBin::RealBin . "/share/theo");
    my @insults = split/\n%\n/, $file->slurp;
    print LOCALCOLOR RED "[ERR] " if $options{verbose};
    say LOCALCOLOR YELLOW $insults[ rand @insults ];
}
