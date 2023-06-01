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
    #nixobolus.url = "github:ponkila/nixobolus";
    nixobolus.url = "path:./modules/homestakeros";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , ethereum-nix
    , flake-parts
    , home-manager
    , nixobolus
    , nixpkgs
    , nixpkgs-stable
    , sops-nix
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
              sops
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

          homestakeros = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./system
              ./system/ramdisk.nix
              ./system/formats/netboot-kexec.nix
              nixobolus.nixosModules.homestakeros
              home-manager.nixosModules.home-manager
              disko.nixosModules.disko
              {
                nixpkgs.overlays = [
                  ethereum-nix.overlays.default
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
                home-manager.sharedModules = [
                  sops-nix.homeManagerModules.sops
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
            nixosModules.homestakeros.options;

          overlays = import ./overlays { inherit inputs; };

          nixosConfigurations = with nixpkgs.lib; {
            "homestakeros" = nixosSystem (getAttrs [ "system" "specialArgs" "modules" ] homestakeros);
          } // (with nixpkgs-stable.lib; { });

          nixosModules.homestakeros = with nixpkgs.lib; {
            imports = [ ./modules/homestakeros ];
            options = {
              localization = {
                hostname = mkOption {
                  type = types.str;
                  default = "homestaker";
                };
                timezone = mkOption {
                  type = types.str;
                  default = "Europe/Helsinki";
                };
              };

              mounts = mkOption {
                type = types.attrsOf types.string;
              };

              ssh = {
                privateKeyPath = mkOption {
                  type = types.path;
                  default = "/var/mnt/secrets/ssh/id_ed25519";
                };
              };

              user = {
                authorizedKeys = mkOption {
                  type = types.listOf types.singleLineStr;
                  default = [ ];
                };
              };

              erigon = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                };
                endpoint = mkOption {
                  type = types.str;
                };
                datadir = mkOption {
                  type = types.str;
                };
              };

              lighthouse = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                };
                endpoint = mkOption {
                  type = types.str;
                };
                exec.endpoint = mkOption {
                  type = types.str;
                };
                slasher = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                  };
                  history-length = mkOption {
                    type = types.int;
                    default = 4096;
                  };
                  max-db-size = mkOption {
                    type = types.int;
                    default = 256;
                  };
                };
                mev-boost = {
                  endpoint = mkOption {
                    type = types.str;
                  };
                };
                datadir = mkOption {
                  type = types.str;
                };
              };
            };
          };
        };
    };
}
