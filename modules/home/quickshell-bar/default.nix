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

  shell = pkgs.replaceVars ./shell.qml {
    inherit fontFamily;
    outputs = builtins.toJSON cfg.outputs;
    primaryOutput = cfg.primaryOutput;
    accent = common.stylix.accent;
    accentSurface = "#33219fff";
    border = "#66219fff";
    muted = "#f38ba8";
    surface = "#f2181825";
    text = "#cdd6f4";
    subdued = "#a6adc8";
    pavucontrol = lib.getExe pkgs.pavucontrol;
    qs = "${pkgs.quickshell}/bin/qs";
  };
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

    xdg.configFile."quickshell/tom-bar/shell.qml".source = shell;

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
