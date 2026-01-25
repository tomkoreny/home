{
  lib,
  pkgs,
  inputs,
  ...
}: 
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
in {
  stylix = stylixBase // {
    image = ./wallpaper.png;
    
    cursor = {
      package = pkgs.rose-pine-cursor;
      name = "BreezeX-RosePine-Linux";
      size = 32;
    };
    
    fonts = {
      monospace = common.stylix.fonts.monospace pkgs;
      sansSerif = {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };
      serif = {
        package = inputs.apple-fonts.packages.${pkgs.system}.ny-nerd;
        name = "NYDisplay Nerd Font";
      };
      sizes = common.stylix.fontSizes.nixos;
    };
  };
}
