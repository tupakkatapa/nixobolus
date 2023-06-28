#!/usr/bin/env bash
# Script for building a host with injected json data

set -o pipefail
trap cleanup EXIT
trap cleanup SIGINT

# This path is also hard-coded in flake.nix
data_nix="/tmp/data.nix"

# Default flags for nix-command
nix_flags=(
  --impure
  --no-warn-dirty
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
)

# Cleanup which will be executed at exit
cleanup() {
  if [ -f "$data_nix" ]; then
    rm "$data_nix"
  fi
}

# Check dependencies 
if ! command -v nix-instantiate >/dev/null 2>&1; then
  echo "Error: 'nix-instantiate' command not found. Please install the Nix package manager."
  echo "For installation instructions, visit: https://nixos.org/download.html"
  exit 1
else
  if ! command -v nix >/dev/null 2>&1; then
    echo "Error: 'nix' command not found. Please install the nix-command."
    echo "You can install the nix-command by running 'nix-env -iA nixpkgs.nix'."
    exit 1
  fi
fi

# Function to display help message
display_usage() {
  cat <<USAGE
Usage: $0 [options]

Options:

  -b, --base <hostname>
      Set the base configuration with the specified hostname.
      Available configurations: "homestakeros".

  -j, --json <data>
      Specify raw JSON data to inject into the base configuration.

  -h, --help
      Displays this help message.

Examples:
  
  Local:
      nix run .#buidl -- --base homestakeros --json '{"erigon":{"enable":true}}'

  Remote:
      nix run github:ponkila/nixobolus#buidl -- -b homestakeros -j '{"erigon":{"enable":true}}'

USAGE
}

# Check that any argument exists
[[ $# -eq 0 ]] && {
  display_usage
  exit 1
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -b|--base)
      hostname="$2"
      shift 2 ;;
    -j|--json)
      json_data="$2"
      shift 2 ;;
    -h|--help)
      display_usage
      exit 0 ;;
    *)
      echo "Error: unknown option -- '$1'"
      echo "Try '--help' for more information."
      exit 1 ;;
  esac
done

# Check that base configuration has been set
if [[ -z $hostname ]]; then
  echo "Error: base configuration is required."
  echo "Try '--help' for more information."
  exit 1
fi

# Create data.nix from JSON data
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

  # Display injected data
  echo -e "$data_nix: \n$(cat $data_nix)"
else
  cleanup
fi

# Run nix build command
nix build .#"$hostname" "${nix_flags[@]}" || \
  { echo "Fetching from GitHub"; nix build github:ponkila/nixobolus#"$hostname" "${nix_flags[@]}" || exit 1; }
