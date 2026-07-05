{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.tomkoreny.darwin.auto-upgrade;
  common = import ../../../lib/common {};
  homeDir = common.user.homeDir { isDarwin = true; };

  # darwin-rebuild via the persistent system profile: /run/current-system is
  # volatile on macOS. Must match the sudoers rule below.
  darwinRebuild = "/nix/var/nix/profiles/system/sw/bin/darwin-rebuild";

  # Pull + rebuild only. Flake input updates happen in CI (which validates the
  # lock before pushing); this machine just follows origin/main. Operating on
  # the same checkout nh uses means "what's running" is "what you edit".
  upgradeScript = pkgs.writeShellScript "darwin-auto-upgrade" ''
    set -euo pipefail
    export PATH="${pkgs.git}/bin:/nix/var/nix/profiles/system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    REPO_PATH=${lib.escapeShellArg cfg.repoPath}

    # $TMPDIR is per-user and cleared on reboot, so a crashed run cannot
    # wedge the lock across boots.
    LOCK_DIR="''${TMPDIR:-/tmp}/auto-upgrade-$(id -u).lock"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "auto-upgrade: another run is in progress; exiting"
      exit 0
    fi
    trap 'rmdir "$LOCK_DIR"' EXIT

    if [ ! -d "$REPO_PATH/.git" ]; then
      echo "auto-upgrade: no git checkout at $REPO_PATH" >&2
      exit 1
    fi

    cd "$REPO_PATH"

    # Never touch a dirty checkout — this is the repo the user edits. Exit
    # non-zero so the skip is visible in launchctl instead of silent.
    if [ -n "$(git status --porcelain)" ]; then
      echo "auto-upgrade: $REPO_PATH has local changes; skipping" >&2
      exit 1
    fi

    git fetch origin main

    if [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
      echo "auto-upgrade: already up to date"
      exit 0
    fi

    git merge --ff-only origin/main

    echo "auto-upgrade: activating $(git rev-parse --short HEAD)..."
    /usr/bin/sudo -n ${darwinRebuild} switch --flake "$REPO_PATH#macos"
  '';
in {
  options.tomkoreny.darwin.auto-upgrade = {
    enable = lib.mkEnableOption "periodic pull + rebuild from git";

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/home";
      description = "Git checkout to pull and rebuild (the same one nh uses)";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 1800; # 30 minutes in seconds
      description = "Seconds between upgrade attempts";
    };
  };

  config = lib.mkIf cfg.enable {
    # Let the (non-root) launchd agent activate the rebuilt system without a
    # password. Scoped to darwin-rebuild only.
    environment.etc."sudoers.d/darwin-rebuild".text = ''
      ${common.user.name} ALL=(ALL) NOPASSWD: ${darwinRebuild}
    '';

    launchd.user.agents.auto-upgrade = {
      command = "${upgradeScript}";
      serviceConfig = {
        StartInterval = cfg.interval;
        RunAtLoad = false;
        StandardOutPath = "${homeDir}/Library/Logs/auto-upgrade.log";
        StandardErrorPath = "${homeDir}/Library/Logs/auto-upgrade.log";
      };
    };
  };
}
