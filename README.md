# Nixobolus
Automated creation of bootable NixOS images

## About
This project currently functions as the backend for [HomestakerOS](https://github.com/ponkila/HomestakerOS), a Web UI designed to generate an integrated network of ephemeral Linux servers. Additionally, this provides modules for our Ethereum [homestaking-infra](https://github.com/ponkila/homestaking-infra) to ensure that everything remain up-to-date and optimized.

As you can see, we are kicking things off by focusing on Ethereum-related stuff, but this has the potential to be used for the deployment and maintenance of any kind of infrastructure.

## Usage as module

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