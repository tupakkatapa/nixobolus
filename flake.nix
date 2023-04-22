{
  description = "Nixobolus flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # nix-sops
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
    }@inputs:

    let
      inherit (self) outputs;
      forEachSystem = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      system = "x86_64-linux";

      # custom packages
      # acessible through 'nix build', 'nix shell', etc
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});
      packages = forEachPkgs (pkgs: import ./pkgs { inherit pkgs; });

      # get hostnames from ./nix_configs/hosts
      ls = builtins.readDir ./hosts;
      hostnames = builtins.filter
        (name: builtins.hasAttr name ls && (ls.${name} == "directory"))
        (builtins.attrNames ls);

      # overlays
      overlays = import ./overlays { inherit inputs; };

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
    in
    {
      # devshell for bootstrapping
      # acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # nix fmt
      formatter = forEachPkgs (pkgs: pkgs.nixpkgs-fmt);

      # nixos-generators
      # available through 'nix build .#your-hostname'
      packages.${system} = builtins.listToAttrs (map
        (hostname: {
          name = hostname;
          value = nixos-generators.nixosGenerate {
            inherit system;
            specialArgs = { inherit inputs outputs; };
              {
                nixpkgs.overlays = [
                  ethereum-nix.overlays.default
                ];
              }
            customFormats = customFormats;
            format = "netboot-kexec";
          };
        })
        hostnames);
    };
}
