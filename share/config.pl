#!/usr/bin/perl

use strict;
use warnings;

my $gpg_fingerprint = "D9AE4AEEE1F1B3598E81D9DFB67D55D482A799FD";
my $gpg_bin = "gpg2";

my %profile = (
    journal => [qw( documents/andinus.org.gpg
                    documents/archive.org.gpg )],
    emacs   => [qw( .emacs.d .elfeed .org-timestamps )],
    config  => [qw( .config .kshrc .kshrc.d .tmux.conf .xsession .remind
                    .screenlayout .mg .mbsyncrc .fehbg .profile .plan
                    .authinfo.gpg .Xresources )],
);

# Add more directories to %profile.
foreach my $tmp_prof (qw( emails music projects documents videos .ssh
                          downloads pictures .password-store .mozilla
                          fortunes )) {
    $profile{$tmp_prof} = [$tmp_prof];
}

# Aliases.
$profile{ssh} = $profile{".ssh"};
$profile{pass} = $profile{".password-store"};
$profile{mozilla} = $profile{".mozilla"};


sub get_gpg_fingerprint { return $gpg_fingerprint; }
sub get_profile { return %profile; }
sub get_gpg_bin { return $gpg_bin; }
sub get_backup_dir { return "/tmp/backups" }

1;
