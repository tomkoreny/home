{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.mako;
  # Mako serves Linux desktop profiles that still use Waybar. The Quickshell
  # bar owns the notification DBus service when enabled, so both daemons must
  # not start in the same session.
  wanted =
    pkgs.stdenv.hostPlatform.isLinux
    && config.tomkoreny.desktop.enable
    && !config.tomkoreny.quickshell-bar.enable;
in
{
  options.tomkoreny.mako = {
    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Monitor connector to pin notifications to (null = follow the focused monitor)";
    };
  };

  config = lib.mkIf wanted {
    services.mako = {
      enable = true;
      settings = {
        anchor = "top-right";
        layer = "overlay";
        default-timeout = 7000;
        width = 380;
        height = 160;
        margin = "12";
        padding = "12";
        border-size = 2;
        border-radius = 8;
        max-visible = 5;
        icons = true;
        max-icon-size = 48;
      }
      // lib.optionalAttrs (cfg.output != null) {
        inherit (cfg) output;
      };
    };
  };
}
