#!/usr/bin/env raku

use v6.d;
use Config;

enum Actions (
    backup => "Make backup",
    rotate => "Rotate the backups",
    list => "List profiles / profile options",
);

sub USAGE {
    say $*USAGE;
    say "\nActions:";
    for Actions.enums.kv -> $action, $description {
        say " " x 4, $action,
        " " x (Actions.enums.keys.map(*.chars).max - $action.chars) + 4,
        $description;
    }
}

sub read-configuration(--> Config) {
    return Config.new.read(
        %*ENV<XDG_CONFIG_HOME> ??
        %*ENV<XDG_CONFIG_HOME> ~ "/leo.toml" !! %*ENV<HOME> ~ "/.config/leo.toml"
    );
}

# If nothing is passed then named argument multi prevails so we just
# create one so that USAGE() gets printed if no argument is passed.
multi sub MAIN(Bool :$help-implied) is hidden-from-USAGE { USAGE() }
multi sub MAIN(Bool :$version) is hidden-from-USAGE { say "Leo v0.6.0" }

multi sub MAIN(Actions $action, Bool :v(:$verbose)) is hidden-from-USAGE {
    note 'Verbosity on' if $verbose;
    note 'Dispatched Actions only sub' if $verbose;
    note 'Reading configuration' if $verbose;

    my Config $config = read-configuration();

    given $action.key {
        when 'list' {
            say "Profiles:";
            say " " x 4, $_ for $config<profiles>.keys.sort;
            exit 0;
        }
        default {
            note "(!!) No profile passed";
            exit 1;
        }
    }
}

multi sub MAIN(
    Actions $action, #= action to perform
    *@profiles, #= profiles to perform the action on
    Bool :v(:$verbose), #= increase verbosity
    Bool :$version, #= print version
) {
    note 'Verbosity on' if $verbose;
    note 'Reading configuration' if $verbose;

    my Config $config = read-configuration();

    # Default number of backups to hold / keep.
    my int ($default_hold, $default_keep) = (1, 2);

    # $backup_dir holds path to backup directory.
    my Str $backup_dir;
    my DateTime $date = DateTime.new(time);

    $backup_dir = $config<backup> ?? $config<backup> !! "/tmp/backups";

    # Fix $backup_dir permission.
    unless $backup_dir.IO.mode eq "0700" {
        note "Setting mode to 700: '$backup_dir'" if $verbose;
        $backup_dir.IO.chmod(0o700);
    }

    for @profiles -> $profile {
        say "[$profile]";
        without ($config<profiles>{$profile}) {
            note "(!!) No such profile";
            exit 1;
        }

        my Str $profile_dir = $backup_dir ~ "/$profile";

        # Create the profile backup directory if it doesn't exist.
        unless $profile_dir.IO ~~ :d {
            note "Creating profile backup directory: '$profile_dir'" if $verbose;
            mkdir($profile_dir, 0o700) or die "$!";
        }

        given $action.key {
            when 'backup' {
                my IO $backup_file = "$profile_dir/$date.tgz".IO;

                say "Backup: ", $backup_file.Str;

                note "\nCalling backup-profile subroutine" if $verbose;
                backup-profile($profile, $backup_file, $config, $verbose);

                if (
                    ($config<profiles>{$profile}<encrypt> // $config<gpg><encrypt>) or
                    ($config<profiles>{$profile}<sign> // $config<gpg><sign>)
                ) {
                    note "\nCalling gnupg subroutine" if $verbose;
                    gnupg($profile, $backup_file, $config, $verbose);
                }
            }
            when 'list' {
                say "Encryption ", ($config<profiles>{$profile}<encrypt> //
                                    $config<gpg><encrypt>) ??
                                                           "ON" !! "OFF";

                say "GnuPG sign ", ($config<profiles>{$profile}<sign> //
                                    $config<gpg><sign>) ??
                                                        "ON" !! "OFF";

                say "Holding ", (
                    $config<profiles>{$profile}<rotate><hold> //
                    $config<rotate><hold> // $default_hold
                ), " backups";

                say "Keeping ", (
                    $config<profiles>{$profile}<rotate><keep> //
                    $config<rotate><keep> // $default_keep
                ), " backups";

                say "Base directory: ",
                ($config<profiles>{$profile}<base_dir> //
                 $config<base_dir> //
                 "/");

                say "\nPaths: ";
                say " " x 4, $_ for @($config<profiles>{$profile}<paths> //
                                      ".");

                if $config<profiles>{$profile}<exclude>.defined {
                    say "\nExclude: ";
                    say " " x 4, $_ for @($config<profiles>{$profile}<exclude>);
                }
            }
            when 'rotate' {
                my DateTime %backups;
                for dir $profile_dir -> $path {
                    next unless $path.f;
                    if $path.Str ~~ /$profile '/' (.*)
                    ['.tar'|'.tar.gpg'|'.tgz'|'.tgz.gpg']$/ -> $match {
                        %backups{$path.Str} = DateTime.new($match[0].Str);
                    }
                }

                say "Total backups: ", %backups.elems;
                exit 0 if %backups.elems == 0; # Exit if 0 backups.

                # Hold the backups that are to be held. Default is to hold 1
                # backup.
                for %backups.sort(*.value).map(*.key).head(
                    $config<profiles>{$profile}<rotate><hold> //
                    $config<rotate><hold> // $default_hold
                ) {
                    note "(H) Holding: ", $_ if $verbose;
                    %backups{$_}:delete;
                }

                # We'll keep `n' latest backups where `n' equals to
                # the number of backups we want to keep. Default is to
                # keep 2 backups.
                for %backups.sort(*.value).map(*.key).tail(
                    $config<profiles>{$profile}<rotate><keep> //
                    $config<rotate><keep> // $default_keep
                ) {
                    note "(K) Keeping: ", $_ if $verbose;
                    %backups{$_}:delete;
                }

                # Now we just remove all backups in %backups.
                for %backups -> $backup {
                    note "(D) Deleting: ", $backup.key if $verbose;
                    unlink($backup.key);
                }
            }
            default {
                note "Invalid action";
                exit 1;
            }
        }
    }
}

sub backup-profile (
    Str $profile, IO $backup_file, Config $config, Bool $verbose
) {
    my IO $base_dir = $_.IO with (
        $config<profiles>{$profile}<base_dir> //
        $config<base_dir> //
        "/"
    );
    chdir $base_dir or die "$!";

    my Str @options = <-c -z>;
    push @options, '-vv' if $verbose;
    push @options, '-f', $backup_file.Str;
    push @options, '-C', $base_dir.Str;

    my Str @backup_paths;
    for (
        @($config<profiles>{$profile}<paths> // ".")
    ) -> $path {
        if $path.IO.d {
            push @backup_paths, $_.Str for dir $path;
        } else {
            push @backup_paths, $path;
        }
    }

    run <tar>, @options, (
        @backup_paths (-) @($config<profiles>{$profile}<exclude>)
    ).keys;
}

sub gnupg (
    Str $profile, IO $backup_file, Config $config, Bool $verbose
) {
    my Str @options = '--yes';

    if (
        $config<profiles>{$profile}<encrypt> //
        $config<gpg><encrypt>
    ) {
        push @options, '--encrypt';
        with $config<gpg><recipients> {
            push @options, "--recipient", $_ for @($_);
        }
    }

    push @options, $verbose ?? '--verbose' !! '--quiet';
    push @options, '--sign' if (
        $config<profiles>{$profile}<sign> //
        $config<gpg><sign>
    );
    push @options, '--default-key', $_ with $config<gpg><fingerprint>;

    run <gpg2>, @options, $backup_file;

    unlink($backup_file) or die "$!";
}
