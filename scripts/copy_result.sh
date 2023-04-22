#!/bin/bash
# deps: none
# desc: simple script for copying result to target directory
# usage: ./scripts/copy_result.sh <target_dir>

PARENT_DIR=$( cd -- "$( dirname -- "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )" &> /dev/null && pwd )
HOST="$1"
TARGET_DIR="$2"

# create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# define an array with the files to copy
files=( "bzImage"
        "initrd"
        "netboot.ipxe"
)

# loop through the array and copy each file to target directory
for file in "${files[@]}"
do
    cp -f "$PARENT_DIR/result/$HOST/$file" "$TARGET_DIR"
done