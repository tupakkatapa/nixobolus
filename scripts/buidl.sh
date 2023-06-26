#!/usr/bin/env bash
# script for building a host with injected json data
# usage: nix run .#buidl -- --hostname <hostname> --format <format> --data <data> ...

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

# Cleanup which will be executed at exit
cleanup() {
  rm -rf "$data_nix"
}

# Create temporary directory
data_nix="/tmp/data.nix"

# Create data.nix file
cat > "$data_nix" << EOF
{ pkgs, config, inputs, lib, ... }:
{
  config = {
    homestakeros = {
      # Erigon options
      erigon = {
        enable = true;
        endpoint = "http://192.168.100.10:8551";
        datadir = "/var/mnt/erigon";
      };
    };
  };
}
EOF

# Run nix build command
nix build .#homestakeros --impure --no-warn-dirty || exit 1
