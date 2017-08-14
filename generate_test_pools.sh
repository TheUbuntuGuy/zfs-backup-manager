#!/bin/bash -e

SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

SOURCE_POOL_FILE="testsource.img"
SOURCE2_POOL_FILE="testsource2.img"
DEST_POOL_FILE="testdest.img"

truncate -s 100M $SOURCE_POOL_FILE
truncate -s 100M $SOURCE2_POOL_FILE
truncate -s 100M $DEST_POOL_FILE

zpool create testsource $SCRIPT_PATH/$SOURCE_POOL_FILE
zpool create testsource2 $SCRIPT_PATH/$SOURCE2_POOL_FILE
zpool create testdest $SCRIPT_PATH/$DEST_POOL_FILE

zfs create testsource/a
zfs create testsource2/b
zfs create testdest/n
zfs create testdest/n2

zfs set furneaux:autobackup=root testsource
zfs set furneaux:backupnestname=n testsource

# zfs set furneaux:autobackup=nested testsource/a
# zfs set furneaux:backupnestname=n testsource/a

# zfs set furneaux:autobackup=nested testsource2/b
# zfs set furneaux:backupnestname=n2 testsource2/b

# zfs set furneaux:autobackup=path testsource/a

# zfs snapshot testsource/a@zfs-auto-snap_daily1
zfs snapshot -r testsource@zfs-auto-snap_daily1
zfs snapshot testsource2/b@zfs-auto-snap_daily1

# zfs send testsource/a@zfs-auto-snap_daily1 | sudo zfs recv testdest/n/a
zfs send -R testsource@zfs-auto-snap_daily1 | sudo zfs recv testdest/n/testsource
zfs send testsource2/b@zfs-auto-snap_daily1 | sudo zfs recv testdest/n2/b

# zfs send testsource/a@zfs-auto-snap_daily1 | sudo zfs recv testdest/a

sleep 2

# zfs snapshot testsource/a@zfs-auto-snap_daily2
zfs snapshot -r testsource@zfs-auto-snap_daily2
zfs snapshot testsource2/b@zfs-auto-snap_daily2
