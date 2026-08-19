{
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
let
  common = import ../../../lib/common { };
  stylixBase = common.stylix.base pkgs;
  sharedFonts = common.stylix.fonts pkgs inputs;
in
{
  # Apply the shared theme to Home Manager programs on both platforms. The
  # system-level Stylix integrations deliberately disable their automatic Home
  # Manager import, so this remains the single user-level configuration.
  config = lib.mkIf (options ? stylix) {
    stylix =
      stylixBase
      // {
        image = common.stylix.wallpaper;
        fonts = sharedFonts // {
          sizes = common.stylix.fontSizes;
        };
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        cursor = common.stylix.cursor pkgs;
        targets.waybar.font = "sansSerif";
      };

    # The package is installed separately by modules/home/packages. Enabling the
    # Home Manager module lets Stylix generate Ghostty's font and color config.
    programs.ghostty = {
      enable = true;
      package = null;
      systemd.enable = false;

      # Stylix scales the terminal size by 4/3 on macOS (13 -> 17.333…), a float
      # Nix stringifies with six decimals, which no longer round-trips and warns
      # on every evaluation. Override with a flat integer.
      settings.font-size = lib.mkIf pkgs.stdenv.isDarwin (lib.mkForce 16);
    };
  };
}
