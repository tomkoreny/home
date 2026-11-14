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
    # the Nix daemon rather than by this job itself. macOS lets only a process
    # with the App Management permission delete an app bundle that was once
    # opened, which is every app in the store that was ever launched, and one
    # refusal ends the whole collection: "fchmodat ...Ghostty.app: Operation
    # not permitted" in every run on record up to 2026-11-14, from this job
    # and from Determinate's own collector alike. Only a person can grant
    # that permission (System Settings > Privacy & Security). Collecting
    # through the daemon means one grant, to Determinate's daemon, is the
    # only one either collector could need. Until then the generations are
    # still pruned and the collection still stops at the first such bundle.
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
