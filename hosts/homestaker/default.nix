{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.1.420"; # FIXME
in
{
  imports = [
    ../../modules/eth
    ../../system
    ../../system/channels.nix
    ../../home-manager/core.nix
  ];

  # User options
  user = {
    authorizedKeys = [
      # "ssh-ed25519 ... 
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
      source = "/dev/disk/by-label/erigon"; #FIXME
      target = datadir;
      type = "btrfs";
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
      history-length = 256;
      max-db-size = 16;
    };
    mount = {
      source = "/dev/disk/by-label/lighthouse"; # FIXME
      target = datadir;
      type = "btrfs";
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

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    hostKeys = [{
      path = "/var/mnt/secrets/ssh/id_ed25519";
      type = "ed25519";
    }];
  };

  system.stateVersion = "23.05";
}
