{
  lib,
  pkgs,
  ...
}: 
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
in {
  stylix = stylixBase // {
    image = ./wallpaper.png;
    
    fonts = {
      monospace = common.stylix.fonts.monospace pkgs;
      # Darwin uses system fonts for better integration
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sizes = common.stylix.fontSizes.darwin;
    };
  };
}
