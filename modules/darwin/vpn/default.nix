{
  config,
  lib,
  pkgs,
  ...
}: let
  vpnScriptSrc = ../../../scripts/vpn/openfortivpn.sh;
  vpnScript = pkgs.writeShellScriptBin "openfortivpn-connect" (builtins.readFile vpnScriptSrc);
  secretName = "openfortivpn";
  secretPath = "/var/run/openfortivpn.conf";
in {
  environment.systemPackages = [
    pkgs.openfortivpn
    vpnScript
  ];

  sops.secrets.${secretName} = {
    sopsFile = ../../../secrets/vpn/openfortivpn.conf;
    format = "binary";
    owner = "root";
    group = "wheel";
    mode = "0400";
    path = secretPath;
  };

  launchd.daemons.openfortivpn = {
    command = "${vpnScript}/bin/openfortivpn-connect";
    environment = {
      OPENFORTIVPN_BIN = lib.getExe pkgs.openfortivpn;
      OPENFORTIVPN_CONFIG = config.sops.secrets.${secretName}.path;
    };
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/openfortivpn.log";
      StandardErrorPath = "/var/log/openfortivpn.log";
    };
  };
}
