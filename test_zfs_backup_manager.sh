#!/bin/bash

# ZFS Backup Manager Test Script
# Version 0.0.1
# Copyright 2017 Romaco Canada, Mark Furneaux

# An ssh key to the local root user is needed for the remote tests to pass.

SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

# Test config. Shouldn't conflict with any real systems...
SOURCE_POOL_FILE="testsource.img"
SOURCE2_POOL_FILE="testsource2.img"
DEST_POOL_FILE="testdest.img"

SOURCE_POOL="testsource_138975"
SOURCE_POOL_2="testsource2_138975"
DEST_POOL="testdest_138975"

ZFS_MODE_PROPERTY="furneaux:testautobackup"

# Lock file the script uses
LOCK_FILE="/var/run/zfs-backup-manager.lock"

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

# Test tallies
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
            log "Dumping current config..."
            zfs list
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

    zpool create $SOURCE_POOL $SCRIPT_PATH/$SOURCE_POOL_FILE
    zpool create $SOURCE_POOL_2 $SCRIPT_PATH/$SOURCE2_POOL_FILE
    zpool create $DEST_POOL $SCRIPT_PATH/$DEST_POOL_FILE

    zfs create $SOURCE_POOL/a
    zfs create $SOURCE_POOL_2/b
    zfs create $DEST_POOL/n
    zfs create $DEST_POOL/m

    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily1
    zfs snapshot $SOURCE_POOL_2/b@zfs-auto-snap_daily1
}

path_setup () {
    zfs set $ZFS_MODE_PROPERTY=path $SOURCE_POOL/a

    zfs send -R $SOURCE_POOL/a@zfs-auto-snap_daily1 | sudo zfs recv -dF $DEST_POOL
}

nested_setup () {
    zfs set $ZFS_MODE_PROPERTY=nested $SOURCE_POOL_2/b
    zfs set furneaux:backupnestname=m $SOURCE_POOL_2/b

    zfs send $SOURCE_POOL_2/b@zfs-auto-snap_daily1 | sudo zfs recv $DEST_POOL/m/b
}

root_setup () {
    zfs set $ZFS_MODE_PROPERTY=root $SOURCE_POOL
    zfs set furneaux:backupnestname=n $SOURCE_POOL

    zfs send -R $SOURCE_POOL@zfs-auto-snap_daily1 | sudo zfs recv $DEST_POOL/n/$SOURCE_POOL
}

general_test_teardown () {
    log "Test Teardown..."

    zpool destroy $SOURCE_POOL
    zpool destroy $SOURCE_POOL_2
    zpool destroy $DEST_POOL

    rm $SOURCE_POOL_FILE
    rm $SOURCE2_POOL_FILE
    rm $DEST_POOL_FILE

    if [ -e $LOCK_FILE ]; then
        rm $LOCK_FILE
    fi
}

create_snapshots () {
    log "Generating New Snapshots..."

    # generate some incompressible data to send
    dd if=/dev/urandom of=/$SOURCE_POOL/testfile bs=1M count=30 > /dev/random 2>&1

    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily3
    zfs snapshot -r $SOURCE_POOL_2@zfs-auto-snap_daily3
    sleep 1
    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily4
    zfs snapshot -r $SOURCE_POOL_2@zfs-auto-snap_daily4
    sleep 1
    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily5
    zfs snapshot -r $SOURCE_POOL_2@zfs-auto-snap_daily5
    sleep 1
    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily6
    zfs snapshot -r $SOURCE_POOL_2@zfs-auto-snap_daily6
    sleep 1
    zfs snapshot -r $SOURCE_POOL@zfs-auto-snap_daily7
    zfs snapshot -r $SOURCE_POOL_2@zfs-auto-snap_daily7
}

test_local () {
    log "=================================================="
    log "Test successful local backup..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_additional_options () {
    log "=================================================="
    log "Test additional options..."
    log "=================================================="

    general_test_setup

    zfs set furneaux:backupopts="-o com.sun:auto-snapshot=false" $SOURCE_POOL/a

    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh --zfs-options-property "furneaux:backupopts"
    check_result $SUCCESS $?

    general_test_teardown
}

test_simulation () {
    log "=================================================="
    log "Test simulation..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    # create a situation which looks correct but will fail if attempted
    zfs destroy $DEST_POOL/a@zfs-auto-snap_daily1
    zfs snapshot $DEST_POOL/a@zfs-auto-snap_daily1
    sleep 1
    zfs snapshot $SOURCE_POOL/a@zfs-auto-snap_daily9

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --simulate --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_missing_nest_name_property () {
    log "=================================================="
    log "Test missing nest name property..."
    log "=================================================="

    general_test_setup
    create_snapshots
    nested_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh --nest-name-property ""
    check_result $CONFIG_INVALID $?

    general_test_teardown
}

test_chain_backup_local () {
    log "=================================================="
    log "Test chain backup local..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup
    nested_setup
    root_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh --nest-name-property "furneaux:backupnestname"  --ssh-options ""
    check_result $SUCCESS $?

    general_test_teardown
}

test_chain_backup_ssh () {
    log "=================================================="
    log "Test chain backup ssh..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup
    nested_setup
    root_setup

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --remote-mode ssh --remote-user "root" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --nest-name-property "furneaux:backupnestname"  --ssh-options ""
    check_result $SUCCESS $?

    general_test_teardown
}

test_chain_backup_mbuffer () {
    log "=================================================="
    log "Test chain backup mbuffer..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup
    nested_setup
    root_setup

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --remote-mode mbuffer --remote-user "root" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --nest-name-property "furneaux:backupnestname"
    check_result $SUCCESS $?

    general_test_teardown
}

test_no_pattern_match () {
    log "=================================================="
    log "Test no pattern match..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "no_match_pattern" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $NO_PATTERN_MATCH $?

    general_test_teardown
}

test_no_pattern_match_remote () {
    log "=================================================="
    log "Test no pattern match on remote..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    zfs destroy $DEST_POOL/a@zfs-auto-snap_daily1

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $NO_PATTERN_MATCH $?

    general_test_teardown
}

test_remote_ahead_of_local () {
    log "=================================================="
    log "Test remote ahead of local..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    # create a snapshot on the destionation which does not exist on the source
    zfs snapshot $DEST_POOL/a@zfs-auto-snap_daily9

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $MISSING_SNAPSHOT $?

    general_test_teardown
}

test_time_sanity_local () {
    log "=================================================="
    log "Test time sanity local..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    # create a snapshot with the same name as one on the source, but newer
    sleep 1
    zfs snapshot $DEST_POOL/a@zfs-auto-snap_daily6

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $TIME_SANITY_FAIL $?

    general_test_teardown
}

test_time_sanity_remote () {
    log "=================================================="
    log "Test time sanity remote..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    # create a snapshot with the same name as one on the source, but newer
    sleep 1
    zfs snapshot $DEST_POOL/a@zfs-auto-snap_daily6

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --remote-mode ssh --remote-user "root" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --ssh-options ""
    check_result $TIME_SANITY_FAIL $?

    general_test_teardown
}

test_invalid_mode () {
    log "=================================================="
    log "Test invalid mode..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    zfs set $ZFS_MODE_PROPERTY=lol $SOURCE_POOL/a

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --remote-mode ssh --remote-user "root" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090
    check_result $MODE_INVALID $?

    general_test_teardown
}

test_nested () {
    log "=================================================="
    log "Test successful nested backup..."
    log "=================================================="

    general_test_setup
    create_snapshots
    nested_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --nest-name-property "furneaux:backupnestname" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_path_on_top_level () {
    log "=================================================="
    log "Test path set on top level dataset..."
    log "=================================================="

    general_test_setup
    create_snapshots

    zfs set $ZFS_MODE_PROPERTY=path $SOURCE_POOL
    zfs send -R $SOURCE_POOL@zfs-auto-snap_daily1 | sudo zfs recv -dF $DEST_POOL

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --nest-name-property "furneaux:backupnestname" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $ROOT_INVALID $?

    general_test_teardown
}

test_root_on_non_top_level () {
    log "=================================================="
    log "Test root set on non top level dataset..."
    log "=================================================="

    general_test_setup
    create_snapshots

    zfs set $ZFS_MODE_PROPERTY=root $SOURCE_POOL/a
    zfs set furneaux:backupnestname=n $SOURCE_POOL/a
    zfs send -R $SOURCE_POOL/a@zfs-auto-snap_daily1 | sudo zfs recv -dF $DEST_POOL

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --nest-name-property "furneaux:backupnestname" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $ROOT_INVALID $?

    general_test_teardown
}

test_root () {
    log "=================================================="
    log "Test successful root backup..."
    log "=================================================="

    general_test_setup
    create_snapshots
    root_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --nest-name-property "furneaux:backupnestname" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_no_nest_name () {
    log "=================================================="
    log "Test no nest name..."
    log "=================================================="

    general_test_setup
    create_snapshots

    zfs set $ZFS_MODE_PROPERTY=root $SOURCE_POOL
    zfs send -R $SOURCE_POOL@zfs-auto-snap_daily1 | sudo zfs recv $DEST_POOL/n/$SOURCE_POOL

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --nest-name-property "furneaux:backupnestname" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $NEST_NAME_MISSING $?

    general_test_teardown
}

test_lockfile () {
    log "=================================================="
    log "Test lockfile..."
    log "=================================================="

    echo $$ > $LOCK_FILE
    ./zfs-backup-manager.sh --remote-host "" --remote-mode mbuffer --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --remote-user "root" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090
    check_result $LOCK_FILE_PRESENT $?
    rm $LOCK_FILE
}

test_ignore_lockfile () {
    log "=================================================="
    log "Test ignore lockfile..."
    log "=================================================="

    general_test_setup
    path_setup

    echo $$ > $LOCK_FILE
    ./zfs-backup-manager.sh --remote-host "" --ignore-lock --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --remote-user "root" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_ssh () {
    log "=================================================="
    log "Test successful ssh backup..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode ssh --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --remote-user "root" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --ssh-options ""
    check_result $SUCCESS $?

    general_test_teardown
}

test_mbuffer () {
    log "=================================================="
    log "Test successful mbuffer backup..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode mbuffer --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --remote-user "root" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090
    check_result $SUCCESS $?

    general_test_teardown
}

test_backup_disabled () {
    log "=================================================="
    log "Test backup disabled..."
    log "=================================================="

    general_test_setup
    create_snapshots
    path_setup

    zfs set $ZFS_MODE_PROPERTY=off $SOURCE_POOL/a

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode mbuffer --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --remote-user "root" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090
    check_result $SUCCESS $?

    general_test_teardown
}

test_mbuffer_auto_blocksize () {
    log "=================================================="
    log "Test auto mbuffer blocksize..."
    log "=================================================="

    general_test_setup

    zfs set recordsize=1M $SOURCE_POOL/a

    create_snapshots
    path_setup

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-mode mbuffer --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --remote-user "root" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "auto" --mbuffer-buffer-size "1G" --mbuffer-port 9090
    check_result $SUCCESS $?

    general_test_teardown
}

test_up_to_date () {
    log "=================================================="
    log "Test up to date..."
    log "=================================================="

    general_test_setup
    path_setup

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $SUCCESS $?

    general_test_teardown
}

test_missing_property () {
    log "=================================================="
    log "Test missing property..."
    log "=================================================="

    general_test_setup
    path_setup

    ./zfs-backup-manager.sh --remote-host "" --mode-property "lol:thisaintright" --remote-pool "$DEST_POOL" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
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

test_remote_mode_invalid () {
    log "=================================================="
    log "Test remote mode invalid"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode lol
    check_result $CONFIG_INVALID $?
}

test_snapshot_pattern_missing () {
    log "=================================================="
    log "Test snapshot pattern missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $CONFIG_INVALID $?
}

test_mode_property_missing () {
    log "=================================================="
    log "Test mode property missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $CONFIG_INVALID $?
}

test_mbuffer_block_size_missing () {
    log "=================================================="
    log "Test mbuffer block size missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh
    check_result $CONFIG_INVALID $?
}

test_mbuffer_port_missing () {
    log "=================================================="
    log "Test mbuffer port missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port "" --remote-mode ssh
    check_result $CONFIG_INVALID $?
}

test_mbuffer_buffer_size_missing () {
    log "=================================================="
    log "Test mbuffer buffer size missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "" --mbuffer-port 9090 --remote-mode ssh
    check_result $CONFIG_INVALID $?
}

test_remote_user_missing () {
    log "=================================================="
    log "Test remote user missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-pool "$DEST_POOL" --mode-property "$ZFS_MODE_PROPERTY" --snapshot-pattern "zfs-auto-snap_daily" --mbuffer-block-size "128k" --mbuffer-buffer-size "1G" --mbuffer-port 9090 --remote-mode ssh --remote-user ""
    check_result $CONFIG_INVALID $?
}

test_all_config_missing () {
    log "=================================================="
    log "Test all config missing"
    log "=================================================="

    ./zfs-backup-manager.sh --remote-host "localhost" --remote-pool "" --mode-property "" --snapshot-pattern "" --mbuffer-block-size "" --mbuffer-buffer-size "" --mbuffer-port "" --remote-mode lol --remote-user ""
    check_result $CONFIG_INVALID $?
}

print_help () {
    echo "Usage: $(basename $0) [--fail-fast] [--cleanup]"
    echo "  --fail-fast         Stop testing on the first failure."
    echo "  --cleanup           Cleanup after a failed test run."
    exit 0
}

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    --fail-fast)
        FAIL_FAST=1
    ;;
    --cleanup)
        general_test_teardown
        exit 0
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

# negative tests
test_lockfile
test_invalid_argument
test_remote_mode_invalid
test_snapshot_pattern_missing
test_mode_property_missing
test_mbuffer_block_size_missing
test_mbuffer_port_missing
test_mbuffer_buffer_size_missing
test_remote_user_missing
test_all_config_missing
test_invalid_mode
test_missing_property
test_missing_nest_name_property
test_root_on_non_top_level
test_path_on_top_level
test_no_nest_name
test_no_pattern_match
test_no_pattern_match_remote
test_remote_ahead_of_local
test_time_sanity_local
test_time_sanity_remote

# positive tests
test_simulation
test_ignore_lockfile
test_additional_options
test_backup_disabled
test_nested
test_local
test_ssh
test_mbuffer
test_mbuffer_auto_blocksize
test_root
test_chain_backup_local
test_chain_backup_ssh
test_chain_backup_mbuffer
test_up_to_date

log ""
log "$TOTAL_TESTS total tests. $PASS_TESTS passed, $FAIL_TESTS failed."
log ""
log "All tests complete. Exiting."

exit 0
