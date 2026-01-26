{ config, lib, pkgs, ... }:

let
  cfg = config.tomkoreny.nixos.clawdbot-node;
  
  # Common configuration from lib
  common = import ../../../lib/common {};
  
  # Script to ensure clawdbot is installed
  ensureClawdbot = pkgs.writeShellScript "ensure-clawdbot" ''
    set -euo pipefail
    export PATH="${pkgs.nodejs_22}/bin:${pkgs.nodePackages.pnpm}/bin:$PATH"
    export HOME="/home/${cfg.user}"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    
    # Setup pnpm
    pnpm setup 2>/dev/null || true
    export PATH="$PNPM_HOME:$PATH"
    
    # Check if clawdbot exists and is recent enough
    if ! command -v clawdbot &>/dev/null; then
      echo "Installing clawdbot..."
      pnpm add -g clawdbot@latest
    fi
  '';
  
  # Node run script
  nodeRunScript = pkgs.writeShellScript "clawdbot-node-run" ''
    set -euo pipefail
    export PATH="${pkgs.nodejs_22}/bin:${pkgs.nodePackages.pnpm}/bin:$PATH"
    export HOME="/home/${cfg.user}"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    export NODE_ENV="production"
    
    exec clawdbot node run \
      --host "${cfg.gatewayHost}" \
      --port "${toString cfg.gatewayPort}" \
      --display-name "${cfg.displayName}" \
      ${lib.concatStringsSep " " cfg.extraFlags}
  '';
in
{
  options.tomkoreny.nixos.clawdbot-node = {
    enable = lib.mkEnableOption "Clawdbot node service";
    
    gatewayHost = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.93";
      description = "Gateway host address (Docker host running clawdbot gateway)";
    };
    
    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Gateway WebSocket port";
    };
    
    displayName = lib.mkOption {
      type = lib.types.str;
      default = "NixOS Desktop";
      description = "Display name shown in gateway node list";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = common.user.name;
      description = "User to run the node service as";
    };
    
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra flags to pass to clawdbot node run";
      example = [ "--tls" "--tls-fingerprint" "sha256:abc..." ];
    };
    
    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-update clawdbot before starting the service";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Ensure Node.js and pnpm are available system-wide
    environment.systemPackages = with pkgs; [
      nodejs_22
      nodePackages.pnpm
      git
    ];
    
    # Systemd user service for clawdbot node
    systemd.user.services.clawdbot-node = {
      description = "Clawdbot Node - connects to gateway at ${cfg.gatewayHost}:${toString cfg.gatewayPort}";
      wantedBy = [ "default.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      # Install/update clawdbot before starting
      preStart = lib.optionalString cfg.autoUpdate ''
        ${ensureClawdbot}
      '';
      
      serviceConfig = {
        Type = "simple";
        ExecStart = nodeRunScript;
        Restart = "always";
        RestartSec = 10;
        
        # Give it time to connect
        TimeoutStartSec = 60;
      };
    };
    
    # Ensure required directories exist with correct permissions
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.clawdbot 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/share/pnpm 0755 ${cfg.user} users -"
    ];
    
    # Open firewall for local network (optional, for browser proxy etc)
    # networking.firewall.allowedTCPPorts = [ 18791 ];
  };
}
