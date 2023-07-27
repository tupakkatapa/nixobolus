{
  description = "Nixobolus flake";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "http://buidl0.ponkila.com:5000"
      "http://buidl1.ponkila.com:5000"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "buidl0.ponkila.com:qJZUo9Aji8cTc0v6hIGqbWT8sy+IT/rmSKUFTfhVGGw="
      "buidl1.ponkila.com:ZIIETN3bdTS4DtymDmVGKqG6UOPy4gU89DPCfAKDcx8="
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
        # Nix code formatter, accessible through 'nix fmt'
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

        # Git hook scripts for identifying issues before submission
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
        # Do not perform hooks with 'nix flake check'
        pre-commit.check.enable = false;

        # Development tools for devshell
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
              paths = [ buidl-script ];
              buildInputs = with pkgs; [ nix makeWrapper ];
              postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
            };
        };
      };
      flake =
        let
          inherit (self) outputs;

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
              #     execution = {
              #       erigon.enable = true;
              #     };
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

          # Function to format module options
          parseOpts = options:
            nixpkgs.lib.attrsets.mapAttrsRecursiveCond (v: ! nixpkgs.lib.options.isOption v)
              (k: v: {
                type = v.type.name;
                default = v.default;
                description = if v ? description then v.description else null;
                example = if v ? example then v.example else null;
              })
              options;

          # Function to get options from module(s)
          getOpts = modules:
            builtins.removeAttrs (nixpkgs.lib.evalModules {
              inherit modules;
              specialArgs = { inherit nixpkgs; };
            }).options [ "_module" ];
        in
        rec {
          overlays = import ./overlays { inherit inputs; };

          # HomestakerOS module for Ethereum-related components
          # A accessible through 'nix eval --json .#exports'
          nixosModules.homestakeros = {
            imports = [ ./modules/homestakeros ];
            config = {
              nixpkgs.overlays = [
                ethereum-nix.overlays.default
                outputs.overlays.additions
                outputs.overlays.modifications
              ];
            };
          };

          # Module option exports for the frontend
          # Accessible through 'nix eval --json .#exports'
          exports = {
            homestakeros = parseOpts (
              getOpts [ ./modules/homestakeros/options.nix ]
            );
            # docs = nixpkgs.legacyPackages."aarch64-darwin".nixosOptionsDoc { 
            #    options = (getOpts [ ./modules/homestakeros/options.nix ]); 
            # };
          };

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
        };
    };
}
