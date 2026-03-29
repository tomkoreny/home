{ config, lib, pkgs, ... }:

let
  cfg = config.tomkoreny.nixos.clawdbot-node;

  common = import ../../../lib/common {};

  # Script to ensure openclaw is installed
  ensureOpenclaw = pkgs.writeShellScript "ensure-openclaw" ''
    set -euo pipefail
    export PATH="${pkgs.nodejs_22}/bin:${pkgs.nodePackages.pnpm}/bin:$PATH"
    export HOME="/home/${cfg.user}"
    export PNPM_HOME="$HOME/.local/share/pnpm"

    # Setup pnpm
    pnpm setup 2>/dev/null || true
    export PATH="$PNPM_HOME:$PATH"

    # Install or update openclaw
    if ! command -v openclaw &>/dev/null; then
      echo "Installing openclaw..."
      pnpm add -g openclaw@latest
    fi
  '';

  # Node run script
  nodeRunScript = pkgs.writeShellScript "openclaw-node-run" ''
    set -euo pipefail
    export PATH="${pkgs.nodejs_22}/bin:${pkgs.nodePackages.pnpm}/bin:$PATH"
    export HOME="/home/${cfg.user}"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    export NODE_ENV="production"

    exec openclaw node run \
      --host "${cfg.gatewayHost}" \
      --port "${toString cfg.gatewayPort}" \
      --display-name "${cfg.displayName}" \
      ${lib.optionalString cfg.tls "--tls"} \
      ${lib.optionalString (cfg.tlsFingerprint != "") "--tls-fingerprint \"${cfg.tlsFingerprint}\""} \
      ${lib.concatStringsSep " " cfg.extraFlags}
  '';
in
{
  options.tomkoreny.nixos.clawdbot-node = {
    enable = lib.mkEnableOption "OpenClaw node service";

    gatewayHost = lib.mkOption {
      type = lib.types.str;
      default = "clawdbot.home.tomkoreny.com";
      description = "Gateway host address (Traefik-proxied endpoint)";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Gateway port";
    };

    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use TLS for the gateway connection";
    };

    tlsFingerprint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Expected TLS certificate fingerprint (sha256)";
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
      description = "Extra flags to pass to openclaw node run";
    };

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-update openclaw before starting the service";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Node.js and pnpm are available system-wide
    environment.systemPackages = with pkgs; [
      nodejs_22
      nodePackages.pnpm
      git
    ];

    # Systemd user service for openclaw node
    systemd.user.services.openclaw-node = {
      description = "OpenClaw Node - connects to gateway at ${cfg.gatewayHost}:${toString cfg.gatewayPort}";
      wantedBy = [ "default.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Install/update openclaw before starting
      preStart = lib.optionalString cfg.autoUpdate ''
        ${ensureOpenclaw}
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = nodeRunScript;
        Restart = "always";
        RestartSec = 10;
        TimeoutStartSec = 120;
      };
    };

    # Ensure required directories exist with correct permissions
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.openclaw 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/share/pnpm 0755 ${cfg.user} users -"
    ];
  };
}
