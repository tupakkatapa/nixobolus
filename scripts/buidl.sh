#!/usr/bin/env bash
# Script for building a host with injected json data

set -o pipefail
trap cleanup EXIT
trap 'cleanup && exit 0' SIGINT

# Default argument values
verbose=false
output_path="./result"
flake_url="github:ponkila/nixobolus"

# Do not change, this path is also hard-coded in flake.nix
data_nix="/tmp/data.nix"

# Cleanup which will be executed at exit
cleanup() {
  [[ -f "$data_nix" ]] && rm "$data_nix"
}

display_usage() {
  cat <<USAGE
Usage: $0 [options] [json_data]

Arguments:
  json_data
      Specify raw JSON data to inject into the base configuration. It can be provided as a positional argument or piped into the script.

Options:
  -b, --base <hostname>
      Set the base configuration with the specified hostname. Available configurations: 'homestakeros'.

  -f, --flake <url>
      Set the URL of the nixobolus flake. Default: 'github:ponkila/nixobolus'.

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

parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -b|--base)
        hostname="$2"
        shift 2 ;;
      -f|--flake)
        flake_url="$2"
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
  # Check that base configuration has been set
  if [[ -z $hostname ]]; then
    echo "error: base configuration is required."
    echo "try '--help' for more information."
    exit 1
  fi
}

create_data_nix() {
  local json_data="$1"
  local data_nix="$2"

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
}

run_nix_build() {
  local hostname="$1"
  local output_path="$2"
  local verbose="$3"
  local flake_url="$4"

  # Default flags for the 'nix build' command
  declare -a nix_flags=(
    --accept-flake-config
    --extra-experimental-features 'nix-command flakes'
    --impure
    --no-warn-dirty
    --out-link "$output_path"
  )

  # Append '--show-trace' and '--debug' if verbose flag is true
  [[ "$verbose" = true ]] && nix_flags+=("--show-trace" "--debug")
  
  # Execute the 'nix build' command
  nix build "$flake_url"#"$hostname" "${nix_flags[@]}" || exit 1
}

print_output() {
  local output_path="$1"
  local data_nix="$2"
  local verbose="$3"

  # Display injected data if verbose is true
  if [ "$verbose" = true ] && [ -f "$data_nix" ]; then
    # Replaces newlines with spaces, removes consecutive spaces and trailing space
    echo "injected data: '$(< "$data_nix" tr '\n' ' ' | tr -s ' ' | sed 's/ $//')'"
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
}

main() {
  # Parse and validate command line arguments
  parse_arguments "$@"

  # Read JSON data from stdin if it exists and is not provided as an argument
  if [ -z "$json_data" ] && ! tty -s && [ -p /dev/stdin ]; then
    json_data=$(</dev/stdin)
  fi

  # If JSON data is provided, create 'data.nix' from it
  # This file will be automatically imported by the flake if it exists
  [[ -n $json_data ]] && create_data_nix "$json_data" "$data_nix"

  # Run the 'nix build' command and fallback to fetching from GitHub if the flake is not found
  run_nix_build "$hostname" "$output_path" $verbose "$flake_url"

  # Display additional output, including injected data and created symlinks
  print_output "$output_path" "$data_nix" $verbose
}

main "$@"
