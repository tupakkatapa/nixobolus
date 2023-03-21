# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{
  description = "Nixobolus 2000";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ethereum.nix
    ethereum-nix = {
      url = "github:nix-community/ethereum.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-generators
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # arguments
    args = {
      hostname = "nixobolus";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-generators, ethereum-nix, args, ... }@inputs:
    let
      inherit (self) outputs;
      hostname = args.hostname;
      system = "x86_64-linux";
      forEachSystem = nixpkgs.lib.genAttrs [ system ];
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      # overlays
      overlays = [ ethereum-nix.overlays.default ];
      pkgs = import nixpkgs { inherit system overlays; };

      # custom formats for nixos-generators
      customFormats = {
            "kexecTree" = { 
              formatAttr = "kexecTree";
              imports = [ ./configs/nix_configs/common/netboot.nix ]; 
            };
      };
    in
    rec {
      #overlays = import ./overlays { inherit inputs; };
      #nixosModules = import ./modules/nixos;
      #homeManagerModules = import ./modules/home-manager;
      
      # devshell for bootstrapping
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nixos-generators
      packages.${system} = {
        nixobolus = nixos-generators.nixosGenerate {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./configs/nix_configs/hosts/${hostname} ];
          customFormats = customFormats;
          format = "kexecTree";
        };
      };

      # nixos configuration entrypoint
      nixosConfigurations = {
        nixobolus = nixpkgs.lib.nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./configs/nix_configs/hosts/${hostname} ];
        };
      };
    };
}