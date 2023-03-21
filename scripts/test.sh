#!/bin/bash

set -e

PARENT_DIR=$( cd -- "$( dirname -- "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )" &> /dev/null && pwd )
test_configs="$PARENT_DIR"/configs/test_configs

check_enc () {
    if grep -qF "ssh-ed25519" "$PARENT_DIR"/configs/nix_configs/hosts/fungus/modules/networking/ssh.nix; then
        echo " └── DECRYPT: True"
    else
        echo " └── DECRYPT: False"
    fi
}

echo "[+] Init build"
time "$PARENT_DIR"/build.sh --keep-configs "$test_configs"/test.yml >/dev/null 2>&1

tests=(
    "$test_configs"/test.yml
    "$test_configs"/test.json
    "$test_configs"/test_sops.yml
    "$test_configs"/test_sops.json
)

for test in "${tests[@]}"; do
    basename="${test##*/}"
    ext="${basename##*.}"

    sops=false
    add=''

    if [[ "$(basename "$test")" =~ sops ]]; then
        sops=true
        add='-sops'
    fi

    printf "\n[+] STDIN (%s%s) -> SCRIPT\n" "$ext" "$add"
    cat "$test" | "$PARENT_DIR"/build.sh --keep-configs "$@"
    if $sops; then 
        check_enc
    fi

    printf "\n[+] ARG   (%s%s) -> SCRIPT\n" "$ext" "$add"
    "$PARENT_DIR"/build.sh --keep-configs "$test" "$@"
    if $sops; then 
        check_enc
    fi
done

