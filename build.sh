#!/usr/bin/env bash
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

# Define variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
NIXPKGS_REPO="https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-unstable.zip"
HM_REPO="https://github.com/nix-community/home-manager/archive/master.tar.gz"
config_dir="$SCRIPT_DIR/configs/nix_configs/hosts"
output_dir="$SCRIPT_DIR/result"
#container=false
verbose=false
keep_configs=false
prompt=false

# Help message
help() {
    echo "Usage: ./build.sh [-p] [-k] [-o output_dir] [-v] [--nix-shell] [config_file]"
    echo ""
    echo "Options:"
    echo "  -p, --prompt          Prompt before performing crucial actions (e.g. overwriting or deleting files)"
    echo "  -k, --keep-configs    Keep nix configurations in './configs/nix_configs/<hostname>' after build"
    echo "  -o, --output          Specify output directory (default: './result')"
    echo "  -v, --verbose         Enable verbose mode"
    echo ""
    echo "If config_file is not specified, the script will read from standard input."
    echo "Config files should be in YAML or JSON format and be formatted correctly."
    keep_configs=true
    exit 0
}

# Handles messages and prompts
say() {
    local message="$1"

    # [-] Check for error message
    if [[ "$message" =~ \[\-\] ]]; then
        echo -e "$message" >&2
        exit 1

    # [?] Prompt for user input
    elif [[ "$message" =~ \[\?\] ]]; then
        if [ "$prompt" == true ]; then
            echo ""
            read -r -p "$message" choice
        else
            choice="y"
        fi
        if [ "$choice" != "y" ]; then
            return 1
        else
            return 0
        fi

    # [+] Print message if verbose mode is on
    elif [ "$verbose" == true ]; then
        echo -e "$message"
    fi
}

# Check main dependencies (nix, python, jinja2)
check_deps() {
    # Check if nix-build is available
    if ! command -v nix-build >/dev/null 2>&1; then
        say "[-] Nix package manager is not installed."
    fi

    # Check if python is installed
    if command -v python3 >/dev/null 2>&1 ; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1 ; then
        python_cmd="python"
    else
        say "[-] Python is not installed. Enter 'nix develop' to quickly set up necessary dependencies."
    fi

    # Check that python can import jinja2
    if ! $python_cmd -c "import jinja2" >/dev/null 2>&1; then
        say "[-] Jinja2 is not installed. Enter 'nix develop' to quickly set up necessary dependencies."
    fi
}

# Parse the command line options
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--prompt) prompt=true ;;
            -k|--keep-configs) keep_configs=true ;;
            -o|--output) output_dir="$2"; shift ;;
            -h|--help) help ;;
            #--docker) container=true; engine="docker" ;;
            #--podman) container=true; engine="podman" ;;
            -v|--verbose) verbose=true ;;
            -*) # Allows combining flags
                for ((i=2; i<=${#1}; i++)); do
                    case ${1:i-1:1} in
                        p) prompt=true ;;
                        k) keep_configs=true ;;
                        o) output_dir="$2"; shift ;;
                        v) verbose=true ;;
                        *) say "[-] Unrecognized option '-${1:i-1:1}'" >&2; exit 1 ;;
                    esac
                done
                ;;
            *.yml|*.yaml|*.json)
                config_file="$1"
                ;;
            *) say "[-] Unrecognized option '$1'"
            ;;
        esac
        shift
    done
}

# Get filetype (yaml or json)
get_filetype() {
    local file=$1
    local basename="${file##*/}"
    local firstline
    filetype="${basename##*.}"

    # Try to detect the filetype by first line
    if ! [[ "$filetype" =~ ^(yaml|yml|json)$ ]]; then
        firstline=$(head -n1 "$file")
        # Check for YAML
        if [[ "$firstline" == "---"* ]]; then
            filetype="yaml"
        # Check for JSON
        elif [[ "$firstline" == "{"* ]]; then
            filetype="json"
        else
            say "[-] Unable to detect the data format as YAML or JSON."
        fi
    fi
}

# Get info from config file (hostnames, system architecture)
get_values_from_config() {
    local config_file=$1
    local filetype=$2

    case "$filetype" in
        yaml|yml)
            # Check if yq is installed
            if ! command -v yq >/dev/null 2>&1; then
                say "[-] yq is not installed. Enter 'nix develop' to quickly set up necessary dependencies."
            fi
            # Extract the hostnames
            hostnames=$(yq -r '.hosts[].name' "$config_file")
            # Extract the system architecture
            #system=$(yq -r '.hosts[].system' "$config_file")
            ;;
        json)
            # Check if jq is installed
            if ! command -v jq >/dev/null 2>&1; then
                say "[-] jq is not installed. Enter 'nix develop' to quickly set up necessary dependencies."
            fi
            # Extract the hostnames
            hostnames=$(jq -r '.hosts[].name' "$config_file")
            # Extract the system architecture
            #system=$(jq -r '.hosts[].system' "$config_file")
            ;;
        *)
            say "[-] Invalid data format. Only YAML and JSON are supported."
            ;;
    esac

    # Check if hosts are empty
    if [ -z "$hostnames" ]; then
        say "[-] No hosts found in $config_file"
    fi
}

# Check if previous config files exist
check_prev_config() {
    local dir=$1
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        if ! say "[?] Delete previous config files and render again? (y/n)"; then
            say "[+] Exiting..."
            keep_configs=true
            exit 0
        fi
        rm -rf "${dir:?}"/*
    fi
}

# Check if config file is encrypted with sops
check_sops () {
    local file=$1
    local filetype=$2

    # get_hostnames() checks that yq or jq is installed
    # get_filetype() checks that $filetype is yaml, yml or json

    if [[ "$filetype" =~ ^(yaml|yml)$ ]]; then
        # Check if the YAML file is encrypted with SOPS
        if yq -e 'has("sops")' "$file" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    elif [[ "$filetype" == json ]]; then
        # Check if the JSON file is encrypted with SOPS
        if jq -e '.sops | length > 0' "$file" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        say "[-] Invalid data format while checking for encryption."
    fi
}

# Decrypt file encrypted with SOPS
sops_decrypt() {
    local file=$1
    local filetype=$2

    # Check if sops is installed
    if ! command -v sops &> /dev/null; then
        say "[-] Decryption failed, SOPS not installed. Enter 'nix develop' to quickly set up necessary dependencies."
    fi

    # Create a temporary file for the decrypted output
    decrypted_temp_file=$(mktemp)

    # Decrypt file and write output to temporary file
    if ! sops --input-type "$filetype" --output-type "$filetype" -d "$file" > "$decrypted_temp_file"; then
        say "[-] Decryption failed."
    else
        say "[+] Decryption successful."
        config_file="$decrypted_temp_file"
    fi
}

# Build images using nix-build command
build_images() {
    local total_hosts
    total_hosts=$(echo "$hostnames" | wc -w)

    # Start the timer
    SECONDS=0

    # Initialize host building counter
    counter=0

    # Loop through the hosts and build the images
    for host in $hostnames; do
        
        # Print host name
        (( counter++ ))
        say "\n[+] Building images for $host [$counter/$total_hosts]"
        
        # Init build command
        nix_build_cmd="nix build .#$host -o $output_dir/$host --show-trace"
        
        # Add docker/podman prefix if enabled
        #if $container; then
        #    if ! command -v "$engine" >/dev/null 2>&1; then
        #        say "[-] ${engine^} is not installed."
        #    fi
        #    nix_build_cmd="$engine run --rm -it -v \"$PWD:$PWD\":z -w \"$PWD\" \$($engine build -q \"$SCRIPT_DIR\") $nix_build_cmd"
        #fi

        # Build images
        if $verbose; then
            say "[+] CMD: \"$nix_build_cmd\""
            eval "$nix_build_cmd"
        else
            eval "$nix_build_cmd" >/dev/null 2>&1
        fi

        # Check if building images for $host was successful
        if [ $? -ne 0 ]; then
            say "[-] Build failed for $host"
            if ! say "[?] Continue? (y/n)"; then
                rm -rf "${output_dir:?}"/"$host"
                say "[+] Exiting..."
                exit 0
            fi
        else
            say "[+] Succesfully built images for $host"
            
            # Print the symlink target paths to the array
            mapfile -t symlink_paths < <(readlink -f "$output_dir"/"$host"/* | sort -u)
            
            if "$verbose"; then
                say "\n[+] $host - result"
            else
                echo "=== $host ==="
            fi

            for path in "${symlink_paths[@]}"; do
                if "$verbose"; then
                    if [[ "${path}" == "${symlink_paths[-1]}" ]]; then
                        say " └── ${path}"
                    else
                        say " ├── ${path}"
                    fi
                else
                    echo "${path}"
                fi
            done
        fi
    done

    # End the timer
    secs=$SECONDS

    # Print the message with the time in the desired format
    hrs=$(printf "%02d" $((secs/3600)))
    mins=$(printf "%02d" $(((secs/60)%60)))
    secs=$(printf "%02d" $((secs%60)))
    say "\n[+] Build(s) completed in: $hrs:$mins:$secs"
}

# Clean up
cleanup() {
    # Remove mktemp files
    temp_files=("$temp_file" "$decrypted_file")
    for file in "${temp_files[@]}"; do
        if [ -e "$file" ]; then
            rm -f "$file"
        fi
    done

    # Remove configuration files
    if [ -d "$config_dir" ] && [ "$(ls -A "$config_dir")" ] && [ "$keep_configs" == false ]; then
        if ! say "[?] Delete rendered config files? (y/n)"; then
            say "[+] Exiting..."
            exit 0
        fi
        rm -rf "${config_dir:?}"/*
    fi
}

main() {
    # set signal handlers to call cleanup function on exit or SIGINT
    trap cleanup EXIT
    trap cleanup SIGINT

    # Parse the command line options
    parse_args "$@"

    # Check main dependencies (nix, python, jinja2)
    check_deps

    # Check if stdin was piped
    if [[ ! -t 0 ]]; then

        # Read from stdin and store it in the temporary file
        temp_file="$(mktemp)"
        cat > "$temp_file"
        config_file="$temp_file"
  
        if [[ ${prompt} == true ]]; then
            say "[-] Prompt needs to be disabled when data is piped to the script."
        fi
    fi
    
    # Check if config_file is set and exists
    if [[ -z "$config_file" && ! -e "$config_file" ]]; then
        say "[-] No given configuration data found."
    fi

    # Get filetype (yaml or json)
    get_filetype "$config_file"

    # Get needed values from config file (hostnames, system architecture)
    get_values_from_config "$config_file" "$filetype"

    # Create required directories if they don't exist
    directories=( "$config_dir" )
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    # Check if previous config files exist
    check_prev_config "$config_dir"

    # Decrypt if file is encrypted with SOPS
    if check_sops "$config_file" "$filetype"; then
        sops_decrypt "$config_file" "$filetype"
    fi

    # Render the Nix config files using the python script
    if ! $python_cmd "$SCRIPT_DIR/scripts/render_configs.py" "$config_file"; then
        say "[-] Rendering failed."
    fi

    # Print the config paths
    for host in $hostnames; do
        mapfile -t subdir_files < <(find "$config_dir"/"$host" -type f -printf '%P\n')
        say "\n[+] $host - config"
        for path in "${subdir_files[@]}"; do
            if [[ "${path}" == "${subdir_files[-1]}" ]]; then
                say " └── ${path}"
            else
                say " ├── ${path}"
            fi
        done
    done

    # Check if previous build files exists
    build_images
}

main "$@"