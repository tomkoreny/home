{
  config,
  lib,
  ...
}:
# Persistent T-Mobile ACHO IPsec tunnel through strongSwan. The connection
# (scripts/vpn/tmobile.swanctl.conf) is shared with modules/darwin/vpn; the
# sops secret adds the PSK and the EAP login to it.
let
  cfg = config.tomkoreny.nixos.vpn;
  secretName = "tmobile-ipsec";
in
{
  options.tomkoreny.nixos.vpn = {
    enable = lib.mkEnableOption "persistent T-Mobile IPsec tunnel";
  };

  config = lib.mkIf cfg.enable {
    # swanctl on PATH for `sudo swanctl --list-sas` and manual (re)initiation.
    environment.systemPackages = [ config.services.strongswan-swanctl.package ];

    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/vpn/tmobile-ipsec.conf;
      format = "binary";
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "strongswan-swanctl.service" ];
    };

    services.strongswan-swanctl = {
      enable = true;
      includes = [
        ../../../scripts/vpn/tmobile.swanctl.conf
        config.sops.secrets.${secretName}.path
      ];
    };
  };
}
