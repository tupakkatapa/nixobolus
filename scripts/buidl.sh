#!/usr/bin/env bash
# Script for building a host with injected json data

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

data_nix="/tmp/data.nix"

# Cleanup which will be executed at exit
cleanup() {
  rm -rf "$data_nix"
}

# Function to display help message
display_usage() {
  cat <<USAGE
Usage: $0 [options]

Options:

  -b, --base <hostname>
      Set the base configuration with the specified hostname.
      Available configurations: "homestakeros".

  -j, --json <data>
      Specifie raw JSON data to inject into the base configuration.

  -h, --help
      Displays this help message.

Example:

  nix run .#buidl -- --base homestakeros --json '{"erigon":{"enable":true}}'

USAGE
}

# Parse command line arguments
[[ $# -eq 0 ]] && {
  display_usage
  exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -b|--base)
            hostname="$2"
            shift 2 ;;
        -j|--json)
            shift
            json_data="$*"
            break ;;
        -h|--help)
            display_usage
            exit 0 ;;
        *)
            echo Unknown option: "$1"
            exit 1 ;;
    esac
done

if [[ -n $json_data ]]; then
  # Escape double quotes
  esc_json_data=$(echo "$json_data" | sed 's/"/\\"/g')
  
  # Convert JSON to Nix expression
  nix_expr=$(nix-instantiate --eval --expr "builtins.fromJSON \"$esc_json_data\"")

  # Create data.nix file
  cat > "$data_nix" << EOF
{ pkgs, config, inputs, lib, ... }:
{
  $hostname = $nix_expr;
}
EOF
fi

# Display injected data
echo -e "$data_nix: \n$(cat $data_nix)"

# Run nix build command
nix build .#"$hostname" --impure --no-warn-dirty || exit 1
