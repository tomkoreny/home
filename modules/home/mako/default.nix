{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.mako;
in
{
  options.tomkoreny.mako = {
    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Monitor connector to pin notifications to (null = follow the focused monitor)";
    };
  };

  # Keep Mako for Linux profiles that still use Waybar. The Quickshell bar
  # owns the notification DBus service when enabled, so both daemons must not
  # start in the same session.
  config = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !config.tomkoreny.quickshell-bar.enable) {
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
