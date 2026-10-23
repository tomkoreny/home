{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.nix-gc;
  common = import ../../../lib/common { };
  homeDir = common.user.homeDir { isDarwin = true; };
  # nix-darwin's nix.gc requires nix.enable, which is off on this host because
  # Determinate owns the daemon, so call Determinate's nix-collect-garbage.
  collectGarbage = "/nix/var/nix/profiles/default/bin/nix-collect-garbage";
  # Long enough to roll back a bad auto-upgrade, short enough that the daily
  # flake.lock bumps do not pile up hundreds of system generations.
  keep = "14d";
  log = "/var/log/nix-gc.log";

  gcScript = pkgs.writeShellScript "nix-gc" ''
    set -euo pipefail
    # Keep only the last run: the collector prints a line per deleted path.
    exec >${log} 2>&1
    echo "nix-gc: started $(/bin/date)"
    # Run as root, nix-collect-garbage only prunes profiles under
    # /nix/var/nix/profiles. Home Manager and `nix profile` generations live in
    # ~/.local/state/nix/profiles, so prune those as the user first. HOME is set
    # explicitly because sudoers keeps the caller's HOME (env_keep+=HOME).
    /usr/bin/sudo -u ${common.user.name} /usr/bin/env HOME=${homeDir} \
      ${collectGarbage} --delete-older-than ${keep}
    ${collectGarbage} --delete-older-than ${keep}
    echo "nix-gc: finished $(/bin/date)"
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
