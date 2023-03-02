#!/bin/bash
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

# Define variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
output="$SCRIPT_DIR/result"
input_file=""
filename=""
filetype=""
hosts=""
sops=false

# Check main dependencies (nix, python, jinja2)
check_deps() {
# Check if nix-build is available
if ! command -v nix-build >/dev/null 2>&1; then
        echo "[-] Nix package manager is not installed."
    exit 1
fi

# Check if python is installed
if command -v python3 >/dev/null 2>&1 ; then
    python_cmd="python3"
elif command -v python >/dev/null 2>&1 ; then
    python_cmd="python"
else
        echo "[-] Python is not installed."
    exit 1
fi

# Check that python can import jinja2
if ! $python_cmd -c "import jinja2" >/dev/null 2>&1; then
        echo "[-] Jinja2 is not installed."
    exit 1
fi
}


# Parse the command line options
parse_args() {
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --no-prompt) prompt=false;;
        -o|--output) output="$2"; shift ;;
        *.yml|*.yaml|*.json)
                input_file="$1"
            ;;
        *) echo "[-] Unknown parameter passed: $1" >&2
           exit 1 ;;
    esac
    shift
done

# Extract hostnames and check if decrypted w/ SOPS
extract_hosts() {

    filetype="${filename##*.}"

case "$filetype" in
    yaml|yml)
        # Check if yq is installed
        if ! command -v yq >/dev/null 2>&1; then
            echo "[-] yq is not installed. Exiting.."
            exit 1
        fi
        # Extract the names of the hosts from the YAML file
        hosts=$(yq -r '.hosts[].name' "$input_file")
        # Check if the YAML file is encrypted with SOPS
        if yq eval 'has("sops")' "$input_file" >/dev/null 2>&1; then
            sops=true
        fi
        ;;
    json)

        # Check if jq is installed
        if ! command -v jq >/dev/null 2>&1; then
            echo "[-] jq is not installed. Exiting.."
            exit 1
        fi
        # Extract the host names from the JSON file
        hosts=$(jq -r '.hosts[].name' "$input_file")
        # Check if the JSON file is encrypted with SOPS
        if jq -e '.sops | length > 0' "$input_file" >/dev/null 2>&1; then
            sops=true
        fi
        ;;
    *)
        echo "[-] Invalid file format. Only YAML and JSON files are supported."
        exit 1
        ;;
esac

# Check if hosts are empty
if [ -z "$hosts" ]; then
    echo "[-] No hosts found in input file."
    exit 1
fi
}

# Check if previous configuration files exist
check_prev_config() {
dir="$SCRIPT_DIR/configs/nix_configs/hosts"
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous config files and render again? (y/n)" choice
    else
        choice="y"
    fi
        if [ "$choice" != "y" ]; then
            echo "[+] Exiting..."
            exit 1
fi
        rm -rf "${dir:?}"/*
    fi
}

# Decrypt file encrypted with SOPS
sops_decrypt() {

    input_file=$1

    # Check if sops is installed
    if ! command -v sops &> /dev/null; then
        echo "[-] Decryption failed, SOPS not installed. Exiting..."
        exit 1
    fi

    # Create a temporary file for the decrypted output
    decrypted_file=$(mktemp)

    # Decrypt file and write output to temporary file
    if ! sops --decrypt "$input_file" > "$decrypted_file"; then
        echo "[-] Decryption failed, exiting..."
        rm "$decrypted_file"
        exit 1
    else
        echo "[+] Decryption successful."
        input_file="$decrypted_file"
    fi
}

# Check if previous build files exists
build_images() {
    # Check if output directory exists and prompt user if necessary
dir="$output"
if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous images and rebuild? (y/n)" choice
    else
        choice="y"
    fi
    if [ "$choice" != "y" ]; then
        echo "[+] Exiting..."
        exit 1
    fi
    rm -rf "$dir"/*
else
    if [ "$prompt" == true ]; then
        read -p "[?] Proceed with building? (y/n)" choice
    else
        choice="y"
    fi
    if [ "$choice" != "y" ]; then
        echo "[+] Exiting..."
        exit 1
    fi
fi

# Start the timer
SECONDS=0

# Initialize host building counter
counter=0

# Loop through the hosts and build the images
declare -A symlink_paths
for host in $hosts; do
    
    # Print host name
    let counter++
    echo -e "\n[+] Building images for $host [$counter/$total_hosts]"
    
    # Build images for $host using nix-build command
    time nix-build \
        -A pix.ipxe configs/nix_configs/hosts/"$host"/default.nix \
        -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-unstable.zip \
        -I home-manager=https://github.com/nix-community/home-manager/archive/master.tar.gz \
        -o "$output"/"$host" ;
        #--show-trace ;

    # Check if building images for $host was successful
    if [ $? -ne 0 ]; then
        echo -e "[-] Build failed for $host"
        if [ "$prompt" == true ]; then
            read -p "[?] Continue? (y/n)" choice
        fi
        if [ "$choice" != "y" ]; then
            rm -rf "$output"/"$host"
            echo "[+] Exiting..."
            exit 1
        fi
    else
        echo "[+] Succesfully built images for $host"
        
        # Add the symlink paths to the array
        symlink_paths[$host]=$(readlink -f "$output"/"$host"/* | sort -u)
    fi
done

# Print the symlink paths (fancy)
for host in $(echo "${!symlink_paths[@]}" | tr ' ' '\n' | sort); do
    echo "[+] $host - result"
    # Split the string into an array
    IFS=$'\n' read -rd '' -a paths <<< "${symlink_paths[$host]}"
    for path in "${paths[@]}"; do
        if [[ "${path}" == "${paths[-1]}" ]]; then
            echo " └── ${path}"
        else
            echo " ├── ${path}"
        fi
    done
done

# End the timer
secs=$SECONDS

# Print the message with the time in the desired format
hrs=$(( secs/3600 )); mins=$(( (secs-hrs*3600)/60 )); secs=$(( secs-hrs*3600-mins*60 ))
printf "[+] Build(s) completed in: %02d:%02d:%02d\n" $hrs $mins $secs
}

# Clean up
cleanup() {
if [ "$prompt" == true ]; then
    read -p "[?] Delete rendered config files? (y/n)" choice
else
    choice="y"
fi
if [ "$choice" != "y" ]; then
    echo "[+] Exiting..."
    exit 1
fi
rm -rf "$SCRIPT_DIR"/configs/nix_configs/hosts/*
}

main() {
    # Check main dependencies (nix, python, jinja2)
    check_deps

    # Parse the command line options
    parse_args "$@"


    # Extract hostnames and check if decrypted w/ SOPS
    extract_hosts

    # Get the total count of hosts
    total_hosts=$(echo "$hosts" | wc -w)

    # Create required directories if they don't exist
    directories=( "$output" "$SCRIPT_DIR/configs/nix_configs/hosts" )
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    # Check if previous configuration files exist
    check_prev_config

    # Decrypt file encrypted with SOPS
    if $sops; then
        sops_decrypt "$input_file"
    fi

    # Render the Nix config files using the render.py script
    if ! $python_cmd "$SCRIPT_DIR/configs/render_configs.py" "$input_file"; then
        echo "[-] Exiting..."
        exit 1
    fi

    # Check if previous build files exists
    build_images

    # Clean up
    cleanup
}

main "$@"
