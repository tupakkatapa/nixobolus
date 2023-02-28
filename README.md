# Nixobolus
Automated creation of bootable NixOS images

## Work in Progress
This repository is a work in progress and is subject to change at any time. Please note that the code and documentation may be incomplete, inaccurate, or contain bugs. Use at your own risk.

## Dependencies
To use this tool, you'll need to install the following dependencies:

- Nix package manager https://zero-to-nix.com/start/install

- Jinja2 and jq

## Usage 
To configure your bootable images, simply edit the example.yml file or create your own to define the settings for your deployment. Each machine is represented as a list item with key-value pairs for various settings.

Settings declared in the "general" section apply to all hosts and will be overwritten by the values in host section if they are the same. Any settings not explicitly defined in the configuration file section will default to the values specified in the corresponding Jinja2 templates, which can be found under the templates_nix folder.

To generate your images, run the `build.sh` script with the path to your configuration file as the argument. This will render the Nix configuration files from the Jinja2 templates and build the initrd and kernel for each configured machine using the `nix-build` command. The resulting images will be generated in the path provided with `-o/--output` flag, defaulting to the result folder.

For example: `./build.sh ./configs/example.yml --output /tmp`

Once you have generated your images, you can use the [kexec](https://wiki.archlinux.org/title/Kexec) script to boot the desired image.

## TODO
- [x] Home-manager
- [x] Secret management using SOPS
- [ ] Flakes
- [ ] Support for adding multiple users
- [ ] Option to build images in Docker/Podman
- [x] Divide Ethereum template into smaller parts
- [ ] Proof of concept WebUI

## Roadmap
- [ ] Stage 1
    - Work on EL and CL client configurations
    - Streamlined installation and configuration process for Nix package manager
    - Documentation of tried and tested configs for initial users comparison and feedback

- [ ] Stage 2
    - Work on validator client configurations
    - Support for ARM hardware (in addition to x86)
    - Documentation for different options for secure key storage
    - Mimic and test realistic UX for a new home-staker

- [ ] Stage 3
    - Further improvements
    - Fine-tuning of documentation and overall UX
    - WebUI

- [ ] Stage 4
    - Complete documentation stating any constraints

## Links
Here are some resources that i found helpful when learning to put this thing together

### NixOS
- https://zero-to-nix.com/
- https://youtu.be/AGVXJ-TIv3Y

### Ethereum
- https://ethereum.org/en/learn/
- https://docs.prylabs.network/docs/concepts/nodes-networks

### SOPS
- https://github.com/mozilla/sops
- https://poweruser.blog/how-to-encrypt-secrets-in-config-files-1dbb794f7352
