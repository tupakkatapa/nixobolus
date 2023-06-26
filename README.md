# Nixobolus
Automated creation of bootable NixOS images

## About
This project currently functions as the backend for [HomestakerOS](https://github.com/ponkila/HomestakerOS), a Web UI designed to generate an integrated network of ephemeral Linux servers. Additionally, this provides modules for our Ethereum [homestaking-infra](https://github.com/ponkila/homestaking-infra) to ensure that everything remain up-to-date and optimized. This project utilizes [ethereum.nix](https://github.com/nix-community/ethereum.nix), which provides an up-to-date package management solution for Ethereum clients.

As you can see, we are kicking things off by focusing on Ethereum-related stuff, but this has the potential to be used for the deployment and maintenance of any kind of infrastructure.

## Usage as module

To use Nixobolus as a module in your NixOS configuration, you can follow the example provided below. For a more practical example, you can refer to our homestaking-infra repository. It provides an implementation of the module and demonstrates its usage in a real scenario.

```nix
{
  inputs.nixobolus.url = "github:ponkila/nixobolus";

  outputs = { self, nixpkgs, nixobolus }: {
    # change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      # customize to your system
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixobolus.nixosModules.homestakeros
      ];
    };
  };
}
```