{
  description = "Nixobolus flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # overrides
    overrides.url = "path:./overrides";
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , nixpkgs
    , overrides
    }@inputs:
    let
      inherit (self) outputs;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      ### OPTIONS AND SERVICES --- START

      #################################################################### LOCALIZATION
      options = {

        localization = {
          hostname = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
            default = "homestaker";
          };
          timezone = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
            default = "Europe/Helsinki";
          };
          keymap = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
            default = "us";
          };
        };

        ssh = {
          privateKeyPath = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.path;
            default = "/var/mnt/secrets/ssh/id_ed25519";
          };
        };

        user = {
          authorizedKeys = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.listOf nixpkgs.lib.types.str;
            default = [ ];
          };
        };

        erigon = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
          endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          datadir = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
        };

        lighthouse = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
          endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          exec.endpoint = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
          slasher = {
            enable = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.bool;
            };
            history-length = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.int;
              default = 4096;
            };
            max-db-size = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.int;
              default = 256;
            };
          };
          mev-boost = {
            endpoint = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.str;
            };
          };
          datadir = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.str;
          };
        };

        mev-boost = {
          enable = nixpkgs.lib.mkOption {
            type = nixpkgs.lib.types.bool;
            default = false;
          };
        };

      };

      cfg = {

        mev-boost = nixpkgs.lib.mkIf options.mev-boost.enable {
          virtualisation.podman.enable = true;
          # dnsname allows containers to use ${name}.dns.podman to reach each other
          # on the same host instead of using hard-coded IPs.
          # NOTE: --net must be the same on the containers, and not eq "host"
          # TODO: extend this with flannel ontop of wireguard for cross-node comms
          virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

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

            script = ''${nixpkgs.mev-boost}/bin/mev-boost \
            -mainnet \
            -relay-check \
            -relays ${nixpkgs.lib.concatStringsSep "," [
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
        };

        lighthouse = nixpkgs.lib.mkIf options.lighthouse.enable {
          # package
          environment.systemPackages = with nixpkgs; [
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

            script = ''${nixpkgs.lighthouse}/bin/lighthouse bn \
            --datadir ${options.lighthouse.datadir} \
            --network mainnet \
            --http --http-address ${options.lighthouse.endpoint} \
            --execution-endpoint ${options.lighthouse.exec.endpoint} \
            --execution-jwt ${options.lighthouse.datadir}/jwt.hex \
            --builder ${options.lighthouse.mev-boost.endpoint} \
            --prune-payloads false \
            --metrics \
            ${if options.lighthouse.slasher.enable then
              "--slasher "
              + " --slasher-history-length " + (toString options.lighthouse.slasher.history-length)
              + " --slasher-max-db-size " + (toString options.lighthouse.slasher.max-db-size)
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
        };

        erigon = nixpkgs.lib.mkIf options.erigon.enable {
          # package
          environment.systemPackages = with nixpkgs; [
            erigon
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

            script = ''${nixpkgs.erigon}/bin/erigon \
            --datadir=${options.erigon.datadir} \
            --chain mainnet \
            --authrpc.vhosts="*" \
            --authrpc.addr ${options.erigon.endpoint} \
            --authrpc.jwtsecret=${options.erigon.datadir}/jwt.hex \
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
        };

        localization = {
          networking.hostName = options.localization.hostname;
          time.timeZone = options.localization.timezone;
          console.keyMap = options.localization.keymap;
        };

        ssh = {
          services.openssh = {
            enable = true;
            settings.PasswordAuthentication = false;
            hostKeys = [{
              path = options.ssh.privateKeyPath;
              type = "ed25519";
            }];
          };
        };

        user = {
          services.getty.autologinUser = "core";
          users.users.core = {
            isNormalUser = true;
            group = "core";
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = options.user.authorizedKeys;
            shell = nixpkgs.fish;
          };
          users.groups.core = { };
          environment.shells = [ nixpkgs.fish ];
          programs.fish.enable = true;

          home-manager.users.core = { nixpkgs, ... }: {

            sops = {
              defaultSopsFile = ./secrets/default.yaml;
              secrets."wireguard/wg0" = {
                path = "%r/wireguard/wg0.conf";
              };
              age.sshKeyPaths = [ options.ssh.privateKeyPath ];
            };

            home.packages = with nixpkgs; [
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
        };

      };


      ### OPTIONS AND SERVICES --- END
    in
    {
      # devshell -- accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nix fmt -- accessible through 'nix fmt'
      formatter = forEachPkgs (pkgs: pkgs.nixpkgs-fmt);

      # filters options recursively
      # available through -- 'nix eval --json .#exports'
      exports = nixpkgs.lib.attrsets.mapAttrsRecursiveCond
        (v: ! nixpkgs.lib.options.isOption v)
        (k: v: v.type.name)
        options;

      # To use, see: https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
      nixosModules = {
        # General
        localization = { config, ... }: {
          options = options.localization;
          config = cfg.localization;
        };
        user = { pkgs, config, ... }: {
          options = options.user;
          config = cfg.user;
        };
        ssh = { config, pkgs, ... }: {
          options = options.ssh;
          config = cfg.ssh;
        };
        # Ethereum
        erigon = { config, pkgs, ... }: {
          options = options.erigon;
          config = cfg.erigon;
        };
        lighthouse = { config, pkgs, ... }: {
          options = options.lighthouse;
          config = cfg.lighthouse;
        };
        mev-boost = { config, pkgs, ... }: {
          options = options.mev-boost;
          config = cfg.mev-boost;
        };
      };

    };
}
