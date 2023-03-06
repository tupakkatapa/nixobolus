# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

# Usage:
# nix-shell

{ pkgs ? import <nixpkgs> {} }:

with pkgs; mkShell {
  name = "nixobolus";
  buildInputs = [ jq yq sops nix j2cli ];
}
