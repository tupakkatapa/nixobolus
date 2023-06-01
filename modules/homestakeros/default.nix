{ config, lib, pkgs, ... }:
let
  cfg = config.homestakeros;
in
{
  # usage: https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b

  config = with nixpkgs.lib; mkMerge [
    ################################################################### LOCALIZATION
    (mkIf true {
      networking.hostName = cfg.localization.hostname;
      time.timeZone = cfg.localization.timezone;
    })

    #################################################################### MOUNTS
    (mkIf true {
      systemd.mounts = builtins.listToAttrs (map
        (mount: {
          enable = mount.enable or true;
          description = mount.description or "Unnamed mount point";
          what = mount.what;
          where = mount.where;
          type = mount.type or "ext4";
          options = mount.options or "defaults";
          before = lib.mkDefault mount.before;
          wantedBy = mount.wantedBy or [ "multi-user.target" ];
        })
        cfg.mounts);
    })

    #################################################################### SSH (system level)
    (mkIf true {
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        hostKeys = [{
          path = cfg.ssh.privateKeyPath;
          type = "ed25519";
        }];
      };
    })

    #################################################################### USER (core)
    (mkIf true {
      services.getty.autologinUser = "core";
      users.users.core = {
        isNormalUser = true;
        group = "core";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = cfg.user.authorizedKeys;
        shell = pkgs.fish;
      };
      users.groups.core = { };
      environment.shells = [ pkgs.fish ];
      programs.fish.enable = true;

      home-manager.users.root.home.stateVersion = config.home-manager.users.core.home.stateVersion;
      home-manager.users.core = { pkgs, ... }: {

        home.packages = with pkgs; [
          file
          tree
          bind # nslookup
        ];

        programs = {
          tmux.enable = true;
          htop.enable = true;
          vim.enable = true;
          git.enable = true;
          fish.enable = true;
          fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

          home-manager.enable = true;
        };

        home.stateVersion = "23.05";
      };
    })

    #################################################################### WIREGUARD (no options)
    (mkIf true {
      home-manager.users.core = { pkgs, ... }: {
        sops = {
          defaultSopsFile = ./secrets/default.yaml;
          secrets."wireguard/wg0" = {
            path = "%r/wireguard/wg0.conf";
          };
          age.sshKeyPaths = [ "/var/mnt/secrets/ssh/id_ed25519" ]; # cfg.ssh.privateKeyPath opt here
        };
      };
      systemd.services.wg0 = {
        enable = true;

        description = "wireguard interface for cross-node communication";
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
        };

        script = ''${nixpkgs.wireguard-tools}/bin/wg-quick \
                    up /run/user/1000/wireguard/wg0.conf
                  '';

        wantedBy = [ "multi-user.target" ];
      };
    })

    #################################################################### ERIGON
    (mkIf (cfg.erigon.enable) {
      # package
      environment.systemPackages = [
        pkgs.erigon
      ];

      # service
      systemd.user.services.erigon = {
        enable = true;

        description = "execution, mainnet";
        requires = [ "wg0.service" ];
        after = [ "wg0.service" "lighthouse.service" ];

        serviceConfig = {
          Restart = "always";
          RestartSec = "5s";
          Type = "simple";
        };

        script = ''${pkgs.erigon}/bin/erigon \
                    --datadir=${cfg.erigon.datadir} \
                    --chain mainnet \
                    --authrpc.vhosts="*" \
                    --authrpc.addr ${cfg.erigon.endpoint} \
                    --authrpc.jwtsecret=${cfg.erigon.datadir}/jwt.hex \
                    --metrics \
                    --externalcl
                  '';

        wantedBy = [ "multi-user.target" ];
      };

      # firewall
      networking.firewall = {
        allowedTCPPorts = [ 30303 30304 42069 ];
        allowedUDPPorts = [ 30303 30304 42069 ];
      };
    })

    #################################################################### MEV-BOOST
    (mkIf (cfg.mev-boost.enable) {
      # service
      systemd.user.services.mev-boost = {
        enable = true;

        description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
        requires = [ "wg0.service" ];
        after = [ "wg0.service" ];

        serviceConfig = {
          Restart = "always";
          RestartSec = "5s";
          Type = "simple";
        };

        script = ''${pkgs.mev-boost}/bin/mev-boost \
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
    })

    #################################################################### LIGHTHOUSE
    (mkIf (cfg.lighthouse.enable) {
      # package
      environment.systemPackages = with pkgs; [
        lighthouse
      ];

      # service
      systemd.user.services.lighthouse = {
        enable = true;

        description = "beacon, mainnet";
        requires = [ "wg0.service" ];
        after = [ "wg0.service" "mev-boost.service" ];

        serviceConfig = {
          Restart = "always";
          RestartSec = "5s";
          Type = "simple";
        };

        script = ''${pkgs.lighthouse}/bin/lighthouse bn \
                    --datadir ${cfg.lighthouse.datadir} \
                    --network mainnet \
                    --http --http-address ${cfg.lighthouse.endpoint} \
                    --http-allow-origin "*" \
                    --execution-endpoint ${cfg.lighthouse.exec.endpoint} \
                    --execution-jwt ${cfg.lighthouse.datadir}/jwt.hex \
                    --builder ${cfg.lighthouse.mev-boost.endpoint} \
                    --prune-payloads false \
                    --metrics \
                    ${if cfg.lighthouse.slasher.enable then
                      "--slasher "
                      + " --slasher-history-length " + (toString cfg.lighthouse.slasher.history-length)
                      + " --slasher-max-db-size " + (toString cfg.lighthouse.slasher.max-db-size)
                    else "" }
                  '';
        wantedBy = [ "multi-user.target" ];
      };

      # firewall
      networking.firewall = {
        allowedTCPPorts = [ 9000 ];
        allowedUDPPorts = [ 9000 ];
        interfaces."wg0".allowedTCPPorts = [
          5052 # lighthouse
        ];
      };
    })
  ];
}
