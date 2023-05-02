{ pkgs, config, inputs, lib, ... }:
let
  infra.ip = "192.168.100.10";
  erigon.datadir = "/var/mnt/erigon";
  lighthouse.datadir = "/var/mnt/lighthouse";
in
{
  user = {
    authorizedKeys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
    ];
  };

  ssh = {
    privateKeyPath = "/var/mnt/secrets/ssh/id_ed25519";
  };

  localization = {
    hostname = "ponkila-ephemeral-beta";
    timezone = "Europe/Helsinki";
    keymap = "fi";
  };

  erigon = {
    endpoint = "192.168.100.10";
    datadir = "/var/mnt/erigon";
    #endpoint = infra.ip;
    #datadir = erigon.datadir;
  };

  lighthouse = {
    endpoint = infra.ip;
    datadir = lighthouse.datadir;
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    slasher = {
      enable = false;
      history-length = 256;
      max-db-size = 16;
    };
  };

  mev-boost = {
    enable = true;
  };

  mounts = [
    {
      what = "/dev/sda1";
      where = "/mnt/mydisk";
      type = "ext4";
      options = "defaults";
    }
    {
      what = "/dev/disk/by-label/mydisk";
      where = "/mnt/mydisk";
      type = "btrfs";
      options = "defaults";
    }
  ];
}
