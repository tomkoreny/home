{ lib, pkgs, inputs, system, ... }: {
  config = lib.mkIf (system == "x86_64-linux") {
    stylix.enable = true;
    stylix.image = ../../nixos/stylix/wallpaper.png;
    stylix.polarity = "dark";
    stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    stylix.override.base00 = "#000000";

    stylix.fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };
      serif = {
        package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.ny-nerd;
        name = "NYDisplay Nerd Font";
      };
    };

    stylix.fonts.sizes = {
      applications = 12;
      terminal = 13;
      desktop = 10;
      popups = 10;
    };

    stylix.opacity = {
      applications = 1.0;
      terminal = 1.0;
      desktop = 1.0;
      popups = 1.0;
    };

    stylix.targets.waybar.font = "sansSerif";
  };
}
