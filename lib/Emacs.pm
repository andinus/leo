#!/usr/bin/perl

package Emacs;

use strict;
use warnings;
use feature 'say';
use Fcntl ':mode';

use IPC::Run3;
use Path::Tiny;
use Term::ANSIColor qw/ :pushpop colored color /;

sub sync {
    my ( $options ) = @_;
    my $verbose = $options->{verbose};

    sub rsync {
        run3 ["openrsync", @_];
    }
    my @def_opt = qw{ --delete -oprtl };
    push @def_opt, "-v" if $verbose;

    # Remove --delete.
    my @no_del_opt = @def_opt;
    shift @no_del_opt;

    if ($options->{authinfo}) {
        my $authinfo_remote = "$ENV{HOME}/.authinfo-remote";
        my %path_perms = (
            $authinfo_remote => 0700,
            "$authinfo_remote/team" => 0600,
            "$authinfo_remote/inst" => 0600,
            "$authinfo_remote/town" => 0600,
        );

        # Check path permissions.
        say LOCALCOLOR CYAN "Checking path permissions...";
        foreach my $path ( sort keys %path_perms ) {
            my $mode = S_IMODE(path($path)->stat->mode);

            if ( $mode == $path_perms{$path} ) {
                say LOCALCOLOR GREEN "[OK] $path"
                    if $verbose;
            } else {
                warn "[ERR] $path
      Expected: $path_perms{$path} :: Got: $mode
      Changing permission...\n";

                path("$path")->chmod($path_perms{$path});
            }
        }
        say LOCALCOLOR CYAN "[DONE] Permissions checked";

        say LOCALCOLOR CYAN "Syncing authinfo...";
        my %authinfo_hosts = (
            "tilde.team" => "$authinfo_remote/team",
            "tilde.institute" => "$authinfo_remote/inst",
            "tilde.town" => "$authinfo_remote/town",
        );
        foreach my $host ( sort keys %authinfo_hosts ) {
            say LOCALCOLOR MAGENTA "$host";
            rsync( @def_opt, $authinfo_hosts{$host}, "andinus\@$host:~/.authinfo" );
        }
        say LOCALCOLOR CYAN "[DONE] authinfo sync";
    }

    if ($options->{config}) {
        say LOCALCOLOR CYAN "Syncing emacs config...";
        my @hosts = qw{ tilde.team tilde.institute envs.net tilde.town };

        my $e_conf = "$ENV{HOME}/.emacs.d";
        my @paths = (
            "$e_conf/init.el",
            "$e_conf/e-init.el",
            "$e_conf/e-init.org",
            "$e_conf/elpa/",
        );
        foreach my $host (@hosts) {
            say LOCALCOLOR MAGENTA "$host";
            foreach my $path (@paths) {
                say "  $path";
                rsync( @def_opt, $path, "andinus\@$host:$path");
            }
        }
        say LOCALCOLOR CYAN "[Done] Emacs config sync";
    }

    if ( $options->{irclogs} ) {
        say LOCALCOLOR CYAN "Syncing irclogs...";
        my @hosts = qw{ tilde.team tilde.institute envs.net tilde.town };

        my $e_conf = "$ENV{HOME}/.emacs.d";
        foreach my $host (@hosts) {
            say LOCALCOLOR MAGENTA "$host";
            rsync( @no_del_opt, "andinus\@$host:~/.emacs.d/irclogs/",
                   "$e_conf/irclogs/$host/");
        }

        say LOCALCOLOR CYAN "[DONE] irclogs sync";
    }

}

1;
