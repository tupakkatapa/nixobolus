# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

{
  description = "Nixobolus flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # sops-nix
    sops-nix.url = "github:Mic92/sops-nix";

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

    # disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # darwin
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # overrides
    overrides.url = "path:./overrides";
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
    , sops-nix
    , overrides
    }@inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";

      # custom packages
      # acessible through 'nix build', 'nix shell', etc
      forEachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});
      packages = forEachPkgs (pkgs: import ./configs/nix_configs/pkgs { inherit pkgs; });

      # get hostnames from ./nix_configs/hosts
      ls = builtins.readDir ./configs/nix_configs/hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # overlays
      overlays = [ ethereum-nix.overlays.default ];
      pkgs = import nixpkgs { inherit system overlays; };

      # custom formats for nixos-generators
      # other available formats can be found at: https://github.com/nix-community/nixos-generators/tree/master/formats
      customFormats = {
        "kexecTree" = { 
          formatAttr = "kexecTree";
          imports = [ ./configs/nix_configs/common/netboot.nix ]; 
        };
      };
    in {
      # devshell for bootstrapping
      # acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nixos-generators
      # available through 'nix-build .#your-hostname'
      packages.${system} = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixos-generators.nixosGenerate {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./configs/nix_configs/hosts/${hostname} ];
          customFormats = customFormats;
          format = "kexecTree";
        };
      }) hostnames);

      # nixos configuration entrypoints
      # available through 'nix-build .#your-hostname'
      nixosConfigurations = builtins.listToAttrs (map (hostname: {
        name = hostname;
        value = nixpkgs.lib.nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs outputs; };
          modules = [ ./configs/nix_configs/hosts/${hostname} ];
        };
      }) hostnames);
    };
}