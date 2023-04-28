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

      # custom packages
      # acessible through 'nix build', 'nix shell', etc
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});
      packages = forEachPkgs (pkgs: import ./pkgs { inherit pkgs; });

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

      # Erigon
      # TODO -- import
      erigon = rec {

        options = {
          enable = false;
          user = "";
          endpoint = "";
          datadir = "";
        };

        config = nixpkgs.lib.mkIf options.enable {
          # package
          environment.systemPackages = with packages; [
            erigon
          ];

          # service
          systemd.services.erigon = {
            enable = true;

            description = "execution, mainnet";
            requires = [ "wg0.service" ];
            after = [ "wg0.service" "lighthouse.service" ];

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              User = options.user;
              Group = options.user;
              Type = "simple";
            };

            script = ''${packages.erigon}/bin/erigon \
              --datadir=${options.datadir} \
              --chain mainnet \
              --authrpc.vhosts="*" \
              --authrpc.addr ${options.endpoint} \
              --authrpc.jwtsecret=${options.datadir}/jwt.hex \
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
        };
      };

      # Erigon
      # TODO -- import
      lighthouse = rec {

        options = {
          enable = false;
          user = "";
          endpoint = "";
          datadir = "";
          exec.endpoint = "";
          slasher = {
            enable = false;
            history-length = 4096;
            max-db-size = 256;
          };
          mev-boost = {
            endpoint = "";
          };
        };

        config = nixpkgs.lib.mkIf options.enable {
          # package
          environment.systemPackages = with packages; [
            lighthouse
          ];

          # service
          systemd.services.lighthouse = {
            enable = true;

            description = "beacon, mainnet";
            requires = [ "wg0.service" ];
            after = [ "wg0.service" "mev-boost.service" ];

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              User = options.user;
              Group = options.user;
              Type = "simple";
            };

            script = ''${packages.lighthouse}/bin/lighthouse bn \
              --datadir ${options.datadir} \
              --network mainnet \
              --http --http-address ${options.endpoint} \
              --execution-endpoint ${options.exec.endpoint} \
              --execution-jwt ${options.datadir}/jwt.hex \
              --builder ${options.mev-boost.endpoint} \
              --prune-payloads false \
              --metrics \
              ${if options.slasher.enable then
                "--slasher "
                + " --slasher-history-length " + (toString options.slasher.history-length)
                + " --slasher-max-db-size " + (toString options.slasher.max-db-size)
              else "" }
            '';
            wantedBy = [ "multi-user.target" ];
          };

          # firewall
          networking.firewall = {
            allowedTCPPorts = [ 9000 ];
            allowedUDPPorts = [ 9000 ];
            interfaces."wg0".allowedTCPPorts = [
              5052 # lighthouse
            ];
          };
        };
      };

      # Mev-boost
      # TODO -- import
      mev-boost = rec {

        options = {
          enable = false;
          user = "";
        };

        config = nixpkgs.lib.mkIf options.enable {
          virtualisation.podman.enable = true;
          # dnsname allows containers to use ${name}.dns.podman to reach each other
          # on the same host instead of using hard-coded IPs.
          # NOTE: --net must be the same on the containers, and not eq "host"
          # TODO: extend this with flannel ontop of wireguard for cross-node comms
          virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

          systemd.services.mev-boost = {
            path = [ "/run/wrappers" ];
            enable = true;

            description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
            requires = [ "wg0.service" ];
            after = [ "wg0.service" ];

            serviceConfig = {
              Restart = "always";
              RestartSec = "5s";
              User = options.user;
              Group = options.user;
              Type = "simple";
            };

            preStart = "${packages.podman}/bin/podman stop mev-boost || true";
            script = ''${packages.podman}/bin/podman \
                --storage-opt "overlay.mount_program=${packages.fuse-overlayfs}/bin/fuse-overlayfs" run \
                --replace --rmi \
                --name mev-boost \
                -p 18550:18550 \
                docker.io/flashbots/mev-boost:latest \
                -mainnet \
                -relay-check \
                -relays ${nixpkgs.lib.concatStringsSep "," [
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
        };
      };
      # nixos configuration entrypoints (needed for accessing options through eval)
      # available through 'nix-build .#your-hostname'
      # TODO -- only maps x86_64-linux at the moment 
      nixosConfigurations = builtins.listToAttrs (map
        (hostname: {
          name = hostname;
          value = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            inherit sharedModules;
            specialArgs = { inherit inputs outputs; };
            modules = [ ./hosts/${hostname} ] ++ sharedModules;
          };
        })
        hostnames);

      # option extraction -- accessible through 'nix eval .#exports.<name>.options'
      exports = {
        erigon = erigon;
        lighthouse = lighthouse;
        mev-boost = mev-boost;
      };

      # generate nixosModules exports dynamically
      # usage -- https://github.com/ponkila/homestaking-infra/commit/574382212cf817dbb75657e9fef9cdb223e9823b
      nixosModules = builtins.mapAttrs
        (name: module: { config, lib, pkgs, ... }:
          { inherit module; }
        )
        exports;
    };
}
