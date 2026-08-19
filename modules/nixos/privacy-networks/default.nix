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

    # nixpkgs rewrote this module around a freeform `settings` attrset and
    # dropped `proto.*` without a rename. The three protocols that block used to
    # turn on (webconsole, HTTP proxy, SOCKS proxy) are `http.enabled`,
    # `httpproxy.enabled` and `socksproxy.enabled`, all of which the module now
    # defaults to true, so enabling the service is enough.
    services.i2pd.enable = true;

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
