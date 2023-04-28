{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";

  # User Options
  user = {
    authorizedKeys = [
      # ssh-ed25519 ...
    ];
  };

  # SSH options
  ssh = {
    enable = true;
    privateKeyPath = "/var/mnt/secrets/ssh/id_ed25519"; # automatically generated
  };

  # Localization
  networking.hostName = "ponkila-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";
  console.keyMap = "fi";

  # Erigon options
  erigon = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/erigon";
  };

  # Lighthouse options
  lighthouse = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/lighthouse";
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    slasher = {
      enable = false;
      history-length = 256;
      max-db-size = 16;
    };
  };
in
{
  # Secrets
  home-manager.users.staker = { pkgs, ... }: {
    sops = {
      defaultSopsFile = ./secrets/default.yaml;
      secrets."wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      age.sshKeyPaths = [ ssh.privateKeyPath ];
    };
  };

  systemd.mounts = [
    # Secrets
    {
      enable = true;

      description = "secrets storage";

      what = "/dev/disk/by-label/secrets";
      where = "/var/mnt/secrets";
      type = "btrfs";

      before = [ "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
    # Erigon
    {
      enable = true;

      description = "erigon storage";

      what = "/dev/disk/by-label/erigon";
      where = erigon.datadir;
      options = lib.mkDefault "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
    # Lighthouse
    {
      enable = true;

      description = "lighthouse storage";

      what = "/dev/disk/by-label/lighthouse";
      where = lighthouse.datadir;
      options = lib.mkDefault "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
  ];

  system.stateVersion = "23.05";
}
