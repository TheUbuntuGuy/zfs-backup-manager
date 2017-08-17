#!/bin/bash -e

zfs snapshot -r testsource@zfs-auto-snap_daily3
sleep 1
zfs snapshot -r testsource@zfs-auto-snap_daily4
sleep 1
zfs snapshot -r testsource@zfs-auto-snap_daily5
sleep 1
zfs snapshot -r testsource@zfs-auto-snap_daily6
sleep 1
zfs snapshot -r testsource@zfs-auto-snap_daily7
