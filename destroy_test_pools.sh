#!/bin/bash -e

SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)

SOURCE_POOL_FILE="testsource.img"
SOURCE2_POOL_FILE="testsource2.img"
DEST_POOL_FILE="testdest.img"

zpool destroy testsource
zpool destroy testsource2
zpool destroy testdest

rm $SOURCE_POOL_FILE
rm $SOURCE2_POOL_FILE
rm $DEST_POOL_FILE
