{
  lib,
  pkgs,
  inputs,
  ...
}: 
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
  sharedFonts = common.stylix.fonts pkgs inputs;
in {
  stylix = stylixBase // {
    image = ./wallpaper.png;
    
    cursor = {
      package = pkgs.rose-pine-cursor;
      name = "BreezeX-RosePine-Linux";
      size = 32;
    };
    
    fonts = sharedFonts // {
      sizes = common.stylix.fontSizes;
    };
  };
}
