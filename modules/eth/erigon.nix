{ pkgs, config, lib, ... }:
let
  options = {
    enable = false;
    user = "";
    endpoint = "";
    datadir = "";
  };
in
{
  config = lib.mkIf options.enable {
    # package
    environment.systemPackages = with pkgs; [
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

      script = ''${pkgs.erigon}/bin/erigon \
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
}

