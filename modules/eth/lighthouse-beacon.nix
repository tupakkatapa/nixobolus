{ pkgs, config, lib, ... }:
let
  options = {
    enable = false;
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
in
{

  config = lib.mkIf options.enable {
    # package
    environment.systemPackages = with pkgs; [
      lighthouse
    ];

    # service
    systemd.user.services.lighthouse = {
      enable = true;

      description = "beacon, mainnet";
      requires = [ "wg0.service" ];
      after = [ "wg0.service" "mev-boost.service" ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        Type = "simple";
      };

      script = ''${pkgs.lighthouse}/bin/lighthouse bn \
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
}

