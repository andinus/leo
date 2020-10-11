#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use IPC::Run3;
use Path::Tiny;
use Config::Tiny;
use Getopt::Long qw/ GetOptions /;

# Options.

my %options = (
    encrypt => $ENV{LEO_ENCRYPT},
    sign => $ENV{LEO_SIGN},
    delete => $ENV{LEO_DELETE},
);

GetOptions(
    \%options,
    qw{ verbose encrypt sign delete help }
) or die "Error in command line arguments\n";

# Configuration.

my $config_file = $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config";
$config_file .= "/leo.conf";

my $config = Config::Tiny->new;
$config = Config::Tiny->read( $config_file )
    or die "Cannot read config file: `$config_file'\n";

# Reading config file.

foreach my $key (sort keys $config->{_}->%*) {
    $options{$key} = $config->{_}->{$key};
}

my %profile;

foreach my $section (sort keys $config->%*) {
    next if $section eq "_";
    foreach my $key (sort keys $config->{$section}->%*) {
        push @{ $profile{$section} }, $key;
    }
}

my $ymd = ymd(); # YYYY-MM-DD.
my $backup_dir = $options{backup_dir} || "/tmp/backups";
$backup_dir .= "/$ymd";

path($backup_dir)->mkpath; # Create backup directory.

my $gpg_fingerprint = $options{gpg_fingerprint};
my $gpg_bin = $options{gpg_bin};

# Print help.
HelpMessage() and exit 0 if scalar @ARGV == 0 or $options{help};

# Parsing the arguments.
foreach my $arg ( @ARGV ) {
    if ( $profile{ $arg } ) {
        say "++++++++********++++++++";

        # Deref the array here because we want flattened list.
        backup("$backup_dir/${arg}.tar", $profile{$arg}->@*);
    } elsif ( -e $arg ) {
        # If the file/directory exist then create a new profile & run
        # backup.
        say "++++++++********++++++++";
        warn "[WARN] leo: creating temporary profile: `$arg'\n";
        backup("$backup_dir/${arg}.tar", $arg);
    } else {
        warn "[WARN] leo: no such profile :: `$arg' \n";
    }
}

sub backup {
    my $tar_file = shift @_;

    # Make @backup_paths relative to '/'.
    my @backup_paths;
    while (my $path = shift @_) {
        push @backup_paths, path( $path )->relative('/');
    }

    say "Backup: $tar_file";
    warn "[WARN] $tar_file exists, might overwrite.\n" if -e $tar_file;
    print "\n";

    # All paths should be relative to '/'.
    tar_create($tar_file, "-C", '/', @backup_paths);

    $? # tar returns 1 on errors.
        ? die "Backup creation failed :: $?\n"
        # Print absolute paths for all backup files/directories.
        : say path($_)->absolute('/'), " backed up." foreach @backup_paths;

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
        print "    $prof\n";
        print "        $_\n" foreach $profile{$prof}->@*;
    }
    print qq{
Options:
    --encrypt };
    print "[Enabled]" if $options{encrypt};
    print qq{
        Encrypt files with $gpg_fingerprint\n
    --sign };
        print "[Enabled]" if $options{sign};
    print qq{
        Sign files with $gpg_fingerprint\n
    --delete };
            print "[Enabled]" if $options{delete};
    print qq{
        Delete the tar file after running $gpg_bin\n
    --verbose
    --help
};
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
