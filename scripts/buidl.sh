#!/usr/bin/env bash
# Script for building a host with injected json data

set -o pipefail
trap cleanup EXIT
trap 'cleanup && exit 0' SIGINT

# Default values
verbose=false
output_path="./result"

# Do not change, this path is also hard-coded in flake.nix
data_nix="/tmp/data.nix" 

# Cleanup which will be executed at exit
cleanup() {
  if [ -f "$data_nix" ]; then
    rm "$data_nix"
  fi
}

# Check dependencies 
if ! command -v nix-instantiate >/dev/null 2>&1; then
  echo "error: 'nix-instantiate' command not found. Please install the Nix package manager."
  echo "for installation instructions, visit: https://nixos.org/download.html"
  exit 1
else
  if ! command -v nix >/dev/null 2>&1; then
    echo "error: 'nix' command not found. Please install the nix-command."
    echo "you can install the nix-command by running 'nix-env -iA nixpkgs.nix'."
    exit 1
  fi
fi

# Function to display help message
display_usage() {
  cat <<USAGE
Usage: $0 [options] [json_data]

Arguments:
  json_data
      Specify raw JSON data to inject into the base configuration. It can be provided as a positional argument or piped into the script.

Options:
  -b, --base <hostname>
      Set the base configuration with the specified hostname. Available configurations: 'homestakeros'.

  -o, --output <output_path>
      Set the output path for the build result symlinks. Default: './result'.

  -v, --verbose
      Enable verbose output, which displays the contents of the injected data and the trace for debugging purposes.

  -h, --help
      Display this help message.

Examples:
  Local, using pipe:
      echo '{"execution":{"erigon":{"enable":true}}}' | nix run .#buidl -- --base homestakeros

  Remote, using positional argument:
      nix run github:ponkila/nixobolus#buidl -- -b homestakeros '{"execution":{"erigon":{"enable":true}}}'

USAGE
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -b|--base)
      hostname="$2"
      shift 2 ;;
    -o|--output)
      output_path="$2"
      shift 2 ;;
    -v|--verbose)
      verbose=true
      shift ;;
    -h|--help)
      display_usage
      exit 0 ;;
    *)
      # Check if argument is JSON data
      if [[ "$1" =~ ^\{.*\}$ ]]; then
        json_data="$1"
      else
        echo "error: unknown option -- '$1'"
        echo "try '--help' for more information."
        exit 1
      fi
      shift ;;
  esac
done

# Default flags for 'nix build' command
nix_flags=(
  --accept-flake-config
  --extra-experimental-features 'nix-command flakes'
  --impure
  --no-warn-dirty
  --out-link "$output_path"
)

# Append '--show-trace' and '--debug' if verbose flag is true
if [ "$verbose" = true ]; then
  nix_flags+=("--show-trace" "--debug" )
fi

# Read JSON data from stdin if it's not provided as an argument
if [ -z "$json_data" ] && ! tty -s && [ -p /dev/stdin ]; then
  # Read JSON data from stdin
  json_data=$(</dev/stdin)
fi

# Check that base configuration has been set
if [[ -z $hostname ]]; then
  echo "error: base configuration is required."
  echo "try '--help' for more information."
  exit 1
fi

# Create data.nix from JSON data
if [[ -n $json_data ]]; then
  # Escape double quotes
  esc_json_data="${json_data//\"/\\\"}"

  # Convert JSON to Nix expression
  nix_expr=$(nix-instantiate --eval --expr "builtins.fromJSON \"$esc_json_data\"") || exit 1

  # Create data.nix file
  cat > "$data_nix" << EOF
{ pkgs, config, inputs, lib, ... }:
{
  $hostname = $nix_expr;
}
EOF
else
  # Precaution
  cleanup
fi

# Run nix build command
output=$(nix build .#"$hostname" "${nix_flags[@]}")
if [[ $output == *"error: could not find a flake.nix file"* ]]; then
  if [ "$verbose" = true ]; then echo "fetching from github:ponkila/nixobolus"; fi
  nix build github:ponkila/nixobolus#"$hostname" "${nix_flags[@]}" || exit 1
fi

# Display injected data if verbose is true
if [ "$verbose" = true ] && [ -f "$data_nix" ]; then
  # Replace newlines with spaces, removes consecutive spaces and trailing space
  echo "injected data: '$(cat $data_nix | tr '\n' ' ' | tr -s ' ' | sed 's/ $//')'"
fi

# Print the real paths of the symlinks
for symlink in "$output_path"/*; do
  real_path=$(readlink -f "$symlink")
  if [ "$verbose" = true ]; then 
    echo created symlink: \'"$symlink > $real_path"\'
  else
    echo "$real_path"
  fi
done
