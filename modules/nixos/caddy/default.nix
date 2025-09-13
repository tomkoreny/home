{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable Caddy web server
  services.caddy = {
    enable = true;
    
    # Use configFile to point to a runtime-generated config
    configFile = pkgs.writeText "Caddyfile" ''
      {
        log {
          level ERROR
        }
      }
      
      import /home/tom/.infrastructure-as-ruby/caddyfiles/*.caddy
    '';
  };

  # Open firewall for HTTP and HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Trust certificates from infrastructure-as-ruby
  # For now, we'll handle certificate trust manually or via a separate mechanism
  # security.pki.certificateFiles = [];

  # Run Caddy as tom user
  systemd.services.caddy = {
    serviceConfig = {
      # Run as tom user and group
      User = lib.mkForce "tom";
      Group = lib.mkForce "users";
      
      # Disable sandboxing to allow reading from home directory
      ProtectHome = lib.mkForce false;
      
      # Allow binding to privileged ports while running as regular user
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      
      # Set working directory to tom's home
      WorkingDirectory = lib.mkForce "/home/tom";
      
      # Disable PrivateTmp to ensure file access
      PrivateTmp = lib.mkForce false;
      
      # Create state directory for tom
      StateDirectory = lib.mkForce "caddy-tom";
      StateDirectoryMode = lib.mkForce "0700";
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}