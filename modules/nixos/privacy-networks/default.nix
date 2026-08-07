{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.privacy-networks;
  secretName = "yggdrasil-private-key";
in
{
  options.tomkoreny.nixos.privacy-networks = {
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
    environment.systemPackages = [ pkgs.yggdrasil ];

    services.i2pd = {
      enable = true;
      proto = {
        http.enable = true;
        httpProxy.enable = true;
        socksProxy.enable = true;
      };
    };

    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/yggdrasil/nixos-private.pem;
      format = "binary";
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "yggdrasil.service" ];
    };

    services.yggdrasil = {
      enable = true;
      settings = {
        AdminListen = "unix:///run/yggdrasil/yggdrasil.sock";
        Peers = cfg.yggdrasilPeers;
        PrivateKeyPath = config.sops.secrets.${secretName}.path;
        NodeInfoPrivacy = true;
      };
    };
  };
}
