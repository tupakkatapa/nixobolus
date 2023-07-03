{ config, lib, pkgs, modulesPath, ... }:
{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      availableKernelModules = [ "squashfs" "overlay" "btrfs" ];
      kernelModules = [ "loop" "overlay" ];
    };

    postBootCommands = ''
      # After booting, register the contents of the Nix store in the Nix database in the tmpfs.
      ${config.nix.package}/bin/nix-store --load-db < /nix/store/nix-path-registration
      # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
      touch /etc/NIXOS
      ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
    '';
  };

  fileSystems = {
    "/" = lib.mkImageMediaOverride {
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };

    "/nix/.ro-store" = lib.mkImageMediaOverride {
      fsType = "squashfs";
      device = "../nix-store.squashfs";
      options = [ "loop" ];
      neededForBoot = true;
    };

    "/nix/.rw-store" = lib.mkImageMediaOverride {
      fsType = "tmpfs";
      options = [ "mode=0755" ];
      neededForBoot = true;
    };

    "/nix/store" = lib.mkImageMediaOverride {
      fsType = "overlay";
      device = "overlay";
      options = [
        "lowerdir=/nix/.ro-store"
        "upperdir=/nix/.rw-store/store"
        "workdir=/nix/.rw-store/work"
      ];
      depends = [
        "/nix/.ro-store"
        "/nix/.rw-store/store"
        "/nix/.rw-store/work"
      ];
    };
  };

  system.build = rec {
    # Create the squashfs image that contains the Nix store.
    squashfsStore = pkgs.callPackage "${toString modulesPath}/../lib/make-squashfs.nix" {
      # Closures to be copied to the Nix store, namely the init
      # script and the top-level system configuration directory.
      storeContents = [ config.system.build.toplevel ];
    };

    # Create the initrd
    netbootRamdisk = pkgs.makeInitrdNG {
      compressor = "zstd";
      prepend = [ "${config.system.build.initialRamdisk}/initrd" ];
      contents = [{
        object = config.system.build.squashfsStore;
        symlink = "/nix-store.squashfs";
      }];
    };

    # Create ipxe script
    netbootIpxeScript = pkgs.writeText "netboot.ipxe"
      ''
        #!ipxe
        # Use the cmdline variable to allow the user to specify custom kernel params
        # when chainloading this script from other iPXE scripts like netboot.xyz
        kernel ${pkgs.stdenv.hostPlatform.linux-kernel.target} init=${config.system.build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams} ''${cmdline}
        initrd initrd
        boot
      '';

    # A script invoking kexec on ./bzImage and ./initrd.gz.
    # Usually used through system.build.kexecTree, but exposed here for composability.
    kexecScript = pkgs.writeScript "kexec-boot"
      ''
        #!/usr/bin/env bash
        if ! kexec -v >/dev/null 2>&1; then
          echo "kexec not found: please install kexec-tools" 2>&1
          exit 1
        fi
        SCRIPT_DIR=$( cd -- "$( dirname -- "''${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
        kexec --load ''${SCRIPT_DIR}/bzImage \
          --initrd=''${SCRIPT_DIR}/initrd.gz \
          --command-line "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
        systemctl kexec
      '';

    # A tree containing initrd.gz, bzImage, ipxe and a kexec-boot script.
    kexecTree = pkgs.linkFarm "kexec-tree" [
      {
        name = "initrd";
        path = "${config.system.build.netbootRamdisk}/initrd";
      }
      {
        name = "bzImage";
        path = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      }
      {
        name = "kexec-boot";
        path = config.system.build.kexecScript;
      }
      {
        name = "netboot.ipxe";
        path = config.system.build.netbootIpxeScript;
      }
    ];
  };
}
