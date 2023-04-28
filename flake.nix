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
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
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

      # modules that are used regardless of the host
      sharedModules = [
        # TODO -- lot of these "modules" should be at host config
        ./home-manager/staker.nix
        ./modules/eth
        ./system
        ./system/ramdisk.nix
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
        }
      ];
    in
    rec {
      # devshell -- accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forEachPkgs (pkgs: import ./shell.nix { inherit pkgs; });

      # custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # nix fmt
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
                inherit system customFormats;
                specialArgs = { inherit inputs outputs; };
                modules = [ ./hosts/${hostname} ] ++ sharedModules;
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
          value = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [ ./hosts/${hostname} ] ++ sharedModules;
          };
        })
        hostnames);

      # option extraction -- accessible through 'nix eval .#nixosConfigurations.<hostname>.config.<name>'
      # usege as module -- https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
      nixosModules = {
        erigon = import ./modules/eth/erigon.nix;
        lighthouse = import ./modules/eth/lighthouse-beacon.nix;
        mev-boost = import ./modules/eth/mev-boost.nix;
      };
    };
}
