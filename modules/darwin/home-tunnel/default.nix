{
  config,
  lib,
  pkgs,
  ...
}:
# IPv4 through home for networks that hand out only IPv6.
#
# The homelab gateway (common.homeGateway) is a Yggdrasil node with a
# WireGuard server on its Yggdrasil address; it masquerades the tunnel's IPv4
# out of the home uplink. Yggdrasil reaches it over IPv6 and WireGuard rides
# on Yggdrasil, so home IPv4 is available wherever IPv6 works.
#
# The `home` interface stays up but routes nothing by itself. The failover
# daemon (failover.sh) decides when IPv4 goes through it and restores the
# local path once that works again.
#
# Key handling and the KeepAlive override follow modules/darwin/wireguard;
# its comments explain both.
let
  cfg = config.tomkoreny.darwin.home-tunnel;
  common = import ../../../lib/common { inherit lib; };
  gw = common.homeGateway;
  interface = "home";
  secretName = "wireguard-home-private-key";
  secretPath = "/etc/wireguard-${interface}.key";

  # Yggdrasil's own IPv4 links must never be carried inside the tunnel that
  # rides on them, so the daemon pins the peers it dials outside of it. Take
  # the host of each URI (bracketed IPv6 literals do not match and need no
  # pin) and split IPv4 literals from names, which are resolved on failover.
  peerHosts = lib.concatMap (
    uri:
    let
      parsed = builtins.match "[a-z]+://([a-zA-Z0-9._-]+)([:/?].*)?" uri;
    in
    lib.optional (parsed != null) (builtins.head parsed)
  ) config.tomkoreny.darwin.privacy-networks.yggdrasilPeers;
  isIPv4 = host: builtins.match "[0-9]+(\\.[0-9]+){3}" host != null;
  peers = lib.partition isIPv4 (lib.unique peerHosts);

  failover = pkgs.writeShellScript "home-tunnel-ipv4-failover" ''
    WG_INTERFACE=${lib.escapeShellArg interface}
    PEER_V4=(${lib.escapeShellArgs peers.right})
    PEER_HOSTS=(${lib.escapeShellArgs peers.wrong})
    RESTART_LABELS=(${lib.escapeShellArgs cfg.restartOnSwitch})
    TIMEOUT=${lib.getExe' pkgs.coreutils "timeout"}
    ${builtins.readFile ./failover.sh}
  '';
in
{
  options.tomkoreny.darwin.home-tunnel = {
    enable = lib.mkEnableOption "IPv4 failover through the home WireGuard-over-Yggdrasil gateway";

    restartOnSwitch = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "org.nixos.openfortivpn" ];
      description = ''
        Labels of system launchd daemons to restart (`launchctl kickstart -k
        system/<label>`) whenever IPv4 moves into or out of the tunnel, for
        services that route through whatever path was current when they
        started.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/wireguard/macos-home-private.key;
      format = "binary";
      owner = "root";
      group = "wheel";
      mode = "0400";
      path = secretPath;
    };

    networking.wg-quick.interfaces.${interface} = {
      address = [ gw.wireguard.addresses.macos ];
      # Fixed rather than derived from the physical uplink, as wg-quick would:
      # the encrypted packets go into Yggdrasil, not onto that link.
      mtu = 1420;
      # No routes from wg-quick: its /0 handling would take IPv4 for good,
      # even while the local network has working IPv4. The daemon below owns
      # IPv4 routing into this interface.
      table = "off";
      privateKeyFile = secretPath;
      autostart = true;
      # No listenPort: wg0 already holds 51820 here, and this side always
      # initiates.

      peers = [
        {
          inherit (gw.wireguard) publicKey endpoint;
          allowedIPs = [ "0.0.0.0/0" ];
          # Keeps the handshake and Yggdrasil's path to the gateway warm, so
          # IPv4 flows as soon as the daemon moves it here.
          persistentKeepalive = 25;
        }
      ];
    };

    launchd.daemons."wg-quick-${interface}".serviceConfig = {
      KeepAlive = lib.mkForce true;
      ThrottleInterval = 10;
    };

    launchd.daemons.home-tunnel-ipv4-failover = {
      command = "${failover}";
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
        # Stopping removes its routes and restarts openfortivpn gracefully,
        # which waits up to 20 s; launchd's default 20 s would cut that short.
        ExitTimeOut = 45;
        StandardOutPath = "/var/log/home-tunnel-failover.log";
        StandardErrorPath = "/var/log/home-tunnel-failover.log";
      };
    };
  };
}
