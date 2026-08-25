{
  config,
  lib,
  ...
}:
# Always-on, split-tunnel WireGuard link to the internal network.
#
# Only the peer's AllowedIPs (the 10.71.71.0/24 tunnel subnet and the single
# internal host 192.168.22.106) get routes, so the link can stay up permanently
# without touching the default route -- normal internet traffic never enters the
# tunnel and there is nothing to toggle when leaving the LAN.
#
# The private key never enters the Nix store: wg-quick renders
# /etc/wireguard/wg0.conf without a PrivateKey line and injects the key from the
# sops-provisioned file via PostUp (`wg set wg0 private-key ...`).
let
  cfg = config.tomkoreny.nixos.wireguard;
  common = import ../../../lib/common { inherit lib; };
  wg = common.wireguard;
  secretName = "wireguard-private-key";
  unit = "wg-quick-${wg.interface}.service";
in
{
  options.tomkoreny.nixos.wireguard = {
    enable = lib.mkEnableOption "always-on split-tunnel WireGuard tunnel";

    address = lib.mkOption {
      type = lib.types.str;
      default = wg.addresses.nixos;
      description = ''
        This host's address inside the tunnel. Must be unique per machine: the
        server keys peers by public key and remembers one endpoint each, so two
        hosts sharing an identity knock each other offline.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/wireguard/nixos-private.key;
      format = "binary";
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ unit ];
    };

    networking.wg-quick.interfaces.${wg.interface} = {
      address = [ cfg.address ];
      listenPort = wg.listenPort;
      privateKeyFile = config.sops.secrets.${secretName}.path;
      autostart = true;

      peers = [
        {
          inherit (wg.server) publicKey endpoint allowedIPs;
          # This host is behind NAT and always initiates; the keepalive holds
          # the mapping open so the server can reach back in at any time.
          persistentKeepalive = 25;
        }
      ];
    };

    # The generated unit is a oneshot with no restart policy, so a tunnel that
    # fails to come up (uplink not ready yet, DNS hiccup) would stay down until
    # someone noticed. "Permanently on" means retrying.
    systemd.services."wg-quick-${wg.interface}".serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
