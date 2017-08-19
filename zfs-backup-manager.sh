#!/bin/bash

# ZFS Backup Manager
# Version 0.0.1
# Copyright 2017 Romaco Canada, Mark Furneaux

# ===== Config Options =====

# The naming pattern to look for when finding snapshots to backup.
# The pattern does not need to be sortable, as snapshot creation time is used for ordering.
SNAPSHOT_PATTERN="zfs-auto-snap_daily"

# This property must be present with the correct value on a dataset for it to be backed up.
# Valid values are "path", "nested", and "root"
# path   - Creates a path of datasets on the destination that matches the source.
#          The pool name is stripped from the path.
#          e.g. With "c" having the "path" mode:
#          /sourcepool/a/b/c backs up to /backuppool/a/b/c
# nested - Nests the dataset on the destination pool within a dataset set by the
#          NEST_NAME_PROPERTY, preserving the rest of the path as in the "path" option.
#          The pool name is not stripped from the path. The nested dataset must already exist.
#          e.g. With the nested name set to "nest" and "sourcepool" having the "nested" mode:
#          /sourcepool/a/b/c backs up to /backuppool/nest/sourcepool/a/b/c
# root   - Special handling for root filesystems. Performs a backup similar to
#          the "nested" mode, however all mountpoints are set to "none" during the receive.
#          The pool name is not stripped from the path. The nested dataset must already exist.
#          This option can only be set on top level pool datasets.
#          e.g. With the nested name set to "system1" and "rootpool" having the "root" mode:
#          /rootpool/a/b/c backs up to /backuppool/system1/rootpool/a/b/c
MODE_PROPERTY="furneaux:autobackup"

# The property which contains the name to nest the dataset under on the destination pool.
# Only needs to be set if one or more datasets have the "nested" or "root" modes.
NEST_NAME_PROPERTY="furneaux:backupnestname"

# Pool on the destination for backups to be received into.
REMOTE_POOL="btank"

# Backup machine hostname. Set to "" for backups on the same machine.
REMOTE_HOST="darwin"

# User on the remote destination machine. Need not be set unless REMOTE_HOST is set.
# There must be an SSH key already installed for passwordless authentication into this account.
# This user must also have the rights to run ZFS commands via sudo without password authentication.
# If using root, sudo is not used.
REMOTE_USER="root"

# How to transfer data over the network. Set to either "ssh" or "mbuffer".
# mbuffer uses raw TCP with buffers on either side and is therefore much faster.
# However mbuffer is not encrypted and as such should only be used on local networks.
# mbuffer still requires SSH for remote system login.
REMOTE_MODE="mbuffer"

# The size of the blocks of data sent by mbuffer. It is usually best to set this the same as the
# ZFS recordsize. Use "auto" to set this automatically to the recordsize per dataset.
MBUFFER_BLOCK_SIZE="auto"

# Port for mbuffer to bind to when receiving data.
MBUFFER_PORT="9090"

# Size of mbuffer's memory buffer on the sending and receiving side.
MBUFFER_BUFF_SIZE="1G"

# Options for the ssh session used during send/receive.
SSH_OPTIONS="-o Ciphers=arcfour"

# ===== End of Config Options =====

LOCK_FILE="/var/run/zfs-backup-manager.lock"
SIMULATE=0
IGNORE_LOCK=0
ZFS_CMD="/sbin/zfs"
SSH_CMD="/usr/bin/ssh"
MBUFFER_CMD="/usr/bin/mbuffer"
REMOTE_ZFS_CMD="$ZFS_CMD"
NEST_NAME=""
RECEIVE_LOG_FILE="/tmp/zfs-backup-manager-sr.log"

# Error codes this script returns
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
LOCK_WRITE_FAIL=13

log () {
    echo "[ZFS Backup Manager] $1"
}

print_help () {
    echo "Usage: $(basename $0) [--simulate] [--ignore-lock]"
    echo "  --simulate                Print the commands which would be run,"
    echo "                            but don't actually execute them."
    echo "  --ignore-lock             Ignore the presence of a lock file and run regardless."
    echo "                            This option is dangerous and should only be used to"
    echo "                            clear a previous failure."
    echo ""
    echo "The following options override those set in the script."
    echo "See the script header for a detailed explanation of each option with examples."
    echo "  --snapshot-pattern        The pattern to search for in snapshot names to backup."
    echo "  --mode-property           The ZFS property which contains the backup mode."
    echo "  --nest-name-property      The ZFS property which contains the dataset name to nest within."
    echo "  --remote-pool             The destination pool name."
    echo "  --remote-host             The hostname of the destination. Pass \"\" for the local machine."
    echo "  --remote-user             The user to login as on the destination."
    echo "  --remote-mode             The transfer mode to a remote system. (ssh/mbuffer)"
    echo "  --mbuffer-block-size      The block size to set when using mbuffer, or \"auto\" to use recordsize."
    echo "  --mbuffer-port            The port for mbuffer to listen on."
    echo "  --mbuffer-buffer-size     The size of the send and receive buffers when using mbuffer."
    echo "  --ssh-options             Additional options to pass to SSH."
    echo ""
    echo "This script must be run as root."
    exit $SUCCESS
}

sanitize_config () {
    IS_INVALID=0
    if [ "$SNAPSHOT_PATTERN" == "" ]; then
        log "Error: Missing snapshot pattern."
        IS_INVALID=1
    fi
    if [ "$MODE_PROPERTY" == "" ]; then
        log "Error: Missing mode property."
        IS_INVALID=1
    fi
    if [ "$REMOTE_POOL" == "" ]; then
        log "Error: Missing remote pool."
        IS_INVALID=1
    fi
    if [ "$MBUFFER_BLOCK_SIZE" == "" ]; then
        log "Error: Missing mbuffer block size."
        IS_INVALID=1
    fi
    if [ "$MBUFFER_PORT" == "" ]; then
        log "Error: Missing mbuffer port."
        IS_INVALID=1
    fi
    if [ "$MBUFFER_BUFF_SIZE" == "" ]; then
        log "Error: Missing mbuffer buffer size."
        IS_INVALID=1
    fi
    if [ "$REMOTE_MODE" != "ssh" ] && [ "$REMOTE_MODE" != "mbuffer" ]; then
        log "Error: Invalid remote mode."
        IS_INVALID=1
    fi
    if [ "$REMOTE_HOST" != "" ]; then
        if [ "$REMOTE_USER" == "" ]; then
            log "Error: Missing remote user."
            IS_INVALID=1
        fi
    fi

    if [ "$IS_INVALID" -eq 1 ]; then
        log "Cannot run without full configuration. Aborting."
        exit $CONFIG_INVALID
    fi
}

check_root () {
    if [ $(whoami) != "root" ]; then
        ZFS_CMD="sudo $ZFS_CMD"
    fi
    if [ "$REMOTE_USER" != "root" ]; then
        REMOTE_ZFS_CMD="sudo $REMOTE_ZFS_CMD"
    fi
}

get_lock () {
    if [ -e $LOCK_FILE ] && [ $IGNORE_LOCK -eq 0 ]; then
        log "Error: Lock file is present!"
        log "This either means that another instance of this script is running,"
        log "or that a previous run crashed. If you are sure that there is no other backup"
        log "in progress, run this script with \"--ignore-lock\" to suppress this error."
        exit $LOCK_FILE_PRESENT
    elif [ $IGNORE_LOCK -eq 1 ]; then
        log "Warning: Ignoring lock file"
    fi

    echo $$ > $LOCK_FILE

    if [ $? -ne 0 ]; then
        log "Error: Lock file could not be written."
        log "Aborting."
        exit $LOCK_WRITE_FAIL
    fi
}

release_lock () {
    rm $LOCK_FILE
}

check_for_datasets () {
    COUNT=$($LIST_DATASETS_TO_BACKUP_CMD | wc -l)
    if [ $COUNT -lt 1 ]; then
        log "Error: Could not find any datasets with the \"$MODE_PROPERTY\" property set."
        log "Nothing to do, aborting."
        release_lock
        exit $NO_DATASETS
    fi
}

run_backup () {
    DATASET=$1
    DATASET_NO_POOL=${DATASET#*/}
    DATASET_BASENAME=${DATASET##*/}
    MODE=$2
    ZFS_OPTIONS=""

    case $MODE in
    path)
        DESTINATION_DATASET="$REMOTE_POOL/$DATASET_NO_POOL"
        DESTINATION="$REMOTE_POOL"
        ZFS_OPTIONS="-d"
        ;;
    nested)
        DESTINATION_DATASET="$REMOTE_POOL/$NEST_NAME/$DATASET_NO_POOL"
        DESTINATION="$REMOTE_POOL/$NEST_NAME/$DATASET_NO_POOL"
        ;;
    root)
        DESTINATION_DATASET="$REMOTE_POOL/$NEST_NAME/$DATASET_NO_POOL"
        DESTINATION="$REMOTE_POOL/$NEST_NAME/$DATASET_NO_POOL"
        ZFS_OPTIONS="-o mountpoint=none"
        ;;
    *)
        log "Error: Unsupported backup mode invoked."
        log "Internal error, aborting."
        exit $INTERNAL_FAULT
        ;;
    esac

    log ""
    log "Processing dataset: $DATASET"
    log "Using mode: $MODE"

    if [ $MODE == "nested" ] || [ $MODE == "root" ]; then
        log "Nesting in: $NEST_NAME"
    fi

    LOCAL_HEAD="$($ZFS_CMD list -t snapshot -H -S creation -o name -d 1 $DATASET | grep $SNAPSHOT_PATTERN | head -1)"
    if [ -z "$LOCAL_HEAD" ]; then
        log "Error: No snapshots matching pattern \"$SNAPSHOT_PATTERN\" found in dataset \"$DATASET\"."
        log "Aborting."
        exit $NO_PATTERN_MATCH
    fi
    LOCAL_SNAP=${LOCAL_HEAD#*@}

    log "Local HEAD is: $LOCAL_SNAP"

    if [ "$REMOTE_HOST" == "" ]; then
        REMOTE_HEAD="$($ZFS_CMD list -t snapshot -H -S creation -o name -d 1 $DESTINATION_DATASET | grep $SNAPSHOT_PATTERN | head -1)"
        if [ $? -ne 0 ]; then
            log "Error: Could not fetch local snapshot list on destination pool."
            log "Aborting."
            exit $COMM_ERROR
        fi
    else
        REMOTE_HEAD="$($SSH_CMD -n $REMOTE_USER@$REMOTE_HOST $REMOTE_ZFS_CMD list -t snapshot -H -S creation -o name -d 1 $DESTINATION_DATASET | grep $SNAPSHOT_PATTERN | head -1)"
        if [ $? -ne 0 ]; then
            log "Error: Could not fetch remote snapshot list on destination pool."
            log "Aborting."
            exit $COMM_ERROR
        fi
    fi
    if [ -z "$REMOTE_HEAD" ]; then
        log "Error: No snapshots matching pattern \"$SNAPSHOT_PATTERN\" found in dataset \"$DATASET\" on remote."
        log "Aborting."
        exit $NO_PATTERN_MATCH
    fi
    REMOTE_SNAP=${REMOTE_HEAD#*@}

    log "Remote HEAD is: $REMOTE_SNAP"

    $ZFS_CMD list -t snapshot -H $DATASET@$REMOTE_SNAP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "Error: HEAD snapshot on the destination does not exist locally."
        log "No reference for incremental send matching the set pattern exists."
        log "The destination must be brought back up to date manually."
        exit $MISSING_SNAPSHOT
    fi

    if [ "$LOCAL_SNAP" == "$REMOTE_SNAP" ]; then
        log "This dataset is up-to-date on the destination."
        return 0
    fi

    LOCAL_SNAP_TIME=$($ZFS_CMD get -Hp -o value creation $DATASET@$LOCAL_SNAP)
    if [ "$REMOTE_HOST" == "" ]; then
        REMOTE_SNAP_TIME=$($ZFS_CMD get -Hp -o value creation $DESTINATION_DATASET@$REMOTE_SNAP)
    else
        REMOTE_SNAP_TIME=$($SSH_CMD -n $REMOTE_USER@$REMOTE_HOST $REMOTE_ZFS_CMD get -Hp -o value creation $DESTINATION_DATASET@$REMOTE_SNAP)
    fi
    if [ $LOCAL_SNAP_TIME -lt $REMOTE_SNAP_TIME ]; then
        log "Error: Local snapshot \"$LOCAL_SNAP\" is older than \"$REMOTE_SNAP\"."
        log "Aborting."
        exit $TIME_SANITY_FAIL
    fi

    log "Performing send/receive..."

    if [ "$REMOTE_HOST" == "" ]; then
        RUN_CMD_SEND="$ZFS_CMD send -R -I $REMOTE_SNAP $DATASET@$LOCAL_SNAP"
        RUN_CMD_RECV="$ZFS_CMD recv -v $ZFS_OPTIONS -F $DESTINATION"

        if [ $SIMULATE -eq 1 ]; then
            log "Running in simulation. Not executing: $RUN_CMD_SEND | $RUN_CMD_RECV"
        else
            $RUN_CMD_SEND | $RUN_CMD_RECV
            if [ $? -ne 0 ]; then
                log "Error: Backing up \"$DATASET@$LOCAL_SNAP\" failed."
                log "Aborting."
                exit $SEND_RECV_FAIL
            fi
        fi
    else
        if [ "$REMOTE_MODE" == "ssh" ]; then
            RUN_CMD_SEND="$ZFS_CMD send -R -I $REMOTE_SNAP $DATASET@$LOCAL_SNAP"
            RUN_CMD_RECV="$SSH_CMD $SSH_OPTIONS $REMOTE_USER@$REMOTE_HOST $REMOTE_ZFS_CMD recv -v $ZFS_OPTIONS -F $DESTINATION"

            if [ $SIMULATE -eq 1 ]; then
                log "Running in simulation. Not executing: $RUN_CMD_SEND | $RUN_CMD_RECV"
            else
                $RUN_CMD_SEND | $RUN_CMD_RECV
                if [ $? -ne 0 ]; then
                    log "Error: Backing up \"$DATASET@$LOCAL_SNAP\" failed."
                    log "Aborting."
                    exit $SEND_RECV_FAIL
                fi
            fi
        elif [ "$REMOTE_MODE" == "mbuffer" ]; then
            if [ $MBUFFER_BLOCK_SIZE == "auto" ]; then
                MBUFFER_REAL_BLOCK_SIZE="$($ZFS_CMD get -H -o value recordsize $DATASET)"
            else
                MBUFFER_REAL_BLOCK_SIZE="$MBUFFER_BLOCK_SIZE"
            fi
            log "Using blocksize: $MBUFFER_REAL_BLOCK_SIZE"

            REMOTE_RUN_CMD="$SSH_CMD $REMOTE_USER@$REMOTE_HOST $MBUFFER_CMD -s $MBUFFER_REAL_BLOCK_SIZE -m $MBUFFER_BUFF_SIZE -I $MBUFFER_PORT | $REMOTE_ZFS_CMD recv -v $ZFS_OPTIONS -F $DESTINATION"
            LOCAL_RUN_CMD_SEND="$ZFS_CMD send -R -I $REMOTE_SNAP $DATASET@$LOCAL_SNAP"
            LOCAL_RUN_CMD_MBUFFER="$MBUFFER_CMD -s $MBUFFER_REAL_BLOCK_SIZE -m $MBUFFER_BUFF_SIZE -O $REMOTE_HOST:$MBUFFER_PORT"
            if [ $SIMULATE -eq 1 ]; then
                log "Running in simulation. Not executing: $REMOTE_RUN_CMD"
                log "Running in simulation. Not executing: $LOCAL_RUN_CMD_SEND | $LOCAL_RUN_CMD_MBUFFER"
            else
                $REMOTE_RUN_CMD > $RECEIVE_LOG_FILE 2>&1 &
                SUBPID=$!
                sleep 3
                $LOCAL_RUN_CMD_SEND | $LOCAL_RUN_CMD_MBUFFER
                STATUS=$?
                log ""
                log "Receive Log:"
                wait $SUBPID
                cat $RECEIVE_LOG_FILE
                if [ $STATUS -ne 0 ]; then
                    log "Error: Backing up \"$DATASET@$LOCAL_SNAP\" failed."
                    log "Aborting."
                    exit $SEND_RECV_FAIL
                fi
            fi
        fi
    fi
}

check_nest_name () {
    if [ "$NEST_NAME_PROPERTY" == "" ]; then
        log "Error: Nest name configuration option is not set."
        log "Aborting."
        exit $CONFIG_INVALID
    fi

    NEST_NAME=$($ZFS_CMD get -s local -H -o value $NEST_NAME_PROPERTY $DATASET)
    if [ $? -ne 0 ]; then
        log "Error: Property \"$NEST_NAME_PROPERTY\" is not set on dataset \"$DATASET\"."
        log "Aborting."
        exit $NEST_NAME_MISSING
    fi
    if [ "$NEST_NAME" == "" ]; then
        log "Error: Property \"$NEST_NAME_PROPERTY\" is empty on dataset \"$DATASET\"."
        log "Aborting."
        exit $NEST_NAME_MISSING
    fi
}

remove_tmp_files () {
    if [ -e $RECEIVE_LOG_FILE ]; then
        rm $RECEIVE_LOG_FILE
    fi
}

process_datasets () {
    while read DATASET MODE
    do
        case $MODE in
        path)
            if [ "$DATASET" == "$(basename $DATASET)" ]; then
                log "Error: Dataset \"$DATASET\" is set to mode \"$MODE\" but is a top-level dataset."
                log "Aborting."
                exit $ROOT_INVALID
            fi
            run_backup $DATASET $MODE
            ;;
        nested)
            check_nest_name
            run_backup $DATASET $MODE
            ;;
        root)
            check_nest_name
            if [ "$DATASET" == "$(basename $DATASET)" ]; then
                run_backup $DATASET $MODE
            else
                log "Error: Dataset \"$DATASET\" is set to mode \"$MODE\" but is not a root dataset."
                log "Aborting."
                exit $ROOT_INVALID
            fi
            ;;
        *)
            log "Error: Dataset \"$DATASET\" has an invalid mode \"$MODE\" set."
            log "Aborting."
            exit $MODE_INVALID
            ;;
        esac
    done < <($LIST_DATASETS_TO_BACKUP_CMD)
}

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    --simulate)
        SIMULATE=1
        log "Simulating write commands"
    ;;
    --ignore-lock)
        IGNORE_LOCK=1
    ;;
    -h|--help)
        print_help
    ;;
    --snapshot-pattern)
        SNAPSHOT_PATTERN="$2"
        shift
    ;;
    --mode-property)
        MODE_PROPERTY="$2"
        shift
    ;;
    --nest-name-property)
        NEST_NAME_PROPERTY="$2"
        shift
    ;;
    --remote-pool)
        REMOTE_POOL="$2"
        shift
    ;;
    --remote-host)
        REMOTE_HOST="$2"
        shift
    ;;
    --remote-user)
        REMOTE_USER="$2"
        shift
    ;;
    --remote-mode)
        REMOTE_MODE="$2"
        shift
    ;;
    --mbuffer-block-size)
        MBUFFER_BLOCK_SIZE="$2"
        shift
    ;;
    --mbuffer-port)
        MBUFFER_PORT="$2"
        shift
    ;;
    --mbuffer-buffer-size)
        MBUFFER_BUFF_SIZE="$2"
        shift
    ;;
    --ssh-options)
        SSH_OPTIONS="$2"
        shift
    ;;
    *)
        log "Error: Invalid argument: \"$key\""
        print_help
    ;;
esac
shift
done

LIST_DATASETS_TO_BACKUP_CMD="$ZFS_CMD get -s local -H -o name,value $MODE_PROPERTY"

log "ZFS Backup Manager v0.0.1 Starting..."

sanitize_config

check_root

get_lock

check_for_datasets

process_datasets

release_lock

remove_tmp_files

log ""
log "Backup process completed successfully. Exiting."

exit $SUCCESS
