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

  # Pretty notification popups. Replaces the old tiramisu -> Waybar
  # `custom/polytiramisu` setup that rendered notifications inline in the bar.
  # Colors, fonts and opacity are themed automatically by Stylix
  # (stylix targets.mako), so only layout is configured here.
  config = lib.mkIf pkgs.stdenv.isLinux {
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
