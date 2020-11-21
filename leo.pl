#!/usr/bin/perl

use strict;
use warnings;

use IPC::Run3;
use Path::Tiny;
use Config::Tiny;
use POSIX qw(strftime);

die "usage: leo [-hpvV] <profile>\n" unless scalar @ARGV;

my ($VERBOSE, $PRINT_PROFILES, $PRINT_PROFILES_VERBOSE);
my $VERSION = "v0.5.1";

# Dispatch table to be parsed before url.
my %dispatch = (
    '-V'  => sub { print "Leo $VERSION\n"; exit; },
    '-v'  => sub { $VERBOSE = 1; },
    '-h'  => \&HelpMessage,
    '-p'  => sub { $PRINT_PROFILES = 1; },
    '-P'  => sub { $PRINT_PROFILES = 1; $PRINT_PROFILES_VERBOSE = 1; },
);
if (exists $dispatch{$ARGV[0]}) {
    # shift @ARGV to get profile in next shift.
    $dispatch{shift @ARGV}->();
}

# Set umask.
umask 077;

# Configuration.
my $config_file = $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config";
$config_file .= "/leo.conf";

my $config = Config::Tiny->new;
$config = Config::Tiny->read( $config_file )
    or die "Cannot read config file: `$config_file'\n";

# Reading config file.
my %options;
foreach my $key (sort keys $config->{_}->%*) {
    $options{$key} = $config->{_}->{$key};
}

my %profile;
# Iterate through all sections in config file, we call this profile.
foreach my $prof (sort keys $config->%*) {
    next if $prof eq "_";

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

my $backup_dir = $options{backup_dir} || "/tmp/backups";
PrintProfiles() if $PRINT_PROFILES;

# Parsing the arguments.
foreach my $prof ( @ARGV ) {
    if ( $profile{ $prof } ) {
        print "--------  $prof";
        print " [GnuPG]" if $profile{$prof}{L_GnuPG};
        print " [Signify]" if $profile{$prof}{L_signify};
        print "\n";

        # Create backup directory.
        path("$backup_dir/${prof}")->mkpath;

        my $date = date();
        my $file = "$backup_dir/${prof}/${date}.tgz";

        run_tar($prof, $file);
        run_gnupg($prof, $file) and $file = "${file}.gpg"
            if $profile{$prof}{L_GnuPG};
        run_signify($prof, $file) if $profile{$prof}{L_signify};
    } else {
        warn "leo: no such profile :: `$prof' \n";
    }
}

sub run_tar {
    my $prof = shift @_;
    my $file = shift @_;

    my @options = ( "-c",
                    "-f", $file,
                    "-C", '/',
                    "-z");
    push @options, "-v" if $options{verbose};

    my @backup_paths;
    foreach my $path ($profile{$prof}{backup}->@*) {
        # If it's a directory then walk it upto 1 level.
        if (-d $path) {
            my $iter = path($path)->iterator();
            while ( my $iter_path = $iter->() ) {
                push @backup_paths, path( $iter_path );
            }
        } else {
            push @backup_paths, path( $path );
        }
    }

    # Remove files that are to be excluded.
    foreach my $exclude ($profile{$prof}{exclude}->@*) {
        @backup_paths = grep !/$exclude/, @backup_paths;
    }

    # All paths should be relative to '/.
    @backup_paths = map { $_->relative('/') } @backup_paths;

    run3 ["/bin/tar", @options, @backup_paths];
    $? # tar returns 1 on errors.
        ? die "Backup creation failed :: $?\n"
        : print "Backup: $file\n";
}

sub run_gnupg {
    my $prof = shift @_;
    my $file = shift @_;

    my @options = ( "--encrypt",
                    "--yes",
                    "-o", "${file}.gpg"
                );

    push @options,
        "--default-key", $options{gpg_fingerprint},
        "--recipient", $options{gpg_fingerprint}
        if $options{gpg_fingerprint};

    push @options, "--sign" unless $profile{$prof}{L_GnuPG_no_sign};

    # Add recipients.
    my @gpg_recipients;
    @gpg_recipients = split / /, $options{gpg_recipients}
        if $options{gpg_recipients};
    push @options, "--recipient", $_ foreach @gpg_recipients;

    push @options, "--verbose" if $options{verbose};

    run3 ["/usr/local/bin/gpg2", @options, $file];

    $? # We assume non-zero is an error.
        ? die "GnuPG failed :: $?\n"
        : print "GnuPG: $file.gpg\n";

    unlink $file or warn "leo: Could not delete `$file': $!\n";
}

sub run_signify {
    my $prof = shift @_;
    my $file = shift @_;

    my @options = ( "-S",
                    "-s", $options{signify_seckey},
                    "-m", $file,
                    "-x", "${file}.sig",
                );

    run3 ["signify", @options];
    $? # Non-zero exit code is an error.
        ? die "Signify failed :: $?\n"
        : print "Signify: ${file}.sig\n";
}

sub PrintProfiles {
    print "Profile:\n";
    foreach my $prof (sort keys %profile) {
        print "    $prof";
        print " [GnuPG]" if $profile{$prof}{L_GnuPG};
        print " [No Sign]" if $profile{$prof}{L_GnuPG_no_sign};
        print " [Signify]" if $profile{$prof}{L_signify};
        print "\n";

        if ($PRINT_PROFILES_VERBOSE) {
            print "        + $_\n" foreach $profile{$prof}{backup}->@*;
            print "        - $_\n" foreach $profile{$prof}{exclude}->@*;
            print "\n";
        }
    }
}
sub HelpMessage {
    print qq{Options:
    -V [$VERSION]
        Print version.
    -v
        Increase verbosity.
    -p
        Print profiles.
    -P
        Print profiles with all the files to backup/exclude.
    -h
        Print help.
};
    exit;
}

sub date { return strftime '%FT%T%z', localtime() }
