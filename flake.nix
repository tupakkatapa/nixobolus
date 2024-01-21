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
    devenv.url = "github:cachix/devenv";
    ethereum-nix.url = "github:nix-community/ethereum.nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    ethereum-nix,
    flake-parts,
    nixpkgs,
    nixpkgs-stable,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} rec {
      systems = nixpkgs.lib.systems.flakeExposed;
      imports = [
        inputs.devenv.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      perSystem = {
        pkgs,
        lib,
        config,
        system,
        ...
      }: {
        # Overlays
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
          config = {};
        };
        overlayAttrs = {
          inherit (config.packages) buidl nethermind nimbus prysm reth ssvnode teku homestakeros;
        };

        # Nix code formatter, accessible through 'nix fmt'
        formatter = nixpkgs.legacyPackages.${system}.alejandra;

        # Development shell
        # Accessible trough 'nix develop .# --impure' or 'direnv allow'
        devenv.shells = {
          default = {
            env = {
              NIX_CONFIG = ''
                accept-flake-config = true
                extra-experimental-features = flakes nix-command
                warn-dirty = false
              '';
            };
            pre-commit.hooks = {
              alejandra.enable = true;
              shellcheck.enable = true;
            };
            # Workaround for https://github.com/cachix/devenv/issues/760
            containers = pkgs.lib.mkForce {};
          };
        };

        # Custom packages, accessible trough 'nix build', 'nix run', etc.
        packages =
          rec {
            "buidl" = pkgs.callPackage ./packages/buidl {};
            # Ethereum.nix
            "nethermind" = inputs.ethereum-nix.packages.${system}.nethermind;
            "nimbus" = inputs.ethereum-nix.packages.${system}.nimbus;
            "prysm" = inputs.ethereum-nix.packages.${system}.prysm;
            "reth" = inputs.ethereum-nix.packages.${system}.reth;
            "ssvnode" = inputs.ethereum-nix.packages.${system}.ssvnode;
            "teku" = inputs.ethereum-nix.packages.${system}.teku;
          }
          # Entrypoint aliases, accessible trough 'nix build'
          // (with flake.nixosConfigurations; {
            "homestakeros" = homestakeros.config.system.build.kexecTree;
          });
      };
      flake = let
        inherit (self) outputs;

        homestakeros = {
          system = "x86_64-linux";
          specialArgs = {inherit inputs outputs;};
          modules =
            [
              self.nixosModules.kexecTree
              self.nixosModules.homestakeros
              {
                boot.loader.grub.enable = false;
                system.stateVersion = "23.11";
              }
            ]
            ++ nixpkgs.lib.optional (builtins.pathExists /tmp/data.nix) /tmp/data.nix;
        };

        # Function to format module options
        parseOpts = options:
          nixpkgs.lib.attrsets.mapAttrsRecursiveCond (v: ! nixpkgs.lib.options.isOption v)
          (k: v: {
            type = v.type.name;
            default = v.default;
            description =
              if v ? description
              then v.description
              else null;
            example =
              if v ? example
              then v.example
              else null;
          })
          options;

        # Function to get options from module(s)
        getOpts = modules:
          builtins.removeAttrs
          (nixpkgs.lib.evalModules {
            inherit modules;
            specialArgs = {inherit nixpkgs;};
          })
          .options ["_module"];
      in {
        # HomestakerOS module for Ethereum-related components
        # A accessible through 'nix eval --json .#exports'
        nixosModules.homestakeros = {
          imports = [
            ./modules/homestakeros
            ./modules/homestakeros/system.nix
          ];
        };

        # Module option exports for the frontend
        # Accessible through 'nix eval --json .#exports'
        exports = parseOpts (getOpts [
          ./modules/homestakeros/options.nix
        ]);

        # NixOS configuration entrypoints for the frontend
        nixosConfigurations = with nixpkgs.lib; {
          "homestakeros" = nixosSystem homestakeros;
        };

        # Format modules
        nixosModules.isoImage = {
          imports = [./modules/copytoram-iso.nix];
        };
        nixosModules.kexecTree = {
          imports = [./modules/netboot-kexec.nix];
        };
      };
    };
}
