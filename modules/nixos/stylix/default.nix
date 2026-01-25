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
    image = common.stylix.wallpaper;
    cursor = common.stylix.cursor pkgs;
    fonts = sharedFonts // {
      sizes = common.stylix.fontSizes;
    };
  };
}
