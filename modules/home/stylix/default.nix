{
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
let
  common = import ../../../lib/common { };
  stylixBase = common.stylix.base;
  sharedFonts = common.stylix.fonts pkgs inputs;
  accentLightColor = common.stylix.accentLight;
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

      # Ghostty is the one surface that can follow the system appearance on its
      # own: it accepts a `light:`/`dark:` theme pair and re-resolves it live
      # when the OS appearance changes. Stylix generates the dark half
      # (Catppuccin Mocha on the shared true black) as the theme named `stylix`;
      # the light half is below. With a split pair Ghostty rewrites its default
      # `window-theme = auto` to `system`, which hands the window chrome to the
      # OS, so nothing else needs setting.
      #
      # mkForce is required, not cosmetic: Stylix assigns
      # `settings.theme = "stylix"` at normal priority, and the option type
      # coerces to a list, so a second definition would *concatenate* instead of
      # conflicting. That emits two `theme =` lines, and Ghostty takes the last
      # one - a silent no-op rather than an evaluation error.
      settings.theme = lib.mkForce "light:stylix-light,dark:stylix";

      # Catppuccin Latte's own terminal palette - the values Catppuccin ships as
      # Ghostty's built-in "Catppuccin Latte" - with Latte blue replaced by the
      # shared light accent in the normal and bright slot. That mirrors the dark
      # side, where Stylix maps the shared accent onto base16 `base0D`.
      #
      # ANSI 0 is Latte `subtext1`, not the background: base16 puts base00 in
      # that slot, which is correct only for a dark scheme and would make black
      # text invisible here.
      themes.stylix-light = {
        background = "#eff1f5";
        foreground = "#4c4f69";
        cursor-color = "#4c4f69";
        selection-background = "#acb0be";
        selection-foreground = "#4c4f69";
        palette = [
          "0=#5c5f77"
          "1=#d20f39"
          "2=#40a02b"
          "3=#df8e1d"
          "4=${accentLightColor}"
          "5=#ea76cb"
          "6=#179299"
          "7=#acb0be"
          "8=#6c6f85"
          "9=#de293e"
          "10=#49af3d"
          "11=#eea02d"
          "12=${accentLightColor}"
          "13=#fe85d8"
          "14=#2d9fa8"
          "15=#bcc0cc"
        ];
      };
    };
  };
}
