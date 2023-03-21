#!/bin/bash

PARENT_DIR=$( cd -- "$( dirname -- "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )" &> /dev/null && pwd )
TARGET_DIR="$1"

# create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# define an array with the files to copy
files=( "$PARENT_DIR/result/bzImage"
        "$PARENT_DIR/result/initrd"
        "$PARENT_DIR/result/netboot.ipxe"
)

# loop through the array and copy each file to target directory
for file in "${files[@]}"
do
    cp -f "$file" "$TARGET_DIR"
done