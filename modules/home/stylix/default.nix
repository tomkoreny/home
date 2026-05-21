{ lib, pkgs, inputs, options, ... }:
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
  sharedFonts = common.stylix.fonts pkgs inputs;
in {
  # NixOS imports Stylix's Home Manager options through the system module.
  config = lib.mkIf (pkgs.stdenv.isLinux && options ? stylix) {
    stylix = stylixBase // {
      image = common.stylix.wallpaper;
      cursor = common.stylix.cursor pkgs;

      fonts = sharedFonts // {
        sizes = common.stylix.fontSizes;
      };

      targets.waybar.font = "sansSerif";
    };
  };
}
