#!/bin/bash

SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

SOURCE_POOL_FILE="testsource.img"
SOURCE2_POOL_FILE="testsource2.img"
DEST_POOL_FILE="testdest.img"

# Error codes from the script
SUCCESS=0
LOCK_FILE_PRESENT=1
NO_DATASETS=2
CONFIG_INVALID=3
ROOT_INVALID=4
MODE_INVALID=5
INTERNAL_FAULT=6
NEST_NAME_MISSING=7
NO_PATTERN_MATCH=8
MISSING_SNAPSHOT=9
COMM_ERROR=10
TIME_SANITY_FAIL=11
SEND_RECV_FAIL=12

TOTAL_TESTS=0
PASS_TESTS=0
FAIL_TESTS=0
FAIL_FAST=0

log () {
    echo "[TEST] $1"
}

check_result () {
    ((TOTAL_TESTS++)) || true

    EXPECT=$1
    CODE=$2

    if [ $EXPECT -eq $CODE ]; then
        ((PASS_TESTS++)) || true
        log "~~~PASS~~~"
    else
        ((FAIL_TESTS++)) || true
        log "~~~FAIL~~~"
        if [ $FAIL_FAST -eq 1 ]; then
            general_test_teardown
            exit 100
        fi
    fi
}

general_test_setup () {
    log "Test Setup..."

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

    zfs snapshot -r testsource@zfs-auto-snap_daily1
    zfs snapshot testsource2/b@zfs-auto-snap_daily1

    zfs send -R testsource@zfs-auto-snap_daily1 | sudo zfs recv testdest/n/testsource
    zfs send testsource2/b@zfs-auto-snap_daily1 | sudo zfs recv testdest/n2/b
}

general_test_teardown () {
    log "Test Teardown..."

    zpool destroy testsource
    zpool destroy testsource2
    zpool destroy testdest

    rm $SOURCE_POOL_FILE
    rm $SOURCE2_POOL_FILE
    rm $DEST_POOL_FILE
}

create_snapshots () {
    log "Generating New Snapshots..."

    zfs snapshot -r testsource@zfs-auto-snap_daily3
    sleep 1
    zfs snapshot -r testsource@zfs-auto-snap_daily4
    sleep 1
    zfs snapshot -r testsource@zfs-auto-snap_daily5
    sleep 1
    zfs snapshot -r testsource@zfs-auto-snap_daily6
    sleep 1
    zfs snapshot -r testsource@zfs-auto-snap_daily7
}

test_local () {
    log "=================================================="
    log "Test successful local backup..."
    log "=================================================="

    general_test_setup
    create_snapshots

    ./zfs-backup-manager.sh --remote-host ""
    check_result $SUCCESS $?

    general_test_teardown
}

test_ssh () {
    log "=================================================="
    log "Test successful ssh backup..."
    log "=================================================="

    general_test_setup
    create_snapshots

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_mbuffer () {
    log "=================================================="
    log "Test successful mbuffer backup..."
    log "=================================================="

    general_test_setup
    create_snapshots

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode mbuffer
    check_result $SUCCESS $?

    general_test_teardown
}

test_up_to_date () {
    log "=================================================="
    log "Test up to date..."
    log "=================================================="

    general_test_setup

    ./zfs-backup-manager.sh --remote-host ""
    check_result $SUCCESS $?

    general_test_teardown
}

test_missing_property () {
    log "=================================================="
    log "Test missing property..."
    log "=================================================="

    general_test_setup

    ./zfs-backup-manager.sh --remote-host "" --mode-property "lol:thisaintright"
    check_result $NO_DATASETS $?

    general_test_teardown
}

test_invalid_argument () {
    log "=================================================="
    log "Test invalid argument..."
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --lolnope
    check_result $SUCCESS $?
}

test_config_invalid () {
    log "=================================================="
    log "Test config invalid"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-mode lol
    check_result $CONFIG_INVALID $?
    ./zfs-backup-manager.sh --remote-host "" --snapshot-pattern ""
    check_result $CONFIG_INVALID $?
    ./zfs-backup-manager.sh --remote-host "" --mode-property ""
    check_result $CONFIG_INVALID $?
    ./zfs-backup-manager.sh --remote-host "" --remote-pool ""
    check_result $CONFIG_INVALID $?
    ./zfs-backup-manager.sh --remote-host "localhost" --remote-user ""
    check_result $CONFIG_INVALID $?
}

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    --fail-fast)
        FAIL_FAST=1
    ;;
    -h|--help)
        print_help
    ;;
    *)
        log "Error: Invalid argument: \"$key\""
        print_help
    ;;
esac
shift
done

log "ZFS Backup Manager Tests Starting..."
log ""

test_invalid_argument
test_missing_property
test_config_invalid
test_local
test_ssh
test_mbuffer
test_up_to_date

log ""
log "$TOTAL_TESTS total tests. $PASS_TESTS passed, $FAIL_TESTS failed."
log ""
log "All tests complete. Exiting."

exit 0
