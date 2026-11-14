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
    # The default level, warn, is transport chatter: 215 MB of it in
    # ~/Library/Logs/i2pd.log by November 2026.
    loglevel = error

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

  # Yggdrasil is a public mesh: any node on it can route to this Mac's
  # address. Nothing filtered that path, so every listener here (Screen
  # Sharing, AirPlay, a container's published port) answered from the mesh,
  # as a probe from NixOS showed on 2026-11-14. These pf rules admit what this
  # Mac starts itself and, from the mesh, only the NixOS desktop (its ssh, for
  # Herdr and administration, and its ping) and the home gateway's WireGuard
  # answers, which carry the IPv4 fallback tunnel (modules/darwin/home-tunnel).
  # The Mac starts that tunnel too, so the first rule already covers it; the
  # explicit rule keeps it working should the state for it ever lapse.
  #
  # `flags any` lets connections that are already open when the rules load
  # carry on, the ssh session that deploys them included.
  firewallRules = pkgs.writeText "yggdrasil-firewall.pf" ''
    pass out quick inet6 from any to 200::/7 flags any keep state
    pass in quick inet6 proto tcp from ${common.yggdrasil.addresses.nixos} to any port 22 flags any keep state
    pass in quick inet6 proto icmp6 from ${common.yggdrasil.addresses.nixos} to any icmp6-type echoreq keep state
    pass in quick inet6 proto udp from ${common.homeGateway.yggdrasil.address} port ${toString common.homeGateway.wireguard.port} to any keep state
    block drop in quick inet6 from 200::/7 to any
  '';
  # macOS's /etc/pf.conf evaluates the anchors under com.apple and nothing
  # else, and a system update restores that file, so the rules go into an
  # anchor of their own under that name instead of into the file.
  firewallAnchor = "com.apple/300.Yggdrasil";
  # For trying changed rules without locking the NixOS desktop out, which is
  # the only way in while the Mac is away: create this file, deploy, test from
  # NixOS, then delete it. While it exists, freshly loaded rules are dropped
  # again after five minutes.
  firewallTrial = "${homeDir}/.local/state/yggdrasil-firewall/trial";
  firewall = pkgs.writeShellScript "yggdrasil-firewall" ''
    set -u
    say() { echo "$(/bin/date '+%F %T') $*"; }
    # pf filters nothing until it is enabled; a second -E only adds a reference.
    /sbin/pfctl -E >/dev/null 2>&1
    if ! output=$(/sbin/pfctl -q -a ${firewallAnchor} -f ${firewallRules} 2>&1); then
      say "loading ${firewallRules} failed: $output"
      exit 1
    fi
    if [ -e ${lib.escapeShellArg firewallTrial} ]; then
      say "trial: rules loaded, dropped again in 300 s unless ${firewallTrial} is removed"
      /bin/sleep 300
      if [ -e ${lib.escapeShellArg firewallTrial} ]; then
        /sbin/pfctl -q -a ${firewallAnchor} -F rules
        say "trial not confirmed: rules dropped"
      else
        say "trial confirmed: rules stay"
      fi
    fi
  '';
in
{
  options.tomkoreny.darwin.privacy-networks = {
    enable = lib.mkEnableOption "I2P and Yggdrasil overlay networks";

    yggdrasilPeers = lib.mkOption {
      type = with lib.types; listOf str;
      default = common.yggdrasil.peers;
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

    launchd.daemons.yggdrasil-firewall = {
      command = "${firewall}";
      serviceConfig = {
        RunAtLoad = true;
        # pf keeps loaded rules until a reboot or until something flushes
        # them, and other software on this Mac drives pf as well (VPN
        # clients, Internet Sharing). Loading the same rules again is a
        # no-op, so do it every quarter of an hour. Calendar slots, because
        # macOS 27 parks StartInterval jobs (see modules/darwin/auto-upgrade).
        StartCalendarInterval = map (minute: { Minute = minute; }) [
          0
          15
          30
          45
        ];
        # Written only when loading fails or a trial runs.
        StandardOutPath = "/var/log/yggdrasil-firewall.log";
        StandardErrorPath = "/var/log/yggdrasil-firewall.log";
      };
    };
  };
}
