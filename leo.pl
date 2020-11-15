#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use IPC::Run3;
use Path::Tiny;
use Config::Tiny;
use POSIX qw(strftime);
use Getopt::Long qw/ GetOptions /;

my $version = "leo v0.4.0";

# Options.
my %options = (
    L_SIGN => $ENV{L_SIGN},
    L_GZIP => $ENV{L_GZIP},
    L_ENCRYPT => $ENV{L_ENCRYPT},
    L_SIGNIFY => $ENV{L_SIGNIFY},
);

GetOptions(
    \%options,
    qw{ verbose help version }
) or die "leo: error in command line arguments\n";

# Print version.
print $version, "\n" and exit 0 if $options{version};

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

# Die if user is using older config format.
die "leo: old config format detected\n"
    if exists $options{encrypt} or exists $options{sign};

my %profile;

foreach my $prof (sort keys $config->%*) {
    next if $prof eq "_";

    # Set global values to local profiles.
    foreach (qw(L_ENCRYPT L_SIGN L_SIGNIFY L_GZIP)) {
        $profile{$prof}{$_} = $options{$_};
    }

    foreach my $key (sort keys $config->{$prof}->%*) {
        # $profile{$prof} contains config values ($), {exclude}
        # (@), {backup} (@).

        # Set config values.
        if ( length($key) >= 2
             and substr($key, 0, 2) eq "L_") {
            $profile{$prof}{$key} = $config->{$prof}->{$key};
            next;
        }

        push @{ $profile{$prof}{exclude} }, $key and next
            if $config->{$prof}->{$key} eq "exclude";

        push @{ $profile{$prof}{backup} }, $key;
    }
}

my $date = date();
my $backup_dir = $options{backup_dir} || "/tmp/backups";

my $gpg_fingerprint = $options{gpg_fingerprint} || "`nil'";

my @gpg_recipients;
@gpg_recipients = split / /, $options{gpg_recipients}
    if $options{gpg_recipients};

my $gpg_bin = $options{gpg_bin} || "gpg";

# Print help.
HelpMessage() and exit 0 if scalar @ARGV == 0 or $options{help};

# Parsing the arguments.
foreach my $prof ( @ARGV ) {
    if ( $profile{ $prof } ) {
        say "++++++++********++++++++";

        my $file = "$backup_dir/${prof}/${date}.tar";
        $file .= ".gz" if $profile{$prof}{L_GZIP};

        path("$backup_dir/${prof}")->mkpath; # Create backup directory.
        backup($prof, $file);

        encrypt_sign($prof, $file) if $profile{$prof}{L_SIGN} or $profile{$prof}{L_ENCRYPT};

        # gpg would've removed the `.tar' file so we sign the
        # encrypted file instead.
        my $encrypted_file = "${file}.gpg";
        $file = $encrypted_file if $profile{$prof}{L_SIGN} or $profile{$prof}{L_ENCRYPT};
        signify($prof, $file) if $profile{$prof}{L_SIGNIFY};
    } else {
        warn "[WARN] leo: no such profile :: `$prof' \n";
    }
}

sub backup {
    my $prof = shift @_;
    my $tar_file = shift @_;

    my @options;
    push @options, "-z" if $profile{$prof}{L_GZIP};

    # Make @backup_paths relative to '/'.
    my @backup_paths;

    my @tmp_exclude;
    @tmp_exclude = $profile{$prof}{exclude}->@*
        if $profile{$prof}{exclude};
    my %exclude_paths = map { $_ => 1 } @tmp_exclude;

    my @tmp_paths = $profile{$prof}{backup}->@*;
    while (my $path = shift @tmp_paths) {
        # If it's a directory then check if we need to exclude any
        # child path.
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
    tar_create($tar_file, @options, "-C", '/', @backup_paths);

    $? # tar returns 1 on errors.
        ? die "Backup creation failed :: $?\n"
        # Print absolute paths for all backup files/directories.
        : say path($_)->absolute('/'), " backed up." foreach @backup_paths;

    path($tar_file)->chmod(0600)
        and print "Changed `$tar_file' mode to 0600.\n";
    print "File was compressed with gzip(1)\n" if $profile{$prof}{L_GZIP};

    print "\n" and tar_list($tar_file) if $options{verbose};
}

# Encrypt, Sign backups.
sub encrypt_sign {
    my $prof = shift @_;
    my $file = shift @_;

    my @options = ();
    push @options, "--default-key", $gpg_fingerprint;

    if ( $profile{$prof}{L_ENCRYPT} ) {
        push @options, "--encrypt";
        push @options, "--recipient", $gpg_fingerprint;
        push @options, "--recipient", $_
            foreach @gpg_recipients;
    }

    push @options, "--sign" if $profile{$prof}{L_SIGN};
    push @options, "--verbose" if $options{verbose};

    say "\nEncrypt/Sign: $file";
    warn "[WARN] $file.gpg exists, might overwrite.\n" if -e "$file.gpg";

    run3 [$gpg_bin, "--yes", "-o", "$file.gpg", @options, $file];

    $? # We assume non-zero is an error.
        ? die "Encrypt/Sign failed :: $?\n"
        : print "\nOutput: $file.gpg";
    print " [Encrypted]" if $profile{$prof}{L_ENCRYPT};
    print " [Signed]" if $profile{$prof}{L_SIGN};
    print "\n";

    unlink $file and say "$file deleted."
        or warn "[WARN] Could not delete $file: $!\n";

    path("$file.gpg")->chmod(0600)
        and print "Changed `$file.gpg' mode to 0600.\n";
}

sub signify {
    my $prof = shift @_;
    my $file = shift @_;

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

+ means included
- means excluded

Profile:};
    foreach my $prof (sort keys %profile) {
        print "    $prof";
        print " [Encrypt]" if $profile{$prof}{L_ENCRYPT};
        print " [Sign]" if $profile{$prof}{L_SIGN};
        print " [Signify]" if $profile{$prof}{L_SIGNIFY};
        print " [gzip]" if $profile{$prof}{L_GZIP};
        print "\n";
        print "        + $_\n" foreach $profile{$prof}{backup}->@*;
        print "        - $_\n" foreach $profile{$prof}{exclude}->@*;
        print "\n";
    }
    print qq{Options:
    --version [$version]
    --verbose
    --help
};
}

sub tar_create { run3 ["/bin/tar", "cf", @_]; }
sub tar_list { run3 ["/bin/tar", "tvf", @_]; }

sub date { return strftime '%FT%T%z', gmtime() }
