# Nixobolus
Automated creation of bootable NixOS images

## Work in Progress
This repository is a work in progress and is subject to change at any time. Please note that the code and documentation may be incomplete, inaccurate, or contain bugs. Use at your own risk.

## Dependencies
To use this tool, you must have [Nix package manager](https://nixos.org/download.html) installed. Optionally, you may also install [direnv](https://github.com/direnv/direnv#basic-installation) which will automatically run `nix develop` whenever you enter the directory.

## Usage

1. Configure

    Simply edit the example.yml file or create your own to define the settings for your deployment. Each machine is represented as a list item with key-value pairs for various settings.

    Settings declared in the "general" section apply to all hosts and will be overwritten by the values in host section if they are the same. Any settings not explicitly defined in the configuration file section will default to the values specified in the corresponding Jinja2 templates, which can be found under the templates folder.

2. Generate

    To get started, enter the build environment by running `nix develop`. Once inside the environment, use the `build.sh` script with the path to your configuration file as an argument. This will generate the Nix configuration files from the Jinja2 templates and build the initrd, kernel, and netboot.ipxe for each configured machine.

    ```
    $ ./build.sh --help
    Usage: ./build.sh [-p] [-k] [-o output_dir] [-v] [--nix-shell] [config_file]

    Options:
    -p, --prompt          Prompt before performing crucial actions (e.g. overwriting or deleting files)
    -k, --keep-configs    Keep nix configurations in './configs/nix_configs/<hostname>' after build
    -o, --output          Specify output directory (default: './result')
    -v, --verbose         Enable verbose mode

    If config_file is not specified, the script will read from standard input.
    Config files should be in YAML or JSON format and be formatted correctly.
    ```

3. Deploy
    
    Once you have generated your images, you can use [kexec](https://wiki.archlinux.org/title/Kexec) or [iPXE](https://ipxe.org/start) to boot the desired image.

## TODO

- [x] Home-manager
- [x] Secret management using SOPS
- [x] Flakes
- [ ] Support for adding multiple users
- [ ] Option to build images in Docker/Podman
- [x] Divide Ethereum template into smaller parts
- [x] Proof of concept [WebUI](https://github.com/ponkila/HomestakerOS)

## Links

Here are some resources that i found helpful when learning to put this thing together

- NixOS
    - https://zero-to-nix.com/
    - https://youtu.be/AGVXJ-TIv3Y

- Ethereum
    - https://ethereum.org/en/learn/
    - https://docs.prylabs.network/docs/concepts/nodes-networks

- SOPS
    - https://github.com/mozilla/sops
    - https://poweruser.blog/how-to-encrypt-secrets-in-config-files-1dbb794f7352