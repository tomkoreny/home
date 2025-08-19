{
  config,
  lib,
  pkgs,
  ...
}: 
let
  certDir = "/home/tom/.infrastructure-as-ruby/certs";
  caddyfilesDir = "/home/tom/.infrastructure-as-ruby/caddyfiles";
  
  # Read Caddyfiles at build time since import doesn't work with sandboxing
  caddyfileContents = 
    if builtins.pathExists caddyfilesDir then
      let
        files = builtins.readDir caddyfilesDir;
        caddyFiles = lib.filterAttrs (name: type: 
          type == "regular" && lib.hasSuffix ".caddy" name
        ) files;
        contents = lib.mapAttrsToList (name: _: 
          builtins.readFile "${caddyfilesDir}/${name}"
        ) caddyFiles;
      in
        lib.concatStringsSep "\n\n" contents
    else
      "";
in {
  # Enable Caddy web server
  services.caddy = {
    enable = true;
    
    # Don't use extraConfig directly as it may be duplicated
    # Instead, write a custom Caddyfile
    configFile = pkgs.writeText "Caddyfile" ''
      {
        log {
          level ERROR
        }
      }
      
      ${caddyfileContents}
    '';
  };

  # Open firewall for HTTP and HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Trust certificates from infrastructure-as-ruby
  # For now, we'll handle certificate trust manually or via a separate mechanism
  # security.pki.certificateFiles = [];

  # Ensure Caddy can read the configuration files
  systemd.services.caddy = {
    serviceConfig = {
      # Disable sandboxing to allow reading from home directory
      ProtectHome = lib.mkForce "read-only";
      # Allow binding to privileged ports while running as regular user
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}