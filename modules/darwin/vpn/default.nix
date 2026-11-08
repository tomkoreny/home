{
  config,
  lib,
  pkgs,
  ...
}:
# Persistent T-Mobile ACHO IPsec tunnel through strongSwan. The connection
# (scripts/vpn/tmobile.swanctl.conf) is shared with modules/nixos/vpn; the
# sops secret adds the PSK and the EAP login to it.
#
# nix-darwin has no strongSwan service, so launchd runs charon directly. On
# macOS charon handles ESP in userspace (kernel-libipsec loads before
# kernel-pfkey and wins) on a utun device and routes the remote subnets into it.
let
  cfg = config.tomkoreny.darwin.vpn;
  strongswan = pkgs.strongswan;
  secretName = "tmobile-ipsec";
  # Avoid /var/run race on early boot; keep secrets in persistent root-owned location.
  secretPath = "/etc/tmobile-ipsec.secrets.conf";
in
{
  options.tomkoreny.darwin.vpn = {
    enable = lib.mkEnableOption "persistent T-Mobile IPsec tunnel";
  };

  config = lib.mkIf cfg.enable {
    # swanctl on PATH for `sudo swanctl --list-sas` and manual (re)initiation.
    environment.systemPackages = [ strongswan ];

    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/vpn/tmobile-ipsec.conf;
      format = "binary";
      owner = "root";
      group = "wheel";
      mode = "0400";
      path = secretPath;
    };

    # strongSwan is built with --sysconfdir=/etc, so charon and swanctl read these.
    environment.etc."swanctl/swanctl.conf".text = ''
      include ${../../../scripts/vpn/tmobile.swanctl.conf}
      include ${secretPath}
    '';
    environment.etc."strongswan.conf".text = ''
      charon {
        # Loads the connection once charon is up; its start_action connects.
        start-scripts {
          swanctl = ${lib.getExe' strongswan "swanctl"} --load-all --noprompt
        }
        filelog {
          stderr {
            time_format = %F %T
            default = 1
          }
        }
      }
    '';

    launchd.daemons.strongswan = {
      command = "${strongswan}/libexec/ipsec/charon";
      serviceConfig = {
        # charon exits 0 on SIGTERM; home-tunnel's restartOnSwitch starts it again.
        KeepAlive = {
          SuccessfulExit = false;
          NetworkState = true;
        };
        RunAtLoad = true;
        StandardOutPath = "/var/log/strongswan.log";
        StandardErrorPath = "/var/log/strongswan.log";
      };
    };
  };
}
