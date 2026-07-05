{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.tomkoreny.nixos.clawdbot-node;

  common = import ../../../lib/common {};

  userHome = config.users.users.${cfg.user}.home;

  # Script to ensure the pinned openclaw version is installed
  ensureOpenclaw = pkgs.writeShellScript "ensure-openclaw" ''
    set -euo pipefail
    export HOME="${userHome}"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    # pnpm refuses global installs unless its global bin dir ($PNPM_HOME/bin)
    # is in PATH, so include both candidate bin locations.
    export PATH="$PNPM_HOME/bin:$PNPM_HOME:${pkgs.nodejs_22}/bin:${pkgs.pnpm}/bin:${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:$PATH"

    want="${cfg.version}"
    have=""
    if command -v openclaw &>/dev/null; then
      have=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)
    fi

    # node-linker=hoisted: openclaw relies on npm-style hoisting (its
    # pi-coding-agent dep imports @sinclair/typebox that only openclaw
    # declares); pnpm 11's isolated global layout breaks that.
    if [ -z "$have" ]; then
      echo "Installing openclaw@$want..."
      pnpm add -g "openclaw@$want" --config.node-linker=hoisted
    ${lib.optionalString cfg.autoUpdate ''
    elif [ "$have" != "$want" ]; then
      echo "Updating openclaw $have -> $want..."
      pnpm add -g "openclaw@$want" --config.node-linker=hoisted
    ''}
    fi
  '';

  # Node run script
  nodeRunScript = pkgs.writeShellScript "openclaw-node-run" ''
    set -euo pipefail
    export HOME="${userHome}"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME/bin:$PNPM_HOME:${pkgs.nodejs_22}/bin:${pkgs.pnpm}/bin:$PATH"
    export NODE_ENV="production"

    exec openclaw node run \
      --host "${cfg.gatewayHost}" \
      --port "${toString cfg.gatewayPort}" \
      --display-name "${cfg.displayName}" \
      ${lib.optionalString cfg.tls "--tls"} \
      ${lib.optionalString (cfg.tlsFingerprint != "") "--tls-fingerprint \"${cfg.tlsFingerprint}\""} \
      ${lib.concatStringsSep " " cfg.extraFlags}
  '';
in {
  options.tomkoreny.nixos.clawdbot-node = {
    enable = lib.mkEnableOption "OpenClaw node service";

    version = lib.mkOption {
      type = lib.types.str;
      # MUST match the gateway's openclaw protocol: mismatched nodes are
      # rejected with "protocol mismatch" (observed: 2026.3.28 against the
      # current gateway). Bump this together with gateway upgrades.
      default = "2026.6.11";
      description = "openclaw npm package version to install (pinned; bump together with the gateway)";
    };

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
      description = "Reinstall openclaw at service start when the installed version differs from `version` (when false, only install if missing)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Node.js and pnpm are available system-wide
    environment.systemPackages = with pkgs; [
      nodejs_22
      pnpm
      git
    ];

    # Systemd user service for openclaw node
    # (no network-online.target ordering: that target does not exist in the
    # user manager; Restart=always covers early starts before the network is up)
    systemd.user.services.openclaw-node = {
      description = "OpenClaw Node - connects to gateway at ${cfg.gatewayHost}:${toString cfg.gatewayPort}";
      wantedBy = ["default.target"];

      # Install the pinned openclaw before starting
      preStart = ''
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
      "d ${userHome}/.openclaw 0700 ${cfg.user} users -"
      "d ${userHome}/.local/share/pnpm 0755 ${cfg.user} users -"
    ];
  };
}
