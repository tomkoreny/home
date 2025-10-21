{
  config,
  lib,
  pkgs,
  ...
}: let
  vpnScriptSrc = ../../../scripts/vpn/openfortivpn.sh;
  vpnScript = pkgs.writeShellScriptBin "openfortivpn-connect" (builtins.readFile vpnScriptSrc);
  secretName = "openfortivpn";
  secretPath = "/run/openfortivpn.conf";
in {
  # Expose the helper script and openfortivpn client system-wide.
  environment.systemPackages = [
    pkgs.openfortivpn
    vpnScript
  ];

  # Provide the FortiVPN configuration via sops-nix.
  sops.secrets.${secretName} = {
    sopsFile = ../../../secrets/vpn/openfortivpn.conf;
    format = "binary";
    owner = "root";
    group = "root";
    mode = "0400";
    path = secretPath;
    restartUnits = [ "openfortivpn.service" ];
  };

  # Systemd service that keeps the VPN connection alive.
  systemd.services.openfortivpn = {
    description = "OpenFortiVPN persistent tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      OPENFORTIVPN_BIN = lib.getExe pkgs.openfortivpn;
      OPENFORTIVPN_CONFIG = config.sops.secrets.${secretName}.path;
    };
    serviceConfig = {
      ExecStart = "${vpnScript}/bin/openfortivpn-connect";
      Restart = "on-failure";
      RestartSec = "10s";
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
      NoNewPrivileges = true;
    };
  };

  # Pre-clean any conflicting /run/secrets directory before sops installs the new symlink.
  # No additional activation logic required.
}
