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
    ethereum-nix.inputs.nixpkgs.follows = "nixpkgs";
    ethereum-nix.url = "github:nix-community/ethereum.nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    mission-control.url = "github:Platonic-Systems/mission-control";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pre-commit-hooks-nix.url = "github:hercules-ci/pre-commit-hooks.nix/flakeModule";
  };

  outputs =
    { self
    , ethereum-nix
    , flake-parts
    , nixpkgs
    , nixpkgs-stable
    , ...
    }@inputs:

    flake-parts.lib.mkFlake { inherit inputs; } rec {

      imports = [
        inputs.flake-root.flakeModule
        inputs.mission-control.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
      ];
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem = { pkgs, lib, config, system, ... }: {
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

        pre-commit.settings = {
          hooks = {
            shellcheck.enable = true;
            nixpkgs-fmt.enable = true;
            flakecheck = {
              enable = true;
              name = "flakecheck";
              description = "Check whether the flake evaluates and run its tests";
              entry = "nix flake check --no-warn-dirty";
              language = "system";
              pass_filenames = false;
            };
          };
        };
        # Do not perform pre-commit hooks w/ nix flake check
        pre-commit.check.enable = false;

        mission-control.scripts = { };

        # Devshells for bootstrapping
        # Accessible through 'nix develop' or 'nix-shell' (legacy)
        devShells.default = pkgs.mkShell {
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
          shellHook = ''
            ${config.pre-commit.installationScript}
          '';
        };

        # Custom packages and aliases for building hosts
        # Accessible through 'nix build', 'nix run', etc
        packages = {
          "homestakeros" = flake.nixosConfigurations.homestakeros.config.system.build.kexecTree;
          "buidl" =
            let
              pkgs = import nixpkgs { inherit system; };
              name = "buidl";
              buidl-script = (pkgs.writeScriptBin name (builtins.readFile ./scripts/buidl.sh)).overrideAttrs (old: {
                buildCommand = "${old.buildCommand}\n patchShebangs $out";
              });
            in
            pkgs.symlinkJoin {
              inherit name;
              paths = [ buidl-script ] ++ [ /* buildInputs here */ ];
              buildInputs = with pkgs; [ makeWrapper ];
              postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
            };
        };
      };
      flake =
        let
          inherit (self) outputs;

          homestakerosOptions = with nixpkgs.lib;
            let
              nospace = str: filter (c: c == " ") (stringToCharacters str) == [ ];
            in
            {
              localization = {
                hostname = mkOption {
                  type = types.strMatching "^$|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$";
                  default = "homestaker";
                  description = "The name of the machine.";
                };
                timezone = mkOption {
                  type = types.nullOr (types.addCheck types.str nospace);
                  default = null;
                  description = "The time zone used when displaying times and dates.";
                  example = "America/New_York";
                };
              };

              mounts = mkOption {
                type = types.attrsOf types.attrs;
                default = { };
                description = "Definition of systemd mount units. Click [here](https://www.freedesktop.org/software/systemd/man/systemd.mount.html#Options) for more information.";
                example = {
                  my-mount = {
                    enable = true;
                    description = "A storage device";

                    what = "/dev/disk/by-label/my-label";
                    where = "/path/to/my/mount";
                    options = "noatime";
                    type = "btrfs";

                    wantedBy = [ "multi-user.target" ];
                  };
                };
              };

              vpn = {
                wireguard = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether to enable WireGuard.";
                  };
                  configFile = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "A file path for the wg-quick configuration.";
                    example = "/var/mnt/secrets/wg0.conf";
                  };
                  interfaceName = mkOption {
                    type = types.str;
                    default = "wg0";
                    description = "The name assigned to the WireGuard network interface.";
                  };
                };
              };

              ssh = {
                authorizedKeys = mkOption {
                  type = types.listOf types.singleLineStr;
                  default = [ ];
                  description = "A list of public SSH keys to be added to the user's authorized keys.";
                };
                privateKeyFile = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  description = "Path to the Ed25519 SSH host key. If absent, the key will be generated automatically.";
                  example = "/var/mnt/secrets/ssh/id_ed25519";
                };
              };

              execution = {
                erigon = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether to enable Erigon.";
                  };
                  endpoint = mkOption {
                    type = types.str;
                    default = "http://127.0.0.1:8551";
                    description = "HTTP-RPC server listening interface of engine API.";
                  };
                  dataDir = mkOption {
                    type = types.path;
                    default = "/var/mnt/erigon";
                    description = "Data directory for the blockchain.";
                  };
                  jwtSecretFile = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Path to the token that ensures safe connection between CL and EL.";
                    example = "/var/mnt/erigon/jwt.hex";
                  };
                };
              };

              consensus = {
                lighthouse = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether to enable Lighthouse.";
                  };
                  endpoint = mkOption {
                    type = types.str;
                    default = "http://127.0.0.1:5052";
                    description = "HTTP server listening interface.";
                  };
                  execEndpoint = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Server endpoint for an execution layer JWT-authenticated HTTP JSON-RPC connection.";
                    example = "http://127.0.0.1:8551";
                  };
                  slasher = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Whether to enable slasher.";
                    };
                    historyLength = mkOption {
                      type = types.int;
                      default = 4096;
                      description = "Number of epochs to store.";
                    };
                    maxDatabaseSize = mkOption {
                      type = types.int;
                      default = 256;
                      description = "Maximum size of the slasher database in gigabytes.";
                    };
                  };
                  dataDir = mkOption {
                    type = types.path;
                    default = "/var/mnt/lighthouse";
                    description = "Data directory for the blockchain.";
                  };
                  jwtSecretFile = mkOption {
                    type = types.nullOr types.path;
                    default = null;
                    description = "Path to the token that ensures safe connection between CL and EL.";
                    example = "/var/mnt/lighthouse/jwt.hex";
                  };
                };
              };

              addons = {
                mev-boost = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether to enable MEV-Boost.";
                  };
                  endpoint = mkOption {
                    type = types.str;
                    default = "http://127.0.0.1:18550";
                    description = "Listening interface for the MEV-Boost server.";
                  };
                };
              };
            };

          homestakeros = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              self.nixosModules.kexecTree
              self.nixosModules.homestakeros
              {
                system.stateVersion = "23.11";
              }
              # Keeping this here for testing
              # {
              #   homestakeros = {
              #     consensus.lighthouse.enable = true;
              #     addons.mev-boost.enable = true;
              #     execution.erigon.enable = true;
              #     vpn.wireguard = {
              #       enable = true;
              #       configFile = "/var/mnt/secrets/wg0.conf";
              #     };
              #   };
              # }
              {
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ] ++ nixpkgs.lib.optional (builtins.pathExists /tmp/data.nix) /tmp/data.nix;
          };
        in
        rec {
          # Filters options to exports recursively
          # Accessible through 'nix eval --json .#exports'
          exports = nixpkgs.lib.attrsets.mapAttrsRecursiveCond
            (v: ! nixpkgs.lib.options.isOption v)
            (k: v: {
              type = v.type.name;
              default = v.default;
              description = if v ? description then v.description else null;
              example = if v ? example then v.example else null;
            })
            homestakerosOptions;

          overlays = import ./overlays { inherit inputs; };

          # NixOS configuration entrypoints for the frontend
          nixosConfigurations = with nixpkgs.lib; {
            "homestakeros" = nixosSystem homestakeros;
          } // (with nixpkgs-stable.lib; { });

          # Format modules
          nixosModules.isoImage = {
            imports = [ ./system ./system/formats/copytoram-iso.nix ];
          };
          nixosModules.kexecTree = {
            imports = [ ./system ./system/formats/netboot-kexec.nix ];
          };

          # HomestakerOS module for Ethereum-related components
          nixosModules.homestakeros = { config, lib, pkgs, ... }: with nixpkgs.lib;
            let
              cfg = config.homestakeros;

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

              # Get the active client from a list of available clients
              # Note: In nix, variables are not evaluated unless they are used somewhere
              activeConsensusClients = getActiveClients (builtins.attrNames cfg.consensus) cfg.consensus;
              activeExecutionClients = getActiveClients (builtins.attrNames cfg.execution) cfg.execution;
              activeVPNClients = getActiveClients (builtins.attrNames cfg.vpn) cfg.vpn;
            in
            {
              options.homestakeros = homestakerosOptions;

              config = mkMerge [
                (mkIf true {
                  nixpkgs.overlays = [
                    ethereum-nix.overlays.default
                    outputs.overlays.additions
                    outputs.overlays.modifications
                  ];
                })
                ################################################################### LOCALIZATION
                (mkIf true {
                  networking.hostName = cfg.localization.hostname;
                  time.timeZone = cfg.localization.timezone;
                })

                #################################################################### MOUNTS
                (mkIf true {
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
                })

                #################################################################### SSH (system level)
                (mkIf true {
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
                })

                #################################################################### MOTD (no options)
                (mkIf true {
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
                })

                #################################################################### WIREGUARD
                (mkIf (cfg.vpn.wireguard.enable) {
                  networking.wg-quick.interfaces.${cfg.vpn.wireguard.interfaceName}.configFile = cfg.vpn.wireguard.configFile;
                })

                #################################################################### ERIGON
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
                        --datadir=${cfg.execution.erigon.dataDir} \
                        --chain mainnet \
                        --authrpc.vhosts="*" \
                        --authrpc.port ${local.erigon.parsedEndpoint.port} \
                        --authrpc.addr ${local.erigon.parsedEndpoint.addr} \
                        ${if cfg.execution.erigon.jwtSecretFile != null then
                          "--authrpc.jwtsecret=${cfg.execution.erigon.jwtSecretFile}"
                        else ""} \
                        --metrics
                      '';

                      wantedBy = [ "multi-user.target" ];
                    };

                    networking.firewall = {
                      allowedTCPPorts = [ 30303 30304 42069 ];
                      allowedUDPPorts = [ 30303 30304 42069 ];
                    };
                  }
                )

                #################################################################### MEV-BOOST
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
                      -addr ${local.mev-boost.parsedEndpoint.addr}:${local.mev-boost.parsedEndpoint.port}
                    '';

                      wantedBy = [ "multi-user.target" ];
                    };
                  }
                )

                #################################################################### LIGHTHOUSE
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
                      --http --http-address ${local.lighthouse.parsedEndpoint.addr} \
                      --http-port ${local.lighthouse.parsedEndpoint.port} \
                      --http-allow-origin "*" \
                      ${if cfg.consensus.lighthouse.execEndpoint != null then
                        "--execution-endpoint ${cfg.consensus.lighthouse.execEndpoint}"
                      else "" } \
                      ${if cfg.addons.mev-boost.enable then
                        "--builder ${cfg.addons.mev-boost.endpoint}"
                      else "" } \
                      ${if cfg.consensus.lighthouse.jwtSecretFile != null then
                        "--execution-jwt ${cfg.consensus.lighthouse.jwtSecretFile}"
                      else ""} \
                      --prune-payloads false \
                      --metrics \
                      ${if cfg.consensus.lighthouse.slasher.enable then
                        "--slasher "
                        + " --slasher-history-length " + (toString cfg.consensus.lighthouse.slasher.historyLength)
                        + " --slasher-max-db-size " + (toString cfg.consensus.lighthouse.slasher.maxDatabaseSize)
                      else "" }
                    '';
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
              ];
            };
        };
    };
}
