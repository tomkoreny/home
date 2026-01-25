{ config, lib, pkgs, ... }:

let
  cfg = config.tomkoreny.darwin.auto-upgrade;
  
  rebuild-script = pkgs.writeShellScript "auto-rebuild-darwin" ''
    set -euo pipefail
    
    REPO_PATH="$HOME/.config/home"
    LOCK_FILE="/tmp/auto-rebuild-darwin.lock"
    LOG_FILE="$HOME/Library/Logs/auto-rebuild.log"
    
    exec >> "$LOG_FILE" 2>&1
    echo "=== Auto-rebuild check at $(date) ==="
    
    # Prevent concurrent runs
    exec 200>"$LOCK_FILE"
    flock -n 200 || { echo "Another rebuild is running"; exit 0; }
    
    # Clone if missing
    if [ ! -d "$REPO_PATH" ]; then
      echo "Cloning repository..."
      ${pkgs.git}/bin/git clone ${cfg.repoUrl} "$REPO_PATH"
    fi
    
    cd "$REPO_PATH"
    
    # Fetch latest
    ${pkgs.git}/bin/git fetch origin main
    
    LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
    REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main)
    
    if [ "$LOCAL" = "$REMOTE" ]; then
      echo "Already up to date"
      exit 0
    fi
    
    echo "Changes detected, updating..."
    ${pkgs.git}/bin/git pull --ff-only origin main
    
    # Rebuild Darwin
    darwin-rebuild switch --flake .#macos
    
    echo "Rebuild complete at $(date)"
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
      default = 1800;  # 30 minutes in seconds
      description = "Interval between checks in seconds";
    };
  };
  
  config = lib.mkIf cfg.enable {
    launchd.user.agents.auto-rebuild = {
      script = "${rebuild-script}";
      serviceConfig = {
        StartInterval = cfg.interval;
        RunAtLoad = true;
        StandardOutPath = "$HOME/Library/Logs/auto-rebuild-stdout.log";
        StandardErrorPath = "$HOME/Library/Logs/auto-rebuild-stderr.log";
      };
      path = [ pkgs.git pkgs.nix config.nix.package "/run/current-system/sw" ];
    };
  };
}
