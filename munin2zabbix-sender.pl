#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;


######################################################################
# DO NOT EDIT following lines
my $version = [
               'version 0.01 alpha   2013/03/15',
               ];

my $DO_OPERATION = 0;

my $temp_dir = '/tmp/munin2zabbix-sender';

# This directory includes lock dir and temp data file for zabbix_sender.
if (! -d $temp_dir) {
  mkdir($temp_dir, 0755);
}

# Path of Command and plugins dir.
my $munin_run_command = '/usr/sbin/munin-run';
my $munin_plugins_dir = '/etc/munin/plugins';
my $zabbix_sender_command = '/usr/bin/zabbix_sender';
my $zabbix_agentd_conf    = ' /etc/zabbix/zabbix_agentd.conf';

######################################################################
my ($dryrun, $help, $selfcheck, $plugin, $DEBUG);

GetOptions(
    'dryrun' => \$dryrun,
    'selfcheck' => \$selfcheck,
    'help' => \$help,
    'verbose' => \$DEBUG,
    'plugin=s' => \$plugin,
    );

{
    # Main Routine
    if ( $help || !$plugin ) {
        die &usage();
    }
    if ($selfcheck) {
        &do_selfcheck();
        exit;
    }
    if ($dryrun) {
        $DO_OPERATION = 0;
    }

    my $lockdir = &do_lock() if $DO_OPERATION;

    print "DEBUG:DO $munin_run_command $plugin\n" if $DEBUG;
    my @results = `$munin_run_command $plugin` if $DO_OPERATION;
    foreach my $line (@results) {
        print "DEBUG:munin  $line\n" if $DEBUG;
        my ( $munin_key,  $value ) = split( /\s/, $line );
        my ( $zabbix_key, $dummy ) = split( /\./, $munin_key );
        print "DEBUG:zabbix $zabbix_key $value\n" if $DEBUG;
        my $result
            = `$zabbix_sender_command -c $zabbix_agentd_conf -k $zabbix_key -o $value`
            if $DO_OPERATION;
        print "DEBUG:result $result\n" if $DEBUG;
    }
    &do_unlock($lockdir) if $DO_OPERATION;
    exit;
}

sub do_lock {
    my $lockdir  = "$temp_dir/lock1";
    my $lockdir2 = "$temp_dir/locl2";

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
    return $lockdir;
}

sub do_unlock {
    my $lockdir = shift;
    rmdir($lockdir);
}

sub usage {
    print STDERR "munin2zabbix-sender $version->[0]\n";
    print STDERR "\n";
    print STDERR "\t[-d|--dryrun] DO NOTHING\n";
    print STDERR "\t[-s|--selfcheck] Check this environment for working.\n";
    print STDERR "\t[-p|--plugin] <name of munin plugin>\n";
    print STDERR "\t[-h|--help] Print this message\n";
    print STDERR "\t[-v|--verbose] Print verbose messages\n\n";
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
        print "[*]munin_run\t... found\n";
    }
    else {
        print "[ ]munin_run\t... not found($munin_run_command)\n";
    }
    if ( -d $munin_plugins_dir ) {
        print "[*]munin_plugins_dir\t... found\n";
    }
    else {
        print "[ ]munin_plugins_dir\t... not found($munin_plugins_dir)\n";
    }
    print "\n";
}
