{ lib, pkgs, inputs, system, ... }: 
let
  common = import ../../../lib/common {};
  stylixBase = common.stylix.base pkgs;
in {
  # Only enable on NixOS (Darwin handles stylix at system level)
  config = lib.mkIf (system == "x86_64-linux") {
    stylix = stylixBase // {
      image = ../../nixos/stylix/wallpaper.png;
      
      fonts = {
        monospace = common.stylix.fonts.monospace pkgs;
        sansSerif = {
          package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd;
          name = "SFProDisplay Nerd Font";
        };
        serif = {
          package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.ny-nerd;
          name = "NYDisplay Nerd Font";
        };
        sizes = common.stylix.fontSizes.nixos;
      };
      
      targets.waybar.font = "sansSerif";
    };
  };
}
