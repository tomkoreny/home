{
  config,
  lib,
  ...
}:
# Always-on, split-tunnel WireGuard link to the internal network.
#
# Same shape as modules/nixos/wireguard: only the peer's AllowedIPs are routed,
# so the tunnel can stay up permanently without capturing the default route.
# nix-darwin's networking.wg-quick writes /etc/wireguard/wg0.conf and a launchd
# daemon running `wg-quick up wg0`; on macOS that drives wireguard-go over a
# utun device.
#
# Do not "fix" the generated daemon into a plain one-shot: wg-quick detects
# launchd, keeps its route monitor inside the job and blocks, so the daemon is
# already long-running. That monitor is what handles roaming, since KeepAlive's
# NetworkState is a no-op key.
#
# The private key stays out of the Nix store: the config carries no PrivateKey
# line and PostUp injects it from the sops-provisioned file.
let
  cfg = config.tomkoreny.darwin.wireguard;
  common = import ../../../lib/common { inherit lib; };
  wg = common.wireguard;
  secretName = "wireguard-private-key";
  # sops-nix only *symlinks* `path` at the sops target under /run/secrets, so
  # this is not a persistent copy -- it is an /etc-shaped alias for a file that
  # does not exist until sops activation runs. Kept anyway to match
  # modules/darwin/vpn's convention and to give manual runs a stable path; the
  # boot ordering is handled by the KeepAlive override below, not by this path.
  secretPath = "/etc/wireguard-${wg.interface}.key";
in
{
  options.tomkoreny.darwin.wireguard = {
    enable = lib.mkEnableOption "always-on split-tunnel WireGuard tunnel";

    address = lib.mkOption {
      type = lib.types.str;
      default = wg.addresses.macos;
      description = ''
        This host's address inside the tunnel. Must be unique per machine: the
        server keys peers by public key and remembers one endpoint each, so two
        hosts sharing an identity knock each other offline.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/wireguard/macos-private.key;
      format = "binary";
      owner = "root";
      group = "wheel";
      mode = "0400";
      path = secretPath;
    };

    networking.wg-quick.interfaces.${wg.interface} = {
      address = [ cfg.address ];
      listenPort = wg.listenPort;
      privateKeyFile = secretPath;
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

    # The generated daemon uses KeepAlive.SuccessfulExit = true, which only
    # relaunches after a *clean* exit. That covers the interface vanishing (the
    # route monitor breaks its loop and exits 0) but not a failed bring-up, and
    # the most likely failure is the one that happens on every boot: launchd
    # starts this daemon and org.nixos.sops-install-secrets as unordered
    # siblings, so PostUp can run before the private key exists, fail, and take
    # the interface down with it -- permanently, since a nonzero exit is never
    # retried. Unconditional KeepAlive retries both cases, throttled to one
    # attempt per 10s, so the tunnel converges once sops has landed.
    launchd.daemons."wg-quick-${wg.interface}".serviceConfig = {
      KeepAlive = lib.mkForce true;
      ThrottleInterval = 10;
    };
  };
}
