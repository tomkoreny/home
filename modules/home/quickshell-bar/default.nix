{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.quickshell-bar;
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  themeVars = {
    inherit fontFamily;
    accent = common.stylix.accent;
    accentSurface = "#33219fff";
    border = "#66219fff";
    cardSurface = "#f21e1e2e";
    muted = "#f38ba8";
    surface = "#f2181825";
    text = "#cdd6f4";
    subdued = "#a6adc8";
  };
  shell = pkgs.replaceVars ./shell.qml (
    (builtins.removeAttrs themeVars [ "cardSurface" ])
    // {
      outputs = builtins.toJSON cfg.outputs;
      primaryOutput = cfg.primaryOutput;
      herdr = lib.getExe herdrPackage;
      hyprctl = lib.getExe' config.wayland.windowManager.hyprland.package "hyprctl";
      herdrView = "${config.home.profileDirectory}/bin/herdr-view";
      pavucontrol = lib.getExe pkgs.pavucontrol;
      qs = "${pkgs.quickshell}/bin/qs";
    }
  );
  launcher = pkgs.replaceVars ./Launcher.qml (
    (builtins.removeAttrs themeVars [ "muted" ])
    // {
      uwsm = lib.getExe pkgs.uwsm;
    }
  );
  notificationCard = pkgs.replaceVars ./NotificationCard.qml themeVars;
  notifications = pkgs.replaceVars ./Notifications.qml (
    (builtins.removeAttrs themeVars [
      "cardSurface"
      "muted"
    ])
    // {
      primaryOutput = cfg.primaryOutput;
    }
  );
in
{
  options.tomkoreny.quickshell-bar = {
    enable = lib.mkEnableOption "the Quickshell desktop bar";

    outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Monitor connectors that host Quickshell bars";
    };

    primaryOutput = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Monitor connector that hosts the status cluster";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "The Quickshell bar is currently Linux-only.";
      }
      {
        assertion = cfg.outputs != [ ];
        message = "tomkoreny.quickshell-bar.outputs must contain at least one output.";
      }
      {
        assertion = lib.elem cfg.primaryOutput cfg.outputs;
        message = "tomkoreny.quickshell-bar.primaryOutput must be one of its outputs.";
      }
    ];

    home.packages = [ pkgs.quickshell ];

    xdg.configFile = {
      "quickshell/tom-bar/shell.qml".source = shell;
      "quickshell/tom-bar/Launcher.qml".source = launcher;
      "quickshell/tom-bar/NotificationCard.qml".source = notificationCard;
      "quickshell/tom-bar/Notifications.qml".source = notifications;
    };

    systemd.user.services.quickshell-bar = {
      Unit.Description = "Quickshell desktop bar";
      Service = {
        ExecStart = "${pkgs.quickshell}/bin/qs -c tom-bar";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
