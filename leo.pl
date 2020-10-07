#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use IPC::Run3;
use Path::Tiny;
use Getopt::Long qw/ GetOptions /;

my %options = (
    encrypt => $ENV{LEO_ENCRYPT},
    sign => $ENV{LEO_SIGN},
    delete => $ENV{LEO_DELETE},
);

GetOptions(
    \%options,
    qw{ verbose encrypt sign delete help }
) or die "Error in command line arguments\n";

# Config file for leo.
my $config_file = $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config";
$config_file .= "/leo.pl";

require "$config_file";

my $ymd = ymd(); # YYYY-MM-DD.
my $backup_dir = get_backup_dir() || "/tmp/backups";
$backup_dir .= "/$ymd";

path($backup_dir)->mkpath; # Create backup directory.
my $prof;


my %profile = get_profile();
my $gpg_fingerprint = get_gpg_fingerprint();
my $gpg_bin = get_gpg_bin();

HelpMessage() and exit 0 if scalar @ARGV == 0 or $options{help};
foreach my $arg ( @ARGV ) {
    $prof = $arg; # Set $prof.
    if ( $profile{ $arg } ) {
        say "++++++++********++++++++";

        # No encryption for journal profile.
        my $tmp = $options{encrypt} and undef $options{encrypt}
            if $prof eq "journal" and $options{encrypt};

        # Deref the array here because we want flattened list.
        backup("$backup_dir/${arg}.tar", $profile{$arg}->@*);

        $options{encrypt} = $tmp if $prof eq "journal";
    } elsif ( -e $arg ) {
        # If the file/directory exist then create a new profile & run
        # backup.
        say "++++++++********++++++++";
        backup("$backup_dir/${arg}.tar",
               # backup() is expecting path relative to $ENV{HOME}.
               path($arg)->relative($ENV{HOME}));
    } else {
        warn "[WARN] leo: no such profile :: `$arg' \n";
    }
}

# User must pass $tar_file first.
sub backup {
    my $tar_file = shift @_;
    my @backup_paths = @_;

    say "Backup: $tar_file";
    warn "[WARN] $tar_file exists, might overwrite.\n" if -e $tar_file;
    print "\n";
    # All paths should be relative to $ENV{HOME}.
    tar_create($tar_file, "-C", $ENV{HOME}, @_);

    $? # tar returns 1 on errors.
        ? die "Backup creation failed :: $?\n"
        # Print absolute paths for all backup files/directories.
        : say path($_)->absolute($ENV{HOME}), " backed up."
        foreach @backup_paths;

    print "\n" and tar_list($tar_file) if $options{verbose};
    encrypt_sign($tar_file) if $options{encrypt} or $options{sign};
}

# Encrypt, Sign backups.
sub encrypt_sign() {
    my $file = shift @_;
    my @options = ();
    push @options, "--recipient", $gpg_fingerprint, "--encrypt"
        if $options{encrypt};
    push @options, "--sign" if $options{sign};
    push @options, "--verbose" if $options{verbose};

    say "\nEncrypt/Sign: $file";
    warn "[WARN] $file.gpg exists, might overwrite.\n" if -e "$file.gpg";

    run3 [$gpg_bin, "--yes", "-o", "$file.gpg", @options, $file];

    $? # We assume non-zero is an error.
        ? die "Encrypt/Sign failed :: $?\n"
        : print "\nOutput: $file.gpg";
    print " [Encrypted]" if $options{encrypt};
    print " [Signed]" if $options{sign};
    print "\n";

    unlink $file and say "$file deleted."
        or warn "[WARN] Could not delete $file: $!\n"
        if $options{delete};
}

sub HelpMessage {
    say qq{Backup files to $backup_dir.

Profile:};
    foreach my $prof (sort keys %profile) {
        next if substr($prof, 0, 1) eq "."; # Profiles starting with a
                                            # dot will have alias.
        print "    $prof\n";
        print "        $_\n" foreach $profile{$prof}->@*;
    }
    say qq{
Options:
    --encrypt
        Encrypt files with $gpg_fingerprint
    --sign
        Sign files with $gpg_fingerprint
    --delete
        Delete the tar file after running $gpg_bin
    --verbose
    --help};
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

    $mday = sprintf "%02d", $mday;
    return "$year-$month-$mday";
}
