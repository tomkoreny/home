{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.tomkoreny.darwin.auto-upgrade;

  rebuild-script = pkgs.writeShellScript "auto-rebuild-darwin" ''
    set -euo pipefail

    # Ensure darwin-rebuild and nix tools are in PATH
    export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/tom/bin:$PATH"

    REPO_PATH="$HOME/.config/home"
    LOCK_FILE="/tmp/auto-rebuild-darwin.lock"
    LOG_FILE="$HOME/Library/Logs/auto-rebuild.log"

    exec >> "$LOG_FILE" 2>&1
    echo "=== Auto-rebuild check at $(${pkgs.coreutils}/bin/date) ==="

    # Prevent concurrent runs
    exec 200>"$LOCK_FILE"
    ${pkgs.flock}/bin/flock -n 200 || { echo "Another rebuild is running"; exit 0; }

    # Clone if missing
    if [ ! -d "$REPO_PATH" ]; then
      echo "Cloning repository..."
      ${pkgs.git}/bin/git clone ${cfg.repoUrl} "$REPO_PATH"
    fi

    cd "$REPO_PATH"

    NEEDS_REBUILD=false

    # Skip cleanly if the repo has local edits or untracked files.
    if [ -n "$(${pkgs.git}/bin/git status --porcelain)" ]; then
      echo "Working tree has local changes, skipping auto-update"
      exit 0
    fi

    # Fetch latest config changes
    ${pkgs.git}/bin/git fetch origin main

    LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
    REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main)

    if [ "$LOCAL" != "$REMOTE" ]; then
      echo "Config changes detected, updating..."
      ${pkgs.git}/bin/git merge --ff-only origin/main
      NEEDS_REBUILD=true
    fi

    # Update flake inputs (nixpkgs etc.) weekly to keep packages fresh
    FLAKE_STAMP="/tmp/auto-rebuild-flake-update"
    WEEK_SECONDS=604800
    NOW=$(${pkgs.coreutils}/bin/date +%s)
    STAMP_AGE=0
    if [ -f "$FLAKE_STAMP" ]; then
      STAMP_TIME=$(${pkgs.coreutils}/bin/stat -c %Y "$FLAKE_STAMP" 2>/dev/null || echo 0)
      STAMP_AGE=$(( NOW - STAMP_TIME ))
    else
      STAMP_AGE=$((WEEK_SECONDS + 1))
    fi

    if [ "$STAMP_AGE" -gt "$WEEK_SECONDS" ]; then
      echo "Updating flake inputs..."
      if nix flake update 2>&1; then
        if ${pkgs.git}/bin/git diff --quiet flake.lock 2>/dev/null; then
          echo "No flake input changes"
        else
          echo "Flake inputs updated, committing..."
          ${pkgs.git}/bin/git add flake.lock
          ${pkgs.git}/bin/git commit -m "chore: auto-update flake inputs"
          ${pkgs.git}/bin/git push origin main || echo "Push failed (non-fatal)"
          NEEDS_REBUILD=true
        fi
      else
        echo "Flake update failed, continuing..."
      fi
      ${pkgs.coreutils}/bin/touch "$FLAKE_STAMP"
    fi

    if [ "$NEEDS_REBUILD" = "true" ]; then
      echo "Running flake checks..."
      nix flake check --show-trace
      echo "Rebuilding Darwin..."
      /usr/bin/sudo -n /run/current-system/sw/bin/darwin-rebuild switch --flake .#macos
      echo "Rebuild complete at $(${pkgs.coreutils}/bin/date)"
    else
      echo "Already up to date"
    fi
  '';
in
{
  options.tomkoreny.darwin.auto-upgrade = {
    enable = lib.mkEnableOption "automatic Darwin upgrades from git";

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/tomkoreny/home.git";
      description = "Git repository URL";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 1800; # 30 minutes in seconds
      description = "Interval between checks in seconds";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.auto-rebuild = {
      script = "${rebuild-script}";
      serviceConfig = {
        StartInterval = cfg.interval;
        RunAtLoad = true;
      };
      path = [
        pkgs.git
        pkgs.nix
        config.nix.package
        "/run/current-system/sw"
        "/nix/var/nix/profiles/default"
        "/etc/profiles/per-user/tom"
      ];
    };
  };
}
