{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10"; # FIXME
in
{
  imports = [
    ../../modules/eth
    ../../system/ramdisk.nix
    ../../system/global.nix
    ../../system/channels.nix
    ../../home-manager/core.nix
  ];

  # User options
  user = {
    authorizedKeys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
    ];
  };
  
  # Localization
  networking.hostName = "homestaker";
  time.timeZone = "Europe/Helsinki";

  # Erigon options
  erigon = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/erigon";
    mount = {
      source = "/dev/disk/by-label/erigon"; # FIXME
      target = datadir;
    };
  };

  # Lighthouse options
  lighthouse = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/lighthouse";
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    slasher = {
      enable = false;
      history-lenght = 256;
      max-db-size = 16;
    };
    mount = {
      source = "/dev/disk/by-label/lighthouse"; # FIXME
      target = datadir;
    };
  };

  # Secrets
  home-manager.users.core = { pkgs, ... }: {
    sops = {
      defaultSopsFile = ./secrets/default.yaml;
      secrets."wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      age.sshKeyPaths = [ "/var/mnt/secrets/ssh/id_ed25519" ];
    };
  };

  systemd.mounts = [
    {
      enable = true;

      description = "secrets storage";

      what = "/dev/disk/by-label/secrets"; # FIXME
      where = "/var/mnt/secrets";
      type = "btrfs";

      before = [ "sops-nix.service" "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];

  system.stateVersion = "23.05";
}