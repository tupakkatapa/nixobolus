# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{
  description = "Nixobolus flake";

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
  };

  outputs = { self, nixpkgs, home-manager, nixos-generators, ethereum-nix, ... }@inputs:

    let
      inherit (self) outputs;
      system = "x86_64-linux";
      forEachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      # get hostnames from ./nix_configs/hosts
      ls = builtins.readDir ./nix_configs/hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # overlays
      overlays = [ ethereum-nix.overlays.default ];
      pkgs = import nixpkgs { inherit system overlays; };

      # custom formats for nixos-generators
      customFormats = {
        "kexecTree" = { 
          formatAttr = "kexecTree";
          imports = [ ./nix_configs/common/netboot.nix ]; 
        };
      };
    in {
      # devshell for bootstrapping
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nixos-generators
      packages.${system} = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixos-generators.nixosGenerate {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./nix_configs/hosts/${hostname} ];
          customFormats = customFormats;
          format = "kexecTree";
        };
      }) hostnames);

      # nixos configuration entrypoints
      nixosConfigurations = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixpkgs.lib.nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./nix_configs/hosts/${hostname} ];
        };
      }) hostnames);
    };
}