#!/bin/bash
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

# Define variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
input_file=""
prompt=true

# Check dependencies
if ! python -c "import jinja2" >/dev/null 2>&1; then
    echo "[-] Jinja2 is not installed. Exiting.."
    exit 1
fi
if ! command -v nix-env >/dev/null 2>&1; then
    echo "[-] Nix package manager is not installed. Exiting.."
    exit 1
fi

# Iterate through the arguments
for arg in "$@"; do
    if [ "$arg" == "--no-prompt" ]; then
        prompt=false
    elif [[ $arg == *.yml || $arg == *.yaml || $arg == *.json ]]; then
        input_file=$arg             # ./configs/config.ext
        basename="${arg##*/}"       # config.ext
        filename="${basename%.*}"   # config
        filetype="${basename##*.}"  # ext

    fi
done

# Check input file and extract hosts
case "$filetype" in
    yaml|yml)
        # Extract the names of the hosts from the YAML file
        hosts=$(grep -oP '^( {2}| {4})- name: \K\w+' $input_file)
        ;;
    json)
        # Extract the host names from the JSON file
        hosts=$(jq -r '.hosts[].name' "$input_file")
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

# Get the total count of hosts
total_hosts=$(echo "$hosts" | wc -w)

# Create required directories if they don't exist
directories=( "$SCRIPT_DIR/images_netboot" "$SCRIPT_DIR/configs/nix_configs/hosts" )
for dir in "${directories[@]}"; do
    mkdir -p "$dir"
done

# Check if previous configuration files exists
dir="$SCRIPT_DIR/configs/nix_configs/hosts"
if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous config files and render again? (y/n)" choice
    else
        choice="y"
    fi
    [ "$choice" != "y" ] && { echo "[-] Exiting..."; exit 1; }
    rm -rf $dir/*
fi

# Check if file is encrypted with sops
if [[ $(grep -E '^(sops:)$' "$input_file") ]]; then
    # Check if sops is installed
    if ! command -v sops &> /dev/null; then
        echo "[-] Decryption failed, SOPS not installed. Exiting..."
        exit 1
    fi

    # Decrypt file and write output to configs/config.decrypted.yml
    if ! sops --decrypt "$input_file" > "configs/$filename.decrypted.$filetype"; then
        echo "[-] Decryption failed, exiting..."
        rm "$input_file"
        exit 1
    else
        echo "[+] Decryption successful."
        input_file="configs/$filename.decrypted.$filetype"
    fi
fi

# Render the Nix config files using the render.py script
if ! python3 "$SCRIPT_DIR/configs/render_configs.py" "$input_file"; then
    echo "[-] Exiting..."
    exit 1
fi

# Clean up the decrypted input file, if exists
[ "$input_file" == "configs/$filename.decrypted.$filetype" ] && rm "$input_file"

# Check if previous build files exists
dir="$SCRIPT_DIR/images_netboot"
if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous netboot images and rebuild? (y/n)" choice
    else
        choice="y"
    fi
    if [ "$choice" != "y" ]; then
        echo "[+] Exiting..."
        exit 1
    fi
    rm -rf $dir/*
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

# Loop through the hosts and build the netboot images
for host in $hosts; do
    
    # Print host name
    let counter++
    echo -e "\n[+] Building netboot image for $host [$counter/$total_hosts]"
    
    # Build netboot image for $host using nix-build command
    time nix-build \
        -A pix.ipxe configs/nix_configs/hosts/$host/default.nix \
        -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-unstable.zip \
        -I home-manager=https://github.com/nix-community/home-manager/archive/master.tar.gz \
        -o images_netboot/$host ;
        #--show-trace ;

    # Check if building netboot image for $host was successful
    if [ $? -ne 0 ]; then
        echo -e "[-] Build failed for $host"
        if [ "$prompt" == true ]; then
            read -p "[?] Continue? (y/n)" choice
        fi
        if [ "$choice" != "y" ]; then
            rm -rf $SCRIPT_DIR/images_netboot/$host
            echo "[+] Exiting..."
            exit 1
        fi
    else
        echo "[+] Succesfully built image for $host"
    fi
done

# End the timer
secs=$SECONDS

# Print the message with the time in the desired format
hrs=$(( secs/3600 )); mins=$(( (secs-hrs*3600)/60 )); secs=$(( secs-hrs*3600-mins*60 ))
printf "[+] Build(s) completed in: %02d:%02d:%02d\n" $hrs $mins $secs

# Clean up
if [ "$prompt" == true ]; then
    read -p "[?] Delete rendered config files? (y/n)" choice
else
    choice="y"
fi
if [ "$choice" != "y" ]; then
    echo "[+] Exiting..."
    exit 1
fi
rm -rf $SCRIPT_DIR/configs/nix_configs/hosts/*