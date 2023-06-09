{
  description = "Nixobolus flake";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin.url = "github:lnl7/nix-darwin";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    ethereum-nix.inputs.nixpkgs.follows = "nixpkgs";
    ethereum-nix.url = "github:nix-community/ethereum.nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    mission-control.url = "github:Platonic-Systems/mission-control";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , ethereum-nix
    , flake-parts
    , home-manager
    , nixpkgs
    , nixpkgs-stable
    , ...
    }@inputs:

    flake-parts.lib.mkFlake { inherit inputs; } rec {

      imports = [
        inputs.flake-root.flakeModule
        inputs.mission-control.flakeModule
      ];
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem = { pkgs, lib, config, system, ... }: {
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
        mission-control.scripts = { };
        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              cpio
              git
              jq
              nix
              nix-tree
              rsync
              ssh-to-age
              zstd
            ];
            inputsFrom = [
              config.flake-root.devShell
              config.mission-control.devShell
            ];
          };
        };
        packages = with flake.nixosConfigurations; {
          "homestakeros" = homestakeros.config.system.build.kexecTree;
        };
      };
      flake =
        let
          inherit (self) outputs;

          homestakeros_options = with nixpkgs.lib; {
            localization = {
              hostname = mkOption {
                type = types.str;
                default = "homestaker";
                description = "The name of the machine";
              };
              timezone = mkOption {
                type = types.str;
                default = "Europe/Helsinki";
                description = "The time zone used when displaying times and dates";
              };
            };

            mounts = mkOption {
              type = types.attrsOf types.attrs;
              default = { };
              description = "Systemd mounts configuration";
            };

            ssh = {
              privateKeyPath = mkOption {
                type = types.path;
                default = "/var/mnt/secrets/ssh/id_ed25519";
                description = "Path, where SSH host keys are automatically generated";
              };
            };

            user = {
              authorizedKeys = mkOption {
                type = types.listOf types.singleLineStr;
                default = [ ];
                description = "A list of public keys that should be added to the user’s authorized keys";
              };
            };

            erigon = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to enable Erigon";
              };
              endpoint = mkOption {
                type = types.str;
                default = "http://127.0.0.1:8551";
                description = "HTTP-RPC server listening interface of engine API";
              };
              datadir = mkOption {
                type = types.str;
                default = "/var/mnt/erigon";
                description = "Data directory for the databases";
              };
            };

            lighthouse = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to enable Lighthouse";
              };
              endpoint = mkOption {
                type = types.str;
                default = "http://127.0.0.1:5052";
                description = "HTTP server listening interface";
              };
              exec.endpoint = mkOption {
                type = types.str;
                default = "http://127.0.0.1:8551";
                description = "Listening interface of the execution engine API";
              };
              slasher = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether to enable slasher";
                };
                history-length = mkOption {
                  type = types.int;
                  default = 4096;
                  description = "Number of epochs to store";
                };
                max-db-size = mkOption {
                  type = types.int;
                  default = 256;
                  description = "Maximum size of the database in gigabytes";
                };
              };
              mev-boost = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether to enable MEV-Boost";
                };
                endpoint = mkOption {
                  type = types.str;
                  default = "http://127.0.0.1:18550";
                  description = "Listening interface for MEV-Boost server";
                };
              };
              datadir = mkOption {
                type = types.str;
                description = "Data directory for the databases";
              };
            };
          };

          homestakeros = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./system
              ./system/ramdisk.nix
              ./system/formats/netboot-kexec.nix
              self.nixosModules.homestakeros
              home-manager.nixosModules.home-manager
              disko.nixosModules.disko
              {
                nixpkgs.overlays = [
                  ethereum-nix.overlays.default
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
                system.stateVersion = "23.05";
              }
            ];
          };
        in
        rec {
          # filters options recursively
          # option exports -- accessible through 'nix eval --json .#exports'
          exports = nixpkgs.lib.attrsets.mapAttrsRecursiveCond
            (v: ! nixpkgs.lib.options.isOption v)
            (k: v: v.type.name)
            homestakeros_options;

          overlays = import ./overlays { inherit inputs; };

          nixosConfigurations = with nixpkgs.lib; {
            "homestakeros" = nixosSystem (getAttrs [ "system" "specialArgs" "modules" ] homestakeros);
          } // (with nixpkgs-stable.lib; { });

          # usage: https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
          nixosModules.homestakeros = { config, lib, pkgs, ... }: with nixpkgs.lib;
            let
              cfg = config.homestakeros;
            in
            {
              options.homestakeros = homestakeros_options;

              config = mkMerge [
                ################################################################### LOCALIZATION
                (mkIf true {
                  networking.hostName = cfg.localization.hostname;
                  time.timeZone = cfg.localization.timezone;
                })

                #################################################################### MOUNTS
                (mkIf true {
                  systemd.mounts = lib.attrsets.mapAttrsToList
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
                    (config.mounts or { });
                })

                #################################################################### SSH (system level)
                (mkIf true {
                  services.openssh = {
                    enable = true;
                    hostKeys = [{
                      path = cfg.ssh.privateKeyPath;
                      type = "ed25519";
                    }];
                    allowSFTP = false;
                    extraConfig = ''
                      AllowTcpForwarding yes
                      X11Forwarding no
                      AllowAgentForwarding no
                      AllowStreamLocalForwarding no
                      AuthenticationMethods publickey
                    '';
                    settings.PasswordAuthentication = false;
                    settings.KbdInteractiveAuthentication = false;
                  };
                })

                #################################################################### USER (core)
                (mkIf true {
                  #services.getty.autologinUser = "core";
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
                  systemd.services.wg0 = {
                    enable = true;

                    description = "wireguard interface for cross-node communication";
                    requires = [ "network-online.target" ];
                    after = [ "network-online.target" ];

                    serviceConfig = {
                      Type = "oneshot";
                    };

                    script = ''${pkgs.wireguard-tools}/bin/wg-quick \
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
                  systemd.user.services.erigon =
                    let
                      # split endpoint to address and port
                      endpointRegex = "(https?://)?([^:/]+):([0-9]+)(/.*)?$";
                      endpointMatch = builtins.match endpointRegex cfg.erigon.endpoint;
                      endpoint = {
                        addr = builtins.elemAt endpointMatch 1;
                        port = builtins.elemAt endpointMatch 2;
                      };
                    in
                    {
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
                      --authrpc.port ${endpoint.port} \
                      --authrpc.addr ${endpoint.addr} \
                      --authrpc.jwtsecret=%r/jwt.hex \
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
                (mkIf (cfg.lighthouse.mev-boost.enable) {
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
                  systemd.user.services.lighthouse =
                    let
                      # split endpoint to address and port
                      endpointRegex = "(https?://)?([^:/]+):([0-9]+)(/.*)?$";
                      endpointMatch = builtins.match endpointRegex cfg.lighthouse.endpoint;
                      endpoint = {
                        addr = builtins.elemAt endpointMatch 1;
                        port = builtins.elemAt endpointMatch 2;
                      };
                    in
                    {
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
                      --http --http-address ${endpoint.addr} \
                      --http-port ${endpoint.port} \
                      --http-allow-origin "*" \
                      --execution-endpoint ${cfg.lighthouse.exec.endpoint} \
                      --execution-jwt %r/jwt.hex \
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
                      5052 # TODO: use 'lighthouse.endpoint.port' here by converting it to u16
                    ];
                  };
                })
              ];
            };
        };
    };
}

