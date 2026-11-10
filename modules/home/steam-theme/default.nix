{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.steam-theme;
  common = import ../../../lib/common { };
  fonts = common.stylix.fonts pkgs inputs;
  inherit (common.stylix) accent background;

  # Millennium identifies a theme by its folder name: that name is the value of
  # `themes.activeTheme` and the key under `themes.conditions` in its config.
  themeId = "adwaita-stylix";
  colorTheme = "Catppuccin Mocha (Stylix)";

  # Layered over the skin's own Catppuccin Mocha palette. The canvas surfaces
  # become the shared true black, Catppuccin's blue and the skin's default
  # accent become the shared accent, and text uses the shared fonts. Raised
  # surfaces (cards, dialogs, popovers) keep their Mocha values so they stay
  # distinguishable from the canvas.
  #
  # `--adw-accent` is the accent as text. The skin derives it by raising the
  # accent's OKLab lightness to 0.85, which turns the shared accent into a
  # second, cyan-leaning blue (#64d5ff); the shared accent already reads at
  # 7.5:1 on the black canvas, so it is used unchanged.
  stylixCss = pkgs.writeText "stylix.css" ''
    @import url("../catppuccin-mocha/catppuccin-mocha.css");

    :root {
      --adw-accent-bg-light: var(--adw-system-accent, ${accent}) !important;
      --adw-accent-bg-dark: var(--adw-system-accent, ${accent}) !important;
      --adw-accent: ${accent} !important;
      --adw-accent-blue: ${accent} !important;
      --adw-user-online: ${accent} !important;

      --adw-window-bg: ${background} !important;
      --adw-view-bg: ${background} !important;
      --adw-headerbar-bg: ${background} !important;
      --adw-headerbar-backdrop: ${background} !important;
      --adw-sidebar-bg: ${background} !important;
      --adw-sidebar-backdrop: ${background} !important;
      --adw-secondary-sidebar-bg: ${background} !important;
      --adw-secondary-sidebar-backdrop: ${background} !important;

      --adw-text-font-primary: "${fonts.sansSerif.name}" !important;
      --adw-text-font-monospace-primary: "${fonts.monospace.name}" !important;
    }
  '';

  theme = pkgs.runCommand "steam-theme-${themeId}" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir -p $out
    cp -r ${inputs.adwaita-for-steam-src}/{adwaita,injectors} $out/
    chmod -R u+w $out
    find $out -name preview.png -delete

    # The skin source follows upstream's branch, so fail the build when it
    # renames a variable the layer above overrides instead of silently
    # falling back to stock Catppuccin.
    for property in $(grep -oE '^\s+--adw-[a-z0-9-]+' ${stylixCss}); do
      grep -rqF -- "$property:" $out/adwaita/colorthemes/catppuccin-mocha $out/adwaita/css/_colors $out/adwaita/css/_root/text.css || {
        echo "Adwaita-for-Steam no longer declares $property" >&2
        exit 1
      }
    done
    install -Dm444 ${stylixCss} $out/adwaita/colorthemes/stylix/stylix.css

    # Offer the layer as one more "Color theme" choice. The `github` block is
    # dropped so Millennium's updater does not try to replace this read-only
    # copy with upstream's.
    jq --arg colorTheme ${lib.escapeShellArg colorTheme} '
      if (.Conditions["Color theme"].values | type) != "object" then
        error("skin.json no longer has Color theme values")
      end
      | del(.github)
      | .name = "Adwaita (Stylix)"
      | .Conditions["Color theme"].values[$colorTheme] = {
          TargetCss: { affects: [ ".*" ], src: "adwaita/colorthemes/stylix/stylix.css" }
        }
    ' ${inputs.adwaita-for-steam-src}/skin.json > $out/skin.json
  '';

  desiredConfig = pkgs.writeText "millennium-theme-config.json" (
    builtins.toJSON {
      # Millennium's own settings pages use this accent.
      general.accentColor = accent;
      themes = {
        activeTheme = themeId;
        conditions.${themeId} = {
          "Color theme" = colorTheme;
          # The layer above sets the accent; "System" would take it from
          # Millennium's injected variable instead.
          "Accent color" = "Theme default";
          # Skips the bundled Adwaita Sans faces; the layer names the font.
          "Font" = "System";
        };
      };
    }
  );

  applyConfig = pkgs.writeShellApplication {
    name = "steam-theme-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config="$1"
      current='{}'
      if [ -e "$config" ]; then
        current="$(cat "$config")"
      fi
      merged="$(jq --slurpfile desired ${desiredConfig} '. * $desired[0]' <<<"$current")"
      if [ "$(jq --sort-keys . <<<"$current")" = "$(jq --sort-keys . <<<"$merged")" ]; then
        exit 0
      fi
      mkdir -p "$(dirname "$config")"
      temporary="$(mktemp "$config.XXXXXX")"
      printf '%s\n' "$merged" > "$temporary"
      mv "$temporary" "$config"
    '';
  };
in
{
  options.tomkoreny.steam-theme.enable = lib.mkEnableOption "the shared look for the Steam client, applied through Millennium";

  config = lib.mkIf cfg.enable {
    # Millennium reads themes from `millennium/themes` inside the Steam root.
    xdg.dataFile."Steam/millennium/themes/${themeId}".source = theme;

    # Millennium owns the rest of its config and rewrites the file when Steam
    # exits. Merge only the theme choice so plugins and other settings stay
    # writable. A change applied while Steam is running is therefore lost at
    # exit and lands with the next activation.
    home.activation.steamTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe applyConfig} ${lib.escapeShellArg "${config.xdg.configHome}/millennium/config.json"}
    '';
  };
}
