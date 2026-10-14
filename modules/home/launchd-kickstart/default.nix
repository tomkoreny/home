# A long-running macOS GUI session's launchd domain can drop into
# "on-demand-only" mode. Agents bootstrapped while it is in that mode are parked
# at `pended nondemand spawn = speculative`: RunAtLoad is ignored and they stay
# stopped until something demands them, which for SketchyBar never happens. On
# 2026-10-14 an auto-upgrade switch reloaded SketchyBar and sops-nix this way
# and left both stopped (launchd: "pending spawn, domain in on-demand-only
# mode"); only a reboot or an explicit kickstart clears it.
#
# After the agents are reloaded, start the managed ones launchd parked.
# nix-darwin loads its user agents (org.nixos.*) before Home Manager activates,
# and sops-nix reloads its own agent after setupLaunchAgents. Only parked agents
# are started: one that ran and exited, or waits for a calendar slot, is not
# speculative, and `kickstart` without -k never restarts a running process.
{ lib, pkgs, ... }:
{
  home.activation.startParkedLaunchAgents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    lib.hm.dag.entryAfter [ "setupLaunchAgents" "sops-nix" ] ''
      domain="gui/$(/usr/bin/id -u)"
      for plist in "$HOME"/Library/LaunchAgents/org.nix-community.home.*.plist \
        "$HOME"/Library/LaunchAgents/org.nixos.*.plist; do
        [[ -e "$plist" ]] || continue
        label=$(/usr/bin/basename "$plist" .plist)
        state=$(/bin/launchctl print "$domain/$label" 2>/dev/null || true)
        if [[ "$state" == *"pended nondemand spawn = speculative"* ]]; then
          echo "Starting $label, which launchd parked instead of running"
          run /bin/launchctl kickstart -p "$domain/$label" >/dev/null \
            || warnEcho "Could not start parked agent '$domain/$label'"
        fi
      done
    ''
  );
}
