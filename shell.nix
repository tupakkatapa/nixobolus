# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

### Usage
# nix-build only: './build.sh ./configs/example.yml --nix-shell'
# whole build.sh: 'nix-shell --run "./build.sh ./configs/example.yml"'

{ pkgs ? import <nixpkgs> {} }:

with pkgs; mkShell {
  name = "nixobolus";
  buildInputs = [ jq yq sops nix j2cli ];
}
