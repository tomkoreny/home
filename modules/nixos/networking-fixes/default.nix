{...}: {
  # Additional networking fixes for connection stability
  networking = {
    # Increase network buffer sizes to prevent connection resets
    dhcpcd.extraConfig = ''
      noarp
      noipv6rs
    '';
    
    # Enable TCP optimizations
    firewall = {
      enable = true;
      allowPing = true;
      # Allow common ports to prevent connection issues
      allowedTCPPorts = [ 80 443 ];
      # TCP/IP stack tuning
      extraCommands = ''
        # Increase TCP buffer sizes
        sysctl -w net.core.rmem_max=134217728
        sysctl -w net.core.wmem_max=134217728
        sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
        sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
        
        # TCP keepalive settings to detect dead connections
        sysctl -w net.ipv4.tcp_keepalive_time=60
        sysctl -w net.ipv4.tcp_keepalive_intvl=10
        sysctl -w net.ipv4.tcp_keepalive_probes=6
        
        # Disable TCP timestamps (can cause issues with some routers)
        sysctl -w net.ipv4.tcp_timestamps=0
        
        # Increase connection tracking limits
        sysctl -w net.netfilter.nf_conntrack_max=131072
      '';
    };
  };
  
  # System-wide TCP tuning via sysctl
  boot.kernel.sysctl = {
    # TCP optimization
    "net.ipv4.tcp_congestion" = "bbr";
    "net.ipv4.tcp_notsent_lowat" = 16384;
    "net.ipv4.tcp_fastopen" = 3;
    
    # Connection tracking
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 432000;
    "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;
    
    # Buffer sizes
    "net.core.netdev_max_backlog" = 5000;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    
    # Disable IPv6 if not needed (can cause dual-stack issues)
    # Uncomment if you don't use IPv6:
    # "net.ipv6.conf.all.disable_ipv6" = 1;
    # "net.ipv6.conf.default.disable_ipv6" = 1;
  };
}