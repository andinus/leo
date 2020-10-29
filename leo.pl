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
    signify => $ENV{LEO_SIGNIFY},
);

GetOptions(
    \%options,
    qw{ verbose encrypt sign signify delete help }
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

    # Set global values to local profiles.
    foreach (qw( encrypt sign signify )) {
        $profile{$section}{$_} = $options{$_};
    }

    foreach my $key (sort keys $config->{$section}->%*) {
        # Override encrypt & sign options with local values.
        if ($key eq "encrypt"
                or $key eq "sign"
                or $key eq "signify") {
            $profile{$section}{$key} = $config->{$section}->{$key};
            next;
        }

        push @{ $profile{$section}{exclude} }, $key and next
            if $config->{$section}->{$key} eq "exclude";

        push @{ $profile{$section}{backup} }, $key;
    }
}

my $date = date();
my $backup_dir = $options{backup_dir} || "/tmp/backups";
# $backup_dir .= "/$date";

path($backup_dir)->mkpath; # Create backup directory.

my $gpg_fingerprint = $options{gpg_fingerprint} || "`nil'";
my @gpg_recipients = split / /, $options{gpg_recipients};
my $gpg_bin = $options{gpg_bin} || "gpg";

# Print help.
HelpMessage() and exit 0 if scalar @ARGV == 0 or $options{help};

# Parsing the arguments.
foreach my $prof ( @ARGV ) {
    if ( $profile{ $prof } ) {
        say "++++++++********++++++++";

        path("$backup_dir/${prof}")->mkpath; # Create backup directory.
        backup($prof);

        # It will fail because signify will look for "${prof}.tar" but
        # delete option would've deleted it. I can make signify look
        # for "${prof}.tar.gpg" but this is fine for now.
        warn "[WARN] signify might fail if used with gpg\n"
            if ($profile{$prof}{signify}
                and ($profile{$prof}{encrypt} or $profile{$prof}{sign}));

        signify($prof) if $profile{$prof}{signify};
        encrypt_sign($prof) if $profile{$prof}{sign} or $profile{$prof}{encrypt};
    } else {
        warn "[WARN] leo: no such profile :: `$prof' \n";
    }
}

sub backup {
    my $prof = shift @_;
    my $tar_file = "$backup_dir/${prof}/${date}.tar";

    # Make @backup_paths relative to '/'.
    my @backup_paths;

    my @tmp_exclude;
    @tmp_exclude = $profile{$prof}{exclude}->@*
        if $profile{$prof}{exclude};
    my %exclude_paths = map { $_ => 1 } @tmp_exclude;

    my @tmp_paths = $profile{$prof}{backup}->@*;
    while (my $path = shift @tmp_paths) {
        if (-d $path) {
            my $iter = path($path)->iterator();
            while ( my $path = $iter->() ) {
                push @backup_paths, path( $path )->relative('/')
                    unless $exclude_paths{$path};
            }
        } else {
            push @backup_paths, path( $path )->relative('/');
        }
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
}

# Encrypt, Sign backups.
sub encrypt_sign {
    my $prof = shift @_;
    my $file = "$backup_dir/${prof}/${date}.tar";

    my @options = ();
    push @options, "--default-key", $gpg_fingerprint;

    if ( $profile{$prof}{encrypt} ) {
        push @options, "--encrypt";
        push @options, "--recipient", $gpg_fingerprint;
        push @options, "--recipient", $_
            foreach @gpg_recipients;
    }

    push @options, "--sign" if $profile{$prof}{sign};
    push @options, "--verbose" if $options{verbose};

    say "\nEncrypt/Sign: $file";
    warn "[WARN] $file.gpg exists, might overwrite.\n" if -e "$file.gpg";

    run3 [$gpg_bin, "--yes", "-o", "$file.gpg", @options, $file];

    $? # We assume non-zero is an error.
        ? die "Encrypt/Sign failed :: $?\n"
        : print "\nOutput: $file.gpg";
    print " [Encrypted]" if $profile{$prof}{encrypt};
    print " [Signed]" if $profile{$prof}{sign};
    print "\n";

    unlink $file and say "$file deleted."
        or warn "[WARN] Could not delete $file: $!\n";
}

sub signify {
    my $prof = shift @_;
    my $file = "$backup_dir/${prof}/${date}.tar";

    die "\nSignify: seckey doesn't exist\n"
        unless $options{signify_seckey} and -e $options{signify_seckey};

    my @options = ("-S");
    push @options, "-s", $options{signify_seckey};
    push @options, "-m", $file;
    push @options, "-x", "$file.sig";

    say "\nSignify: $file";
    warn "[WARN] $file.sig exists, might overwrite.\n" if -e "$file.sig";

    run3 ["signify", @options];

    $? # We assume non-zero is an error.
        ? die "Signify failed :: $?\n"
        : print "\nOutput: $file.sig";
    print " [Signify]";
    print "\n";
}

sub HelpMessage {
    say qq{Backup files to $backup_dir.

Profile:};
    foreach my $prof (sort keys %profile) {
        print "    $prof";
        print " [Encrypt]" if $profile{$prof}{encrypt};
        print " [Sign]" if $profile{$prof}{sign};
        print " [Signify]" if $profile{$prof}{signify};
        print "\n";
        print "        $_\n" foreach $profile{$prof}{backup}->@*;
        print "\n";
    }
    print qq{Options:
    --encrypt };
    print "[Enabled]" if $options{encrypt};
    print qq{
        Encrypt files with $gpg_fingerprint\n
    --sign };
    print "[Enabled]" if $options{sign};
    print qq{
        Sign files with $gpg_fingerprint\n
    --signify };
    print "[Enabled]" if $options{signify};
    print qq{
        Sign with signify(1)\n
    --verbose
    --help
};
}

sub tar_create { run3 ["/bin/tar", "cf", @_]; }
sub tar_list { run3 ["/bin/tar", "tvf", @_]; }

sub date {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time);

    $year += 1900; # $year contains the number of years since 1900.

    # $mon the month in the range 0..11 , with 0 indicating January
    # and 11 indicating December.
    my @months = qw( 01 02 03 04 05 06 07 08 09 10 11 12 );
    my $month = $months[$mon];

    # Pad by 2 zeros.
    $mday = sprintf "%02d", $mday;
    $hour = sprintf "%02d", $hour;
    $min = sprintf "%02d", $min;
    $min = sprintf "%02d", $sec;

    return "$year-$month-${mday}T${hour}:${min}:${sec}Z";
}
