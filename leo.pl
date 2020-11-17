#!/usr/bin/perl

use strict;
use warnings;

use IPC::Run3;
use Path::Tiny;
use Config::Tiny;
use POSIX qw(strftime);
use Getopt::Long qw/ GetOptions /;

my $version = "leo v0.4.4";

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

my @gpg_recipients;
@gpg_recipients = split / /, $options{gpg_recipients}
    if $options{gpg_recipients};

my $gpg_bin = $options{gpg_bin} || "gpg";
warn "[WARN] \$gpg_bin is set to `$gpg_bin'"
    unless $gpg_bin =~ /^(gpg2?)$/;

# Print help.
HelpMessage() and exit 0 if scalar @ARGV == 0 or $options{help};

# Parsing the arguments.
foreach my $prof ( @ARGV ) {
    if ( $profile{ $prof } ) {
        print "--------  $prof";
        print " [Encrypt]" if $profile{$prof}{L_ENCRYPT};
        print " [Sign]"    if $profile{$prof}{L_SIGN};
        print " [Signify]" if $profile{$prof}{L_SIGNIFY};
        print " [gzip]"    if $profile{$prof}{L_GZIP};
        print "\n";

        my $file = "$backup_dir/${prof}/${date}.tar";
        $file .= ".gz" if $profile{$prof}{L_GZIP};

        path("$backup_dir/${prof}")->mkpath; # Create backup directory.
        backup($prof, $file);

        my $is_gpg_req = 1 if $profile{$prof}{L_SIGN} or $profile{$prof}{L_ENCRYPT};
        encrypt_sign($prof, $file) if $is_gpg_req;

        # gpg would've removed the `.tar' file.
        $file = "${file}.gpg" if $is_gpg_req;
        signify($prof, $file) if $profile{$prof}{L_SIGNIFY};
    } else {
        warn "[WARN] leo: no such profile :: `$prof' \n";
    }
}

sub backup {
    my $prof = shift @_;
    my $tar_file = shift @_;

    my @options = ("-C", "/");
    push @options, "-z" if $profile{$prof}{L_GZIP};

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

    # All paths should be relative to '/'.
    @backup_paths = map { $_->relative('/') } @backup_paths;

    tar_create($tar_file, @options, @backup_paths);
    $? # tar returns 1 on errors.
        ? die "Backup creation failed :: $?\n"
        : print "Backup: $tar_file\n";

    path($tar_file)->chmod(0600);
    print "File was compressed with gzip(1).\n"
        if $profile{$prof}{L_GZIP} and $options{verbose};

    tar_list($tar_file) if $options{verbose};
}

# Encrypt, Sign backups.
sub encrypt_sign {
    my $prof = shift @_;
    my $file = shift @_;

    my @options = ();
    push @options, "--default-key", $options{gpg_fingerprint}
        if $options{gpg_fingerprint};

    if ( $profile{$prof}{L_ENCRYPT} ) {
        push @options, "--encrypt";
        push @options, "--recipient", $options{gpg_fingerprint}
            if $options{gpg_fingerprint};
        push @options, "--recipient", $_
            foreach @gpg_recipients;
    }

    push @options, "--sign" if $profile{$prof}{L_SIGN};
    push @options, "--verbose" if $options{verbose};

    run3 [$gpg_bin, "--yes", "-o", "${file}.gpg", @options, $file];

    $? # We assume non-zero is an error.
        ? die "GPG failed :: $?\n"
        : print "GPG: $file.gpg\n";

    unlink $file or warn "[WARN] Could not delete `$file': $!\n";

    path("$file.gpg")->chmod(0600);
}

sub signify {
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

sub HelpMessage {
    print qq{Backup files to $backup_dir.

Profile:\n};
    foreach my $prof (sort keys %profile) {
        print "    $prof";
        if ($options{verbose}) {
            print " [Encrypt]" if $profile{$prof}{L_ENCRYPT};
            print " [Sign]" if $profile{$prof}{L_SIGN};
            print " [Signify]" if $profile{$prof}{L_SIGNIFY};
            print " [gzip]" if $profile{$prof}{L_GZIP};
            print "\n";

            print "        + $_\n" foreach $profile{$prof}{backup}->@*;
            print "        - $_\n" foreach $profile{$prof}{exclude}->@*;
        }
        print "\n";
    }
    print qq{Options:
    --version [$version]
    --verbose
    --help
};
}

sub tar_create { run3 ["/bin/tar", "cf", @_]; }
sub tar_list { print "\n"; run3 ["/bin/tar", "tvf", @_]; print "\n";}

sub date { return strftime '%FT%T%z', localtime() }
