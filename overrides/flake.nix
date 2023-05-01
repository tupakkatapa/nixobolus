# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{
  description = "Nixobolus flake";

  inputs = { };

  outputs = { self, ... }@inputs: {
    nixosModules.data = import ./data.nix;
  };

}
