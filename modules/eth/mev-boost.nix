{ pkgs, lib, ... }:
{
  virtualisation.podman.enable = true;
  # dnsname allows containers to use ${name}.dns.podman to reach each other
  # on the same host instead of using hard-coded IPs.
  # NOTE: --net must be the same on the containers, and not eq "host"
  # TODO: extend this with flannel ontop of wireguard for cross-node comms
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  systemd.services.mev-boost = {
    path = [ "/run/wrappers" ];
    enable = true;

    description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
    requires = [ "wg0.service" ];
    after = [ "wg0.service" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    preStart = "${pkgs.podman}/bin/podman stop mev-boost || true";
    script = ''${pkgs.podman}/bin/podman \
      --storage-opt "overlay.mount_program=${pkgs.fuse-overlayfs}/bin/fuse-overlayfs" run \
      --replace --rmi \
      --name mev-boost \
      -p 18550:18550 \
      docker.io/flashbots/mev-boost:latest \
      -mainnet \
      -relay-check \
      -relays ${lib.concatStringsSep "," [
        "https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ad3b71d3499c54ad14d6c21b41a37ae@boost-relay.flashbots.net"
        "https://0xad0a8bb54565c2211cee576363f3a347089d2f07cf72679d16911d740262694cadb62d7fd7483f27afd714ca0f1b9118@bloxroute.ethical.blxrbdn.com"
        "https://0x9000009807ed12c1f08bf4e81c6da3ba8e3fc3d953898ce0102433094e5f22f21102ec057841fcb81978ed1ea0fa8246@builder-relay-mainnet.blocknative.com"
        "https://0xb0b07cd0abef743db4260b0ed50619cf6ad4d82064cb4fbec9d3ec530f7c5e6793d9f286c4e082c0244ffb9f2658fe88@bloxroute.regulated.blxrbdn.com"
        "https://0x8b5d2e73e2a3a55c6c87b8b6eb92e0149a125c852751db1422fa951e42a09b82c142c3ea98d0d9930b056a3bc9896b8f@bloxroute.max-profit.blxrbdn.com"
        "https://0x98650451ba02064f7b000f5768cf0cf4d4e492317d82871bdc87ef841a0743f69f0f1eea11168503240ac35d101c9135@mainnet-relay.securerpc.com"
        "https://0x84e78cb2ad883861c9eeeb7d1b22a8e02332637448f84144e245d20dff1eb97d7abdde96d4e7f80934e5554e11915c56@relayooor.wtf"
      ]} \
      -addr 0.0.0.0:18550
  '';

    wantedBy = [ "multi-user.target" ];
  };
}