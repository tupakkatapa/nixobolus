{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.ssh;
in
{
  options.ssh = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    privateKeyPath = mkOption {
      type = types.str;
    };
  };

  config = mkIf cfg.enable {
    # SSH
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      hostKeys = [{
        path = ssh.privateKeyPath;
        type = "ed25519";
      }];
    };
  };
}
