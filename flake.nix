{
  description = "Nixobolus flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixobolus.url = "github:ponkila/nixobolus/jesse/options-extractions";
    sops-nix.url = "github:Mic92/sops-nix";
    overrides.url = "path:./overrides";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ethereum-nix = {
      url = "github:nix-community/ethereum.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , ethereum-nix
    , home-manager
    , nixos-generators
    , nixpkgs
    , nixobolus
    , sops-nix
    , overrides
    }@inputs:
    let
      inherit (self) outputs;
      lib = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = lib.genAttrs systems;
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      # custom packages -- accessible through 'nix build', 'nix shell', etc
      # TODO -- check that this actually works
      packages = forEachPkgs (pkgs: import ./pkgs { inherit pkgs; });

      # list hostnames from ./hosts
      ls = builtins.readDir ./hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # custom formats for nixos-generators
      # other available formats can be found at: https://github.com/nix-community/nixos-generators/tree/master/formats
      customFormats = {
        "netboot-kexec" = {
          formatAttr = "kexecTree";
          imports = [ ./system/formats/netboot-kexec.nix ];
        };
        "copytoram-iso" = {
          formatAttr = "isoImage";
          imports = [ ./system/formats/copytoram-iso.nix ];
          filename = "*.iso";
        };
      };

      modules = [
        #./hosts/test
        ./system
        ./system/ramdisk.nix
        home-manager.nixosModules.home-manager
        disko.nixosModules.disko
        nixobolus.nixosModules.erigon
        nixobolus.nixosModules.lighthouse
        nixobolus.nixosModules.mounts
        nixobolus.nixosModules.localization
        nixobolus.nixosModules.user
        nixobolus.nixosModules.mev-boost
        {
          nixpkgs.overlays = [
            ethereum-nix.overlays.default
            outputs.overlays.additions
            outputs.overlays.modifications
          ];
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
          ];
        }
        {
          system.stateVersion = "23.05";
        }
      ];

      ### OPTIONS AND CONFIGS --- START

      #################################################################### LOCALIZATION

      options.localization = {
        hostname = lib.mkOption {
          type = lib.types.str;
          default = "homestaker";
        };
        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/Helsinki";
        };
        keymap = lib.mkOption {
          type = lib.types.str;
          default = "us";
        };
      };

      config.localization = {
        networking.hostName = self.options.localization.hostname;
        time.timeZone = self.options.localization.timezone;
        console.keyMap = self.options.localization.keymap;
      };

      #################################################################### MOUNTS

      options.mounts = lib.mkOption {
        type = lib.types.attrsOf lib.types.string;
      };

      config.mounts = {
        systemd.mounts = builtins.listToAttrs (map
          (mount: {
            enable = true;
            description = mount.description or "Unnamed mount point";
            what = mount.what;
            where = mount.where;
            type = mount.type or "ext4";
            options = mount.options or "defaults";
            before = lib.mkDefault mount.before;
            wantedBy = mount.wantedBy or [ "multi-user.target" ];
          })
          options.mounts);
      };

      #################################################################### SSH (system level)
      options.ssh = {
        privateKeyPath = lib.mkOption {
          type = lib.types.path;
          default = "/var/mnt/secrets/ssh/id_ed25519";
        };
      };

      config.ssh = {
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
          hostKeys = [{
            path = self.options.ssh.privateKeyPath;
            type = "ed25519";
          }];
        };
      };

      #################################################################### USER (core)
      options.user = {
        authorizedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };

      config.user = {
        services.getty.autologinUser = "core";
        users.users.core = {
          isNormalUser = true;
          group = "core";
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = self.options.user.authorizedKeys;
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
            age.sshKeyPaths = [ self.ssh.options.privateKeyPath ];
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

      #################################################################### ERIGON
      options.erigon = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
        };
        datadir = lib.mkOption {
          type = lib.types.str;
        };
      };
      config.erigon = lib.mkIf self.options.erigon.enable {
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
            --datadir=${self.options.erigon.datadir} \
            --chain mainnet \
            --authrpc.vhosts="*" \
            --authrpc.addr ${self.options.erigon.endpoint} \
            --authrpc.jwtsecret=${self.options.erigon.datadir}/jwt.hex \
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

      #################################################################### LIGHTHOUSE

      options.lighthouse = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
        };
        exec.endpoint = lib.mkOption {
          type = lib.types.str;
        };
        slasher = {
          enable = lib.mkOption {
            type = lib.types.bool;
          };
          history-length = lib.mkOption {
            type = lib.types.int;
            default = 4096;
          };
          max-db-size = lib.mkOption {
            type = lib.types.int;
            default = 256;
          };
        };
        mev-boost = {
          endpoint = lib.mkOption {
            type = lib.types.str;
          };
        };
        datadir = lib.mkOption {
          type = lib.types.str;
        };
      };

      config.lighthouse = lib.mkIf self.options.lighthouse.enable {
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
            --datadir ${self.options.lighthouse.datadir} \
            --network mainnet \
            --http --http-address ${self.options.lighthouse.endpoint} \
            --execution-endpoint ${self.options.lighthouse.exec.endpoint} \
            --execution-jwt ${self.options.lighthouse.datadir}/jwt.hex \
            --builder ${self.options.lighthouse.mev-boost.endpoint} \
            --prune-payloads false \
            --metrics \
            ${if self.options.lighthouse.slasher.enable then
              "--slasher "
              + " --slasher-history-length " + (toString self.options.lighthouse.slasher.history-length)
              + " --slasher-max-db-size " + (toString self.options.lighthouse.slasher.max-db-size)
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

      #################################################################### MEV-BOOST

      options.mev-boost = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };

      config.mev-boost = lib.mkIf self.options.mev-boost.enable {
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
      };

      #################################################################### WIREGUARD (no options)
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

      #################################################################### PROMETHEUS (no options)
      services.prometheus = {
        enable = false;
        port = 9001;
        exporters = {
          node = {
            enable = false;
            enabledCollectors = [ "systemd" ];
            port = 9002;
          };
        };
        scrapeConfigs = [
          {
            job_name = config.networking.hostName;
            static_configs = [{
              targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
            }];
          }
          {
            job_name = "erigon";
            metrics_path = "/debug/metrics/prometheus";
            scheme = "http";
            static_configs = [{
              targets = [ "127.0.0.1:6060" "127.0.0.1:6061" "127.0.0.1:6062" ];
            }];
          }
          {
            job_name = "lighthouse";
            scrape_interval = "5s";
            static_configs = [{
              targets = [ "127.0.0.1:5054" "127.0.0.1:5064" ];
            }];
          }
        ];
      };
      ### OPTIONS AND CONFIGS --- END
    in
    rec {
      # devshell -- accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # nix code formatter -- accessible through 'nix fmt'
      formatter = forEachPkgs (pkgs: pkgs.nixpkgs-fmt);

      # nixos-generators attributes for each system and hostname combination
      # available through 'nix build .#nixobolus.<system_arch>.<hostname>'
      nixobolus = builtins.listToAttrs (map
        (system: {
          name = system;
          value = builtins.listToAttrs (map
            (hostname: {
              name = hostname;
              value = nixos-generators.nixosGenerate {
                inherit modules system customFormats;
                specialArgs = { inherit inputs outputs; };
                format = "netboot-kexec";
              };
            })
            hostnames);
        })
        systems);

      # nixos configuration entrypoints (needed for accessing options through eval)
      # TODO -- only maps "x86_64-linux" at the moment 
      nixosConfigurations = builtins.listToAttrs (map
        (hostname: {
          name = hostname;
          value = lib.nixosSystem {
            system = "x86_64-linux";
            inherit modules;
            specialArgs = { inherit inputs outputs; };
          };
        })
        hostnames);

      # filters options recursively
      # option exports -- available through'nix eval --json .#exports'
      exports = lib.attrsets.mapAttrsRecursiveCond
        (v: ! lib.options.isOption v)
        (k: v: v.type.name)
        options;

      # To use, see: https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
      # TODO --  infinite recursion on clients side 
      nixosModules = {
        # General
        localization = { config, ... }: {
          options = options.localization;
          config = config.localization;
        };
        mounts = { pkgs, config, lib, ... }: {
          options = options.mounts;
          config = config.mounts;
        };
        user = { pkgs, config, inputs, lib, ... }: {
          options = options.user;
          config = config.user;
        };
        ssh = { config, lib, pkgs, ... }: {
          options = options.ssh;
          config = config.ssh;
        };
        # Ethereum
        erigon = { config, lib, pkgs, ... }: {
          options = options.erigon;
          config = config.erigon;
        };
        lighthouse = { config, lib, pkgs, ... }: {
          options = options.lighthouse;
          config = config.lighthouse;
        };
        mev-boost = { config, lib, pkgs, ... }: {
          options = options.mev-boost;
          config = config.mev-boost;
        };
      };

    };
}
