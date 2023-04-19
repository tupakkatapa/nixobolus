
services.prometheus = {
  enable = false;
  port = 9001;
  exporters = {
    node = {
      enable = false;
      enabledCollectors = [ "systemd" ];
      port = 9002;
    };
  };
  scrapeConfigs = [
    {
      job_name = config.networking.hostName;
      static_configs = [{
        targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
      }];
    }
    {
      job_name = "erigon";
      metrics_path = "/debug/metrics/prometheus";
      scheme = "http";
      static_configs = [{
        targets = [ "127.0.0.1:6060" "127.0.0.1:6061" "127.0.0.1:6062" ];
      }];
    }
    {
      job_name = "lighthouse";
      scrape_interval = "5s";
      static_configs = [{
        targets = [ "127.0.0.1:5054" "127.0.0.1:5064" ];
      }];
    }
  ];
};