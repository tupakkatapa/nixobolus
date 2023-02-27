#!/bin/bash
# Nixobolus - Automated creation of bootable images
# https://github.com/ponkila/Nixobolus

# Get the current path of the script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Set default values for arguments
prompt=true

# Check if previous configuration files exists
dir="$SCRIPT_DIR/configs/nix_configs/hosts"
if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous config files? (y/n)" choice
    else
        choice="y"
    fi
    if [ "$choice" == "y" ]; then
        rm -rf $dir/*
    fi
    
fi

# Check if previous build files exists
dir="$SCRIPT_DIR/images_netboot"
if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    if [ "$prompt" == true ]; then
        read -p "[?] Delete previous netboot images? (y/n)" choice
    else
        choice="y"
    fi
    if [ "$choice" == "y" ]; then
        rm -rf $dir/*
    fi
    
fi

# Remove unneeded items from the Nix store
if [ "$prompt" == true ]; then
    read -p "[?] Run nix-collect-garbage? (y/n)" choice
else
    choice="y"
fi
if [ "$choice" == "y" ]; then
    nix-collect-garbage -d
fi