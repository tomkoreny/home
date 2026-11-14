{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.nix-gc;
  # nix-darwin's nix.gc requires nix.enable, which is off on this host because
  # Determinate owns the daemon, so call Determinate's nix-collect-garbage.
  collectGarbage = "/nix/var/nix/profiles/default/bin/nix-collect-garbage";
  # How long a system generation stays: long enough to roll back a bad
  # auto-upgrade, short enough that the daily flake.lock bumps do not pile up
  # hundreds of them. Home Manager is part of the system generation here; the
  # profiles under ~/.local/state/nix are pruned by `nh clean`
  # (modules/home/nh).
  keep = "14d";
  log = "/var/log/nix-gc.log";

  gcScript = pkgs.writeShellScript "nix-gc" ''
    set -uo pipefail
    # Keep only the last run: the collector prints a line per deleted path.
    exec >${log} 2>&1
    echo "nix-gc: started $(/bin/date)"
    # Old generations are removed first, then the store is collected through
    # the Nix daemon rather than by this job itself. macOS refuses to let a
    # process without Full Disk Access delete an app bundle that was once
    # opened, which is every app in the store that was ever launched, and one
    # refusal ends the whole collection: "fchmodat ...Ghostty.app: Operation
    # not permitted" in every run on record up to 2026-11-14, from this job
    # and from Determinate's own collector alike. Collecting through the
    # daemon means one grant, to Determinate's daemon, serves both: System
    # Settings > Privacy & Security > Full Disk Access, with
    # /usr/local/bin/determinate-nixd switched on, which only a person can
    # do. App Management, the permission meant for changing apps, is recorded
    # per user and changed nothing for the daemon, which runs as root. With Full
    # Disk Access on (2026-11-14) the bundle named above was deleted. Without
    # it the generations are still pruned and the collection stops at the
    # first such bundle.
    NIX_REMOTE=daemon ${collectGarbage} --delete-older-than ${keep}
    status=$?
    echo "nix-gc: finished $(/bin/date) with exit status $status"
    exit "$status"
  '';
in
{
  options.tomkoreny.darwin.nix-gc = {
    enable = lib.mkEnableOption "weekly pruning of Nix generations older than ${keep} and garbage collection";
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.nix-gc = {
      command = "${gcScript}";
      serviceConfig = {
        # Sunday 03:15. launchd starts a missed calendar job once the Mac wakes.
        StartCalendarInterval = [
          {
            Weekday = 0;
            Hour = 3;
            Minute = 15;
          }
        ];
        RunAtLoad = false;
      };
    };
  };
}
