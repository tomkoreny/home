{
  config,
  lib,
  ...
}: let
  cfg = config.tomkoreny.nixos.networking-fixes;
in {
  options.tomkoreny.nixos.networking-fixes = {
    enable = lib.mkEnableOption "TCP tuning and connection-stability fixes";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = {
      enable = true;
      allowPing = true;
    };

    # Load these at boot so the sysctls below can apply.
    boot.kernelModules = [
      "tcp_bbr"
      "nf_conntrack"
    ];

    boot.kernel.sysctl = {
      # Increase TCP buffer sizes to prevent connection resets
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 87380 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";

      # TCP keepalive settings to detect dead connections
      "net.ipv4.tcp_keepalive_time" = 60;
      "net.ipv4.tcp_keepalive_intvl" = 10;
      "net.ipv4.tcp_keepalive_probes" = 6;

      # Disable TCP timestamps (can cause issues with some routers)
      "net.ipv4.tcp_timestamps" = 0;

      # TCP optimization
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_notsent_lowat" = 16384;
      "net.ipv4.tcp_fastopen" = 3;

      # Connection tracking
      "net.netfilter.nf_conntrack_max" = 131072;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 432000;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;

      # Backlogs
      "net.core.netdev_max_backlog" = 5000;
      "net.ipv4.tcp_max_syn_backlog" = 8192;
    };
  };
}
