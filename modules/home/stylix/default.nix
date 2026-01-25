{ lib, pkgs, inputs, system, ... }: 
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
  sharedFonts = common.stylix.fonts pkgs inputs;
in {
  # Only enable on NixOS (Darwin handles stylix at system level)
  config = lib.mkIf (system == "x86_64-linux") {
    stylix = stylixBase // {
      image = common.stylix.wallpaper;
      
      fonts = sharedFonts // {
        sizes = common.stylix.fontSizes;
      };
      
      targets.waybar.font = "sansSerif";
    };
  };
}
