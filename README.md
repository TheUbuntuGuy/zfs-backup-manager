# ZFS Backup Manager

This tool backs up one or more datasets from one pool to another and manages incremental sends based on timely snapshots generated by a tool such as `zfs-auto-snapshot`.  
It can use local pipes, `SSH`, or `mbuffer` for data transfer. It has modes for nesting datasets on the destination, and special handling for mountpoints of root pools.  
Dataset-specific options are stored as custom properties within the dataset, and datasets to backup are automatically discovered.

It can be automated to run with a backup server which is normally powered off using [offline-zfs-backup](https://github.com/TheUbuntuGuy/offline-zfs-backup).

All configuration options and their explanations can be found in the config file `/etc/zfs-backup-manager.conf`. All options can be overridden from the command line as well, including specifying other configuration files.

## Quick Usage Reference
```
Usage: zfs-backup-manager.sh [--simulate] [--ignore-lock] [--config FILE]
  --simulate                Print the commands which would be run,
                            but don't actually execute them.
  --ignore-lock             Ignore the presence of a lock file and run regardless.
                            This option is dangerous and should only be used to
                            clear a previous failure.
  --config FILE             Load a custom configuration file.
                            If not set, defaults to '/etc/zfs-backup-manager.sh'.

The following options override those set in the configuration file.
See the configuration file for a detailed explanation of each option with examples.
  --snapshot-pattern        The pattern to search for in snapshot names to backup.
  --mode-property           The ZFS property which contains the backup mode.
  --nest-name-property      The ZFS property which contains the dataset name to nest within.
  --zfs-options-property    The ZFS property which contains additional ZFS receive options.
  --remote-pool             The destination pool name.
  --remote-host             The hostname of the destination. Pass "" for the local machine.
  --remote-user             The user to login as on the destination.
  --remote-mode             The transfer mode to a remote system. (ssh/mbuffer)
  --mbuffer-block-size      The block size to set when using mbuffer, or "auto" to use recordsize.
  --mbuffer-port            The port for mbuffer to listen on.
  --mbuffer-buffer-size     The size of the send and receive buffers when using mbuffer.
  --ssh-options             Additional options to pass to SSH.

This script must be run as root.
```

## Sample Output
This is an example of backing up a single dataset using `mbuffer` for transport, and the `root` mode.
```
[ZFS Backup Manager] ZFS Backup Manager v0.0.2 Starting...
[ZFS Backup Manager] Loading configuration...
[ZFS Backup Manager] Using mbuffer for transfer
[ZFS Backup Manager]
[ZFS Backup Manager] Processing dataset: rootpool/ROOT/watt
[ZFS Backup Manager] Using mode: root
[ZFS Backup Manager] Nesting in: watt/rootpool/ROOT
[ZFS Backup Manager] Local HEAD is: zfs-auto-snap_daily-2018-02-10-1125
[ZFS Backup Manager] Remote HEAD is: zfs-auto-snap_daily-2018-02-08-1125
[ZFS Backup Manager] Performing send/receive...
[ZFS Backup Manager] Using blocksize: 128k
receiving incremental stream of rootpool/ROOT/watt@zfs-auto-snap_daily-2018-02-09-1125 into backuppool/watt/rootpool/ROOT/watt@zfs-auto-snap_daily-2018-02-09-1125
received 30.1M stream in 30 seconds (1.00M/sec)
receiving incremental stream of rootpool/ROOT/watt@zfs-auto-snap_daily-2018-02-10-1125 into backuppool/watt/rootpool/ROOT/watt@zfs-auto-snap_daily-2018-02-10-1125
received 312B stream in 1 seconds (312B/sec)
[ZFS Backup Manager]
[ZFS Backup Manager] Backup process completed successfully. Exiting.
```

Another run with a single dataset using `ssh` transport and the `nested` mode.
```
[ZFS Backup Manager] ZFS Backup Manager v0.0.2 Starting...
[ZFS Backup Manager] Loading configuration...
[ZFS Backup Manager] Using SSH for transfer
[ZFS Backup Manager] 
[ZFS Backup Manager] Processing dataset: tank/gitlab-data
[ZFS Backup Manager] Using mode: nested
[ZFS Backup Manager] Nesting in: gitlab
[ZFS Backup Manager] Local HEAD is: zfs-auto-snap_daily-2018-02-10-1125
[ZFS Backup Manager] Remote HEAD is: zfs-auto-snap_daily-2018-02-08-1125
[ZFS Backup Manager] Performing send/receive...
receiving incremental stream of tank/gitlab-data@zfs-auto-snap_daily-2018-02-09-1125 into backuppool/gitlab/gitlab-data@zfs-auto-snap_daily-2018-02-09-1125
received 312B stream in 1 seconds (312B/sec)
receiving incremental stream of tank/gitlab-data@zfs-auto-snap_daily-2018-02-10-1125 into backuppool/gitlab/gitlab-data@zfs-auto-snap_daily-2018-02-10-1125
received 312B stream in 1 seconds (312B/sec)
[ZFS Backup Manager] 
[ZFS Backup Manager] Backup process completed successfully. Exiting.
```

## Installation
You can build a Debian package on your system by running:
```
make package
```

The package will be located in `bin`. You can install it directly from `make` using:
```
make install
```

## Testing
This script comes with a system test script `test_zfs_backup_manager.sh`. This script runs 37 external tests using temporary file-backed local pools. It is encouraged that you run these tests before using the script to prove that your system is sane.  
Similarly if you modify the script, run the tests to verify that you have not caused any regressions.  
Please note that currently the test script does not have 100% coverage, nor is it fully automated. You must check the output to validate more than just the return codes.

## Dependencies
You will need `openssh-client`, `mbuffer`, `zfs-auto-snapshot`, and of course `zfs` installed to use all features. The Debian package links to the related packages.
