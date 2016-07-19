#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage 'pod2usage';

######################################################################
# DO NOT EDIT following lines
my $version = [
    'version 0.08         2016/07/19',
    'version 0.07         2016/07/19',
    'version 0.06         2016/07/15',
    'version 0.05         2013/03/25',
    'version 0.04         2013/03/22',
    'version 0.03 beta    2013/03/22',
    'version 0.02 beta    2013/03/15',
    'version 0.01 alpha   2013/03/15',
];

$ENV{'PATH'} = '/usr/sbin:/bin:/usr/bin';

my $DO_OPERATION = 1;

my $temp_dir = '/tmp/munin2zabbix-sender';

my $lockdir  = "$temp_dir/lock1";
my $lockdir2 = "$temp_dir/locl2";

my @unsupported_plugins = ( 'diskstats', 'yum' );

######################################################################
# DO EDIT following lines as you like

# Path of Command and plugins dir.
my $munin_run_command     = '/usr/sbin/munin-run';
my $munin_plugins_dir     = '/etc/munin/plugins';
my $zabbix_sender_command = '/usr/bin/zabbix_sender';
my $zabbix_agentd_conf    = '/etc/zabbix/zabbix_agentd.conf';

######################################################################
my ( $dryrun, $help, $selfcheck, $called_plugin, $verbose, $all_plugins,
    $ignored_plugin, $cdef );

GetOptions(
    'dryrun'    => \$dryrun,
    'selfcheck' => \$selfcheck,
    'help'      => \$help,
    'verbose'   => \$verbose,
    'plugin=s'  => \$called_plugin,
    'ignore=s'  => \$ignored_plugin,
    'cdef'      => \$cdef,
    'all'       => \$all_plugins,
);

{
    # Main Routine
    if ($selfcheck) {
        &do_selfcheck();
        exit;
    }
    if ( $help || ( !$called_plugin && !$all_plugins ) ) {
        pod2usage(1);
    }
    if ( $ignored_plugin && !$all_plugins ) {
        pod2usage(1);
    }
    if ($dryrun) {
        $DO_OPERATION = 0;
    }

    if ($DO_OPERATION) {

      # This directory includes lock dir and temp data file for zabbix_sender.
        if ( !-d $temp_dir ) {
            mkdir( $temp_dir, 0755 );
        }
        &do_lock();
    }

    my ( @munin_plugins, @ignored_plugins );
    if ($ignored_plugin) {
        @ignored_plugins = split( /,|:/, $ignored_plugin );
    }
    push( @ignored_plugins, @unsupported_plugins );
    my $ignored_list = join( "|^", @ignored_plugins );

    if ($all_plugins) {
        if ($ignored_list) {
            @munin_plugins
                = `ls $munin_plugins_dir | egrep -v "^$ignored_list"`;
        }
        else {
            @munin_plugins = `ls $munin_plugins_dir`;
        }
        &DEBUG("ignored:list $ignored_list");
    }
    else {
        @munin_plugins = split( /,|:/, $called_plugin );
    }

    if ($DO_OPERATION) {
        my $temp_file = "$lockdir/munin.dat";
        unless ( open( FN, "> $temp_file" ) ) {
            print STDERR "failed open a file($lockdir/munin.dat)\n";
        }
        flock( FN, 2 );

        foreach my $plugin (@munin_plugins) {
            chomp($plugin);

            # get CDEF
            my %munin_item = ();
            if ($cdef) {
                &DEBUG("$munin_run_command $plugin config");
                my @munin_configs = `$munin_run_command $plugin config`;

                foreach my $line (@munin_configs) {
                    my ( $key, @data ) = split( /\s/, $line );

                    if ( $key =~ /\.cdef$/ ) {
                        my ( $item, undef ) = split( /\./, $key );
                        $munin_item{$item}{'cdef'} = $data[0];
                        &DEBUG("CDEF:$item: $data[0]");
                    }
                }
            }

            # Get values by munin_run
            my $time = time();
            my @zabbix_send_key;

            &DEBUG("$munin_run_command $plugin");
            my @results = `$munin_run_command $plugin 2> /dev/null`;
            if ( $? == 0 ) {

                # success
                foreach my $line (@results) {
                    chomp($line);
                    &DEBUG("munin  $line");
                    my ( $munin_key,  $value ) = split( /\s/, $line );
                    my ( $zabbix_key, $dummy ) = split( /\./, $munin_key );
                    push( @zabbix_send_key, $zabbix_key );
                    $value = 0 if !$value;
                    $munin_item{$zabbix_key}{'value'} = $value;
                    $munin_item{$zabbix_key}{'time'}  = $time;
                    &DEBUG(
                        "munin[$plugin,$zabbix_key] $value(BEFORE ACCORDING TO CDEF)"
                    );

                    if ( defined $munin_item{$zabbix_key}{'cdef'} ) {
                        my @cdef
                            = split( /,/, $munin_item{$zabbix_key}{'cdef'} );
                        my @stack;
                        foreach my $calc (@cdef) {
                            if ( $calc =~ /^[\*\/\+\-]$/ ) {
                                my $pop1 = pop(@stack);
                                my $pop2 = pop(@stack);
                                my ( $pop1_value, $pop2_value );
                                if ( $pop1 =~ /^[0-9]+$/ ) {
                                    $pop1_value = $pop1;
                                }
                                else {
                                    $pop1_value = $munin_item{$pop1}{'value'};
                                }
                                $pop2_value = $munin_item{$pop2}{'value'};

                                my $exp
                                    = '$pop2_value = '
                                    . "$pop2_value"
                                    . $calc
                                    . "$pop1_value";
                                eval($exp);
                                $munin_item{$pop2}{'value'} = $pop2_value;
                                &DEBUG("ADJUST: $pop2 $pop2_value");
                                push( @stack, $pop2 );
                            }
                            else {
                                push( @stack, $calc );
                            }

                        }
                    }
                }
                foreach my $key (@zabbix_send_key) {
                    &DEBUG(
                        "- munin[$plugin,$key] $time $munin_item{$key}{'value'}"
                    );
                    print FN
                        "- munin[$plugin,$key] $time $munin_item{$key}{'value'}\n";
                }
            }
            else {
                # fail..
                &DEBUG("Failed to $munin_run_command $plugin");
            }
        }

        my $result
            = `$zabbix_sender_command -T -c $zabbix_agentd_conf -i $lockdir/munin.dat`;
        close(FN);
        &DEBUG("result $result");
        unlink($temp_file);
    }
    else {
        &DEBUG(
            "EXEC $zabbix_sender_command -T -c $zabbix_agentd_conf -i $lockdir/munin.dat"
        );
    }
    &do_unlock() if $DO_OPERATION;
    exit;
}

sub do_lock {

    # retry count;
    my $retry = 5;

    # lock function.
    # cf. http://homepage1.nifty.com/glass/tom_neko/web/web_04.html
    while ( !mkdir( $lockdir, 0755 ) ) {
        if ( --$retry <= 0 ) {
            if ( mkdir( $lockdir2, 0755 ) ) {
                if ( ( -M $lockdir ) * 86400 > 600 ) {
                    rename( $lockdir2, $lockdir ) or &error("LOCK ERROR");
                    last;
                }
                else { rmdir($lockdir2); }
                print STDERR "already working...\n";
                exit;
            }
        }
        sleep(1);
    }
}

sub do_unlock {
    rmdir($lockdir);
}

sub do_selfcheck {
    print "\n";
    print "Check path of commands and munin-plugin's directory...\n";

    if ( -e $zabbix_sender_command ) {
        print "[*]zabbix_sender\t... found\n";
    }
    else {
        print "[ ]zabbix_sender\t... not found($zabbix_sender_command)\n";
    }
    if ( -e $zabbix_agentd_conf ) {
        print "[*]zabbix_agentd.conf\t... found\n";
    }
    else {
        print "[ ]zabbix_agentd.conf\t... not found($zabbix_agentd_conf)\n";
    }
    if ( -e $munin_run_command ) {
        print "[*]munin_run\t\t... found\n";
    }
    else {
        print "[ ]munin_run\t\t... not found($munin_run_command)\n";
    }
    if ( -d $munin_plugins_dir ) {
        print "[*]munin_plugins_dir\t... found\n";
    }
    else {
        print "[ ]munin_plugins_dir\t... not found($munin_plugins_dir)\n";
    }
    print "\n";
}

sub DEBUG {
    my $message = shift;
    if ($verbose) {
        print "DEBUG:";
        print "DryRun:" if !$DO_OPERATION;
        print "$message\n";
    }
}

sub error {
    my $message = shift;
    print STDERR "error: $message\n";
    exit;
}

1;

__END__

=head1 NAME

 munin2zabbix-sender.pl - This script can send data from munin plugins to zabbix via zabbix_sender.

=head1 SYNOPSIS

munin2zabbix-sender.pl [options]

 Options
    [-d|--dryrun]        DO NOTHING.
    [-s|--selfcheck]     Check this environment for working.
    [-p|--plugin]        <name of munin plugin>
    [-h|--help]          Print this message.
    [-v|--verbose]       Print verbose messages.
    [-a|--all]           Call all available munin-node plugins.
    [-i|--ignore]        Ignore munin-node plugins with "--all" option.
    [-c|--cdef]          Adjust values by CDEF from munin-run config.

 Examples:
    Call one plugin (forward match in plugin name).
    # munin2zabbix-sender.pl -p mysql_select_types

    Call multiple plugins (forward match in plugin name).
    # munin2zabbix-sender.pl -p mysql_select_types,memory
    # munin2zabbix-sender.pl -p mysql_select_types:memory

    Call all available munin-node plugins.
    # munin2zabbix-sender.pl -a

    Call all available munin-node plugins and adjust values according to CDEF.
    # munin2zabbix-sender.pl -a -c

    Call all available munin-node plugins without some plugins (forward match in plugin name).
    # munin2zabbix-sender.pl -a -i cpu,if_


 See Also:
    perldoc munin2zabbix-sender.pl

=head1 DESCRIPTION

 This script can send data from munin plugins to zabbix via zabbix_sender.

=head1 SEE ALSO

https://github.com/kunitake/munin2zabbix-sender/README.md

=head1 AUTHOR

KUNITAKE Koichi <koichi@kunitake.org>

=cut
