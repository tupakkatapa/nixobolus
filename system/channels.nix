# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{ pkgs, lib, ... }:
let
  # List of Nix channels to add
  channels = [
    {
      name = "nixos-unstable";
      url = "https://nixos.org/channels/nixos-unstable";
    }
  ];
in
{
  systemd.services = {
    # Add Nix channels on boot
    add-nix-channels = {
      enable = true;
      description = "Add Nix channels on boot";

      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.concatStringsSep " " (map (c: "${pkgs.nix}/bin/nix-channel --add ${c.url} ${c.name}") channels)}";
        ExecStartPost = "${pkgs.nix}/bin/nix-channel --update";
      };
    };
  };
}