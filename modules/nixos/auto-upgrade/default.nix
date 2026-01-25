{ config, lib, pkgs, ... }:

let
  cfg = config.tomkoreny.nixos.auto-upgrade;
  
  rebuild-script = pkgs.writeShellScript "auto-rebuild" ''
    set -euo pipefail
    
    REPO_PATH="/etc/nixos/home"
    LOCK_FILE="/tmp/auto-rebuild.lock"
    
    # Prevent concurrent runs
    exec 200>"$LOCK_FILE"
    flock -n 200 || { echo "Another rebuild is running"; exit 0; }
    
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
    
    # Rebuild
    nixos-rebuild switch --flake .#nixos
    
    echo "Rebuild complete at $(date)"
  '';
in
{
  options.tomkoreny.nixos.auto-upgrade = {
    enable = lib.mkEnableOption "automatic NixOS upgrades from git";
    
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/tomkoreny/home.git";
      description = "Git repository URL";
    };
    
    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/30";  # Every 30 minutes
      description = "Systemd calendar interval";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Clone repo if not present
    system.activationScripts.clone-home-repo = ''
      if [ ! -d /etc/nixos/home ]; then
        ${pkgs.git}/bin/git clone ${cfg.repoUrl} /etc/nixos/home
      fi
    '';
    
    systemd.services.auto-rebuild = {
      description = "Auto rebuild NixOS from git";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = rebuild-script;
      };
      path = [ pkgs.nixos-rebuild pkgs.git pkgs.nix ];
    };
    
    systemd.timers.auto-rebuild = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;  # Run if missed while off
        RandomizedDelaySec = "5m";  # Spread load
      };
    };
  };
}
