munin2zabbix-sender
===================

NAME
---------------

        munin2zabbix-sender.pl - This script can send data from munin plugins to zabbix via zabbix_sender.

Version
----------------
        0.05

SYNOPSIS
---------------
       munin2zabbix-sender.pl [options]

        Options
           [-d|--dryrun]        DO NOTHING.
           [-s|--selfcheck]     Check this environment for working.
           [-p|--plugin]        <name of munin plugin>
           [-h|--help]          Print this message.
           [-v|--verbose]       Print verbose messages.
           [-a|--all]           Call all available munin-node plugins.
           [-i|--ignore]        Ignore munin-node plugins with "--all" option.

        Examples:
           Call one plugin.
           # munin2zabbix-sender.pl -p mysql_select_types

           Call multiple plugins.
           # munin2zabbix-sender.pl -p mysql_select_types,memory
           # munin2zabbix-sender.pl -p mysql_select_types:memory

           Call all available munin-node plugins
           # munin2zabbix-sender.pl -a

           Call all available munin-node plugins without some plugins.
           # munin2zabbix-sender.pl -a -i cpu,if_

        See Also:
           perldoc munin2zabbix-sender.pl

DESCRIPTION
---------------
        This script can send data from munin plugins to zabbix via zabbix_sender.

SEE ALSO
---------------
       https://github.com/kunitake/munin2zabbix-sender/README.md

Unsupported munin plugins
-------------------------------
* yum
* diskstats 
