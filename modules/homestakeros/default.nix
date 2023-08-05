{ config, lib, pkgs, inputs, outputs, ... }:
let
  cfg = config.homestakeros;
in
{
  inherit (import ./options.nix { inherit lib pkgs; }) options;

  config = with lib;
    let
      # Function to parse a URL into its components
      parseEndpoint = endpoint:
        let
          regex = "(https?://)?([^:/]+):([0-9]+)(/.*)?$";
          match = builtins.match regex endpoint;
        in
        {
          addr = builtins.elemAt match 1;
          port = builtins.elemAt match 2;
        };

      # Function to get the active client
      getActiveClients = clients: path: builtins.filter (clientName: path.${clientName}.enable) clients;

      activeConsensusClients = getActiveClients (builtins.attrNames cfg.consensus) cfg.consensus;
      activeExecutionClients = getActiveClients (builtins.attrNames cfg.execution) cfg.execution;
      activeVPNClients = getActiveClients (builtins.attrNames cfg.vpn) cfg.vpn;
    in
    mkMerge [
      ################################################################### LOCALIZATION
      (
        mkIf true {
          networking.hostName = cfg.localization.hostname;
          time.timeZone = cfg.localization.timezone;
        }
      )

      #################################################################### MOUNTS
      # cfg: https://www.freedesktop.org/software/systemd/man/systemd.mount.html#Options
      (
        mkIf true {
          systemd.mounts = lib.mapAttrsToList
            (name: mount: {
              enable = mount.enable or true;
              description = mount.description or "${name} mount point";
              what = mount.what;
              where = mount.where;
              type = mount.type or "ext4";
              options = mount.options or "defaults";
              before = lib.mkDefault (mount.before or [ ]);
              wantedBy = mount.wantedBy or [ "multi-user.target" ];
            })
            cfg.mounts;
        }
      )

      #################################################################### SSH (system level)
      (
        mkIf true {
          services.openssh = {
            enable = true;
            hostKeys = lib.mkIf (cfg.ssh.privateKeyFile != null) [{
              path = cfg.ssh.privateKeyFile;
              type = "ed25519";
            }];
            allowSFTP = false;
            extraConfig = ''
              AllowTcpForwarding yes
              X11Forwarding no
              #AllowAgentForwarding no
              AllowStreamLocalForwarding no
              AuthenticationMethods publickey
            '';
            settings.PasswordAuthentication = false;
            settings.KbdInteractiveAuthentication = false;
          };
        }
      )

      #################################################################### USER (core)
      (
        mkIf true {
          users.users.core = {
            isNormalUser = true;
            group = "core";
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = cfg.ssh.authorizedKeys;
            shell = pkgs.fish;
          };
          users.groups.core = { };
          environment.shells = [ pkgs.fish ];

          programs = {
            tmux.enable = true;
            htop.enable = true;
            git.enable = true;
            fish.enable = true;
            fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";
          };
        }
      )

      #################################################################### MOTD (no options)
      # cfg: https://github.com/rust-motd/rust-motd
      (
        mkIf true {
          programs.rust-motd = {
            enable = true;
            enableMotdInSSHD = true;
            settings = {
              banner = {
                color = "yellow";
                command = ''
                  echo ""
                  echo " +-------------+"
                  echo " | 10110 010   |"
                  echo " | 101 101 10  |"
                  echo " | 0   _____   |"
                  echo " |    / ___ \  |"
                  echo " |   / /__/ /  |"
                  echo " +--/ _____/---+"
                  echo "   / /"
                  echo "  /_/"
                  echo ""
                  systemctl --failed --quiet
                '';
              };
              uptime.prefix = "Uptime:";
              last_login.core = 2;
            };
          };
        }
      )

      #################################################################### WIREGUARD
      # cfg: https://man7.org/linux/man-pages/man8/wg.8.html
      (
        mkIf (cfg.vpn.wireguard.enable) {
          networking.wg-quick.interfaces.${cfg.vpn.wireguard.interfaceName}.configFile = cfg.vpn.wireguard.configFile;
        }
      )

      #################################################################### ERIGON
      # cli: https://erigon.gitbook.io/erigon/advanced-usage/command-line-options
      # sec: https://erigon.gitbook.io/erigon/basic-usage/default-ports-and-firewalls
      (
        let
          local.erigon.parsedEndpoint = parseEndpoint cfg.execution.erigon.endpoint;
        in

        mkIf (cfg.execution.erigon.enable) {
          environment.systemPackages = [
            pkgs.erigon
          ];

          systemd.services.erigon = {
            enable = true;

            description = "execution, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = map (name: "${name}.service") activeConsensusClients
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.erigon}/bin/erigon \
              --datadir ${cfg.execution.erigon.dataDir} \
              --chain mainnet \
              --authrpc.vhosts "*" \
              --authrpc.port ${local.erigon.parsedEndpoint.port} \
              --authrpc.addr ${local.erigon.parsedEndpoint.addr} \
              --authrpc.jwtsecret ${cfg.execution.erigon.jwtSecretFile} \
              --metrics'';

            wantedBy = [ "multi-user.target" ];
          };

          networking.firewall = {
            allowedTCPPorts = [ 30303 30304 42069 ];
            allowedUDPPorts = [ 30303 30304 42069 ];
          };
        }
      )

      #################################################################### GETH
      # cli: https://geth.ethereum.org/docs/fundamentals/command-line-options
      # sec: https://geth.ethereum.org/docs/fundamentals/security
      (
        let
          local.geth.parsedEndpoint = parseEndpoint cfg.execution.geth.endpoint;
        in

        mkIf (cfg.execution.geth.enable) {
          environment.systemPackages = [
            pkgs.go-ethereum
          ];

          systemd.services.go-ethereum = {
            enable = true;

            description = "execution, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = map (name: "${name}.service") activeConsensusClients
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.go-ethereum}/bin/geth \
              --mainnet \
              --datadir ${cfg.execution.geth.dataDir} \
              --authrpc.vhosts "*" \
              --authrpc.port ${local.geth.parsedEndpoint.port} \
              --authrpc.addr ${local.geth.parsedEndpoint.addr} \
              --authrpc.jwtsecret ${cfg.execution.geth.jwtSecretFile} \
              --metrics'';

            wantedBy = [ "multi-user.target" ];
          };

          networking.firewall = {
            allowedTCPPorts = [ 30303 ];
            allowedUDPPorts = [ 30303 ];
          };
        }
      )

      #################################################################### NETHERMIND
      # cli: https://docs.nethermind.io/nethermind/ethereum-client/configuration
      # sec: https://docs.nethermind.io/nethermind/first-steps-with-nethermind/firewall-configuration
      (
        let
          local.nethermind.parsedEndpoint = parseEndpoint cfg.execution.nethermind.endpoint;
        in

        mkIf (cfg.execution.nethermind.enable) {
          environment.systemPackages = [
            pkgs.nethermind
          ];

          systemd.services.nethermind = {
            enable = true;

            description = "execution, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = map (name: "${name}.service") activeConsensusClients
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.nethermind}/bin/Nethermind.Runner \
              --config mainnet \
              --datadir ${cfg.execution.nethermind.dataDir} \
              --JsonRpc.EngineHost ${local.nethermind.parsedEndpoint.addr} \
              --JsonRpc.EnginePort ${local.nethermind.parsedEndpoint.port} \
              --JsonRpc.JwtSecretFile ${cfg.execution.nethermind.jwtSecretFile} \
              --Metrics.Enabled true'';

            wantedBy = [ "multi-user.target" ];
          };

          networking.firewall = {
            allowedTCPPorts = [ 30303 ];
            allowedUDPPorts = [ 30303 ];
          };
        }
      )

      #################################################################### BESU
      # cli: https://besu.hyperledger.org/stable/public-networks/reference/cli/options
      # sec: https://besu.hyperledger.org/stable/public-networks/how-to/connect/configure-ports
      (
        let
          local.besu.parsedEndpoint = parseEndpoint cfg.execution.besu.endpoint;
        in

        mkIf (cfg.execution.besu.enable) {
          environment.systemPackages = [
            pkgs.besu
          ];

          systemd.services.besu = {
            enable = true;

            description = "execution, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = map (name: "${name}.service") activeConsensusClients
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.besu}/bin/besu \
              --network=mainnet \
              --data-path=${cfg.execution.besu.dataDir} \
              --engine-rpc-enabled=true \
              --engine-host-allowlist="*" \
              --engine-rpc-port=${local.besu.parsedEndpoint.port} \
              --rpc-http-host=${local.besu.parsedEndpoint.addr} \
              --engine-jwt-secret=${cfg.execution.besu.jwtSecretFile} \
              --metrics-enabled=true'';

            wantedBy = [ "multi-user.target" ];
          };

          networking.firewall = {
            allowedTCPPorts = [ 30303 ];
            allowedUDPPorts = [ 30303 ];
          };
        }
      )

      #################################################################### MEV-BOOST
      # cli: https://github.com/flashbots/mev-boost#mev-boost-cli-arguments
      (
        let
          local.mev-boost.parsedEndpoint = parseEndpoint cfg.addons.mev-boost.endpoint;
        in

        mkIf (cfg.addons.mev-boost.enable) {
          systemd.services.mev-boost = {
            enable = true;

            description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

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
                        "https://0xa1559ace749633b997cb3fdacffb890aeebdb0f5a3b6aaa7eeeaf1a38af0a8fe88b9e4b1f61f236d2e64d95733327a62@relay.ultrasound.money"
                      ]} \
                      -addr ${local.mev-boost.parsedEndpoint.addr}:${local.mev-boost.parsedEndpoint.port}'';

            wantedBy = [ "multi-user.target" ];
          };
        }
      )

      #################################################################### LIGHTHOUSE
      # cli: https://lighthouse-book.sigmaprime.io/api-bn.html
      # sec: https://lighthouse-book.sigmaprime.io/advanced_networking.html
      (
        let
          local.lighthouse.parsedEndpoint = parseEndpoint cfg.consensus.lighthouse.endpoint;
        in

        mkIf (cfg.consensus.lighthouse.enable) {
          environment.systemPackages = with pkgs; [
            lighthouse
          ];

          systemd.services.lighthouse = {
            enable = true;

            description = "beacon, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = [ ]
              ++ lib.optional (cfg.addons.mev-boost.enable)
              "mev-boost.service"
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.lighthouse}/bin/lighthouse bn \
                      --datadir ${cfg.consensus.lighthouse.dataDir} \
                      --network mainnet \
                      --http \
                      --http-address ${local.lighthouse.parsedEndpoint.addr} \
                      --http-port ${local.lighthouse.parsedEndpoint.port} \
                      --http-allow-origin "*" \
                      --execution-endpoint ${cfg.consensus.lighthouse.execEndpoint} \
                      --execution-jwt ${cfg.consensus.lighthouse.jwtSecretFile} \
                      --prune-payloads false \
                      ${if cfg.addons.mev-boost.enable then
                      "--builder ${cfg.addons.mev-boost.endpoint}"
                      else "" } \
                      ${if cfg.consensus.lighthouse.slasher.enable then
                      "--slasher "
                      + "--slasher-history-length " + (toString cfg.consensus.lighthouse.slasher.historyLength)
                      + "--slasher-max-db-size " + (toString cfg.consensus.lighthouse.slasher.maxDatabaseSize)
                      else "" } \
                      --metrics'';

            wantedBy = [ "multi-user.target" ];
          };

          # Firewall
          networking.firewall = {
            allowedTCPPorts = [ 9000 ];
            allowedUDPPorts = [ 9000 ];

            interfaces = builtins.listToAttrs (map
              (clientName: {
                name = "${cfg.vpn.${clientName}.interfaceName}";
                value = {
                  allowedTCPPorts = [
                    (lib.strings.toInt local.lighthouse.parsedEndpoint.port)
                  ];
                };
              })
              activeVPNClients);
          };
        }
      )

      #################################################################### PRYSM
      # cli: https://docs.prylabs.network/docs/prysm-usage/parameters
      # sec: https://docs.prylabs.network/docs/prysm-usage/p2p-host-ip
      (
        let
          local.prysm.parsedEndpoint = parseEndpoint cfg.consensus.prysm.endpoint;
        in

        mkIf (cfg.consensus.prysm.enable) {
          environment.systemPackages = with pkgs; [
            prysm
          ];

          systemd.services.prysm = {
            enable = true;

            description = "beacon, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = [ ]
              ++ lib.optional (cfg.addons.mev-boost.enable)
              "mev-boost.service"
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.prysm}/bin/beacon-chain \
                      --datadir ${cfg.consensus.prysm.dataDir} \
                      --mainnet \
                      --grpc-gateway-host ${local.prysm.parsedEndpoint.addr} \
                      --grpc-gateway-port ${local.prysm.parsedEndpoint.port} \
                      --execution-endpoint ${cfg.consensus.prysm.execEndpoint} \
                      --jwt-secret ${cfg.consensus.prysm.jwtSecretFile} \
                      ${if cfg.addons.mev-boost.enable then
                      "--http-mev-relay ${cfg.addons.mev-boost.endpoint}"
                      else "" } \
                      ${if cfg.consensus.prysm.slasher.enable then
                      "--historical-slasher-node " 
                      + "--slasher-datadir ${cfg.consensus.prysm.dataDir}/beacon/slasher_db"
                      else "" } \
                      --accept-terms-of-use'';

            wantedBy = [ "multi-user.target" ];
          };

          # Firewall
          networking.firewall = {
            allowedTCPPorts = [ 12000 13000 ];
            allowedUDPPorts = [ 12000 13000 ];

            interfaces = builtins.listToAttrs (map
              (clientName: {
                name = "${cfg.vpn.${clientName}.interfaceName}";
                value = {
                  allowedTCPPorts = [
                    (lib.strings.toInt local.prysm.parsedEndpoint.port)
                  ];
                };
              })
              activeVPNClients);
          };
        }
      )

      #################################################################### TEKU
      # cli: https://docs.teku.consensys.net/reference/cli
      (
        let
          local.teku.parsedEndpoint = parseEndpoint cfg.consensus.teku.endpoint;
        in

        mkIf (cfg.consensus.teku.enable) {
          environment.systemPackages = with pkgs; [
            teku
          ];

          systemd.services.teku = {
            enable = true;

            description = "beacon, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = [ ]
              ++ lib.optional (cfg.addons.mev-boost.enable)
              "mev-boost.service"
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.teku}/bin/teku \
                      --data-base-path=${cfg.consensus.teku.dataDir} \
                      --network=mainnet \
                      --rest-api-enabled=true \
                      --rest-api-port=${local.teku.parsedEndpoint.port} \
                      --rest-api-interface=${local.teku.parsedEndpoint.addr} \
                      --rest-api-host-allowlist="*" \
                      --ee-endpoint=${cfg.consensus.teku.execEndpoint} \
                      --ee-jwt-secret-file=${cfg.consensus.teku.jwtSecretFile} \
                      ${if cfg.addons.mev-boost.enable then
                      "--builder-endpoint=${cfg.addons.mev-boost.endpoint}"
                      else "" } \
                      --metrics-enabled=true'';

            wantedBy = [ "multi-user.target" ];
          };

          # Firewall
          networking.firewall = {
            allowedTCPPorts = [ 9000 ];
            allowedUDPPorts = [ 9000 ];

            interfaces = builtins.listToAttrs (map
              (clientName: {
                name = "${cfg.vpn.${clientName}.interfaceName}";
                value = {
                  allowedTCPPorts = [
                    (lib.strings.toInt local.teku.parsedEndpoint.port)
                  ];
                };
              })
              activeVPNClients);
          };
        }
      )

      #################################################################### NIMBUS
      # cli: https://nimbus.guide/options.html
      (
        let
          local.nimbus.parsedEndpoint = parseEndpoint cfg.consensus.nimbus.endpoint;
        in

        mkIf (cfg.consensus.nimbus.enable) {
          environment.systemPackages = with pkgs; [
            nimbus
          ];

          systemd.services.nimbus = {
            enable = true;

            description = "beacon, mainnet";
            requires = [ ]
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            after = [ ]
              ++ lib.optional (cfg.addons.mev-boost.enable)
              "mev-boost.service"
              ++ lib.optional (elem "wireguard" activeVPNClients)
              "wg-quick-${cfg.vpn.wireguard.interfaceName}.service";

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              Type = "simple";
            };

            script = ''${pkgs.nimbus}/bin/nimbus_beacon_node \
                      --data-dir=${cfg.consensus.nimbus.dataDir} \
                      --network=mainnet \
                      --rest=true \
                      --rest-port=${local.nimbus.parsedEndpoint.port} \
                      --rest-address=${local.nimbus.parsedEndpoint.addr} \
                      --rest-allow-origin="*" \
                      --el=${cfg.consensus.nimbus.execEndpoint} \
                      --jwt-secret=${cfg.consensus.nimbus.jwtSecretFile} \
                      ${if cfg.addons.mev-boost.enable then
                      "--payload-builder=true "
                      + "--payload-builder-url=${cfg.addons.mev-boost.endpoint}"
                      else "" } \
                      --metrics=true'';

            wantedBy = [ "multi-user.target" ];
          };

          # Firewall
          networking.firewall = {
            allowedTCPPorts = [ 9000 ];
            allowedUDPPorts = [ 9000 ];

            interfaces = builtins.listToAttrs (map
              (clientName: {
                name = "${cfg.vpn.${clientName}.interfaceName}";
                value = {
                  allowedTCPPorts = [
                    (lib.strings.toInt local.nimbus.parsedEndpoint.port)
                  ];
                };
              })
              activeVPNClients);
          };
        }
      )
    ];
}
