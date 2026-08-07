{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.privacy-networks;
  common = import ../../../lib/common { };
  homeDir = common.user.homeDir { isDarwin = true; };

  secretName = "yggdrasil-private-key";
  secretPath = "/etc/yggdrasil-private-key.pem";

  i2pdDataDir = "${homeDir}/Library/Application Support/i2pd";
  i2pdConfig = pkgs.writeText "i2pd.conf" ''
    daemon = false
    ipv4 = true
    ipv6 = true
    nat = true
    log = stdout

    [http]
    enabled = true
    address = 127.0.0.1
    port = 7070

    [httpproxy]
    enabled = true
    address = 127.0.0.1
    port = 4444

    [socksproxy]
    enabled = true
    address = 127.0.0.1
    port = 4447
  '';
  i2pdStart = pkgs.writeShellScript "start-i2pd" ''
    set -euo pipefail
    mkdir -p ${lib.escapeShellArg i2pdDataDir}
    exec ${lib.getExe pkgs.i2pd} \
      --datadir=${lib.escapeShellArg i2pdDataDir} \
      --conf=${i2pdConfig}
  '';

  yggdrasilConfig = pkgs.writeText "yggdrasil.conf" (
    builtins.toJSON {
      AdminListen = "unix:///var/run/yggdrasil.sock";
      Peers = cfg.yggdrasilPeers;
      PrivateKeyPath = secretPath;
      NodeInfoPrivacy = true;
    }
  );
in
{
  options.tomkoreny.darwin.privacy-networks = {
    enable = lib.mkEnableOption "I2P and Yggdrasil overlay networks";

    yggdrasilPeers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "tls://marisa.nadeko.net:44442"
        "tls://ygg-dc.lxak.net:8880"
      ];
      description = "Outbound Yggdrasil peer URIs";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.i2pd
      pkgs.yggdrasil
    ];

    launchd.user.agents.i2pd = {
      command = "${i2pdStart}";
      serviceConfig = {
        KeepAlive = {
          NetworkState = true;
          SuccessfulExit = false;
        };
        ProcessType = "Background";
        RunAtLoad = true;
        StandardOutPath = "${homeDir}/Library/Logs/i2pd.log";
        StandardErrorPath = "${homeDir}/Library/Logs/i2pd.log";
      };
    };

    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/yggdrasil/macos-private.pem;
      format = "binary";
      owner = "root";
      group = "wheel";
      mode = "0400";
      path = secretPath;
    };

    launchd.daemons.yggdrasil = {
      command = "${lib.getExe pkgs.yggdrasil} -useconffile ${yggdrasilConfig}";
      serviceConfig = {
        KeepAlive = {
          NetworkState = true;
          SuccessfulExit = false;
        };
        ProcessType = "Background";
        RunAtLoad = true;
        StandardOutPath = "/var/log/yggdrasil.log";
        StandardErrorPath = "/var/log/yggdrasil.log";
      };
    };
  };
}
