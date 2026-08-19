{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  common = import ../../../lib/common { };
  sharedFonts = common.stylix.fonts pkgs inputs;
  backgroundColor = common.stylix.background;
  accentColor = common.stylix.accent;
  themeName = "Catppuccin Mocha (Stylix)";

  catppuccinElementTheme = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/element/f8236600302ef016c7366b96414a09e086996b71/themes/mocha/blue.json";
    hash = "sha256-SFskzt4ywG65x6nIdInLeWKPjYUffvHhKzhgJbohXhk=";
  };

  elementConfig =
    pkgs.runCommand "element-catppuccin-config.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - <<'PY'
        import json
        import os

        background = "${backgroundColor}"
        accent = "${accentColor}"

        with open("${catppuccinElementTheme}") as source:
            theme = json.load(source)

        replacements = {
            "#1e1e2e": background,
            "#89b4fa": accent,
        }

        def replace_colors(value):
            if isinstance(value, str):
                return replacements.get(value.lower(), value)
            if isinstance(value, list):
                return [replace_colors(item) for item in value]
            if isinstance(value, dict):
                return {key: replace_colors(item) for key, item in value.items()}
            return value

        theme = replace_colors(theme)
        theme["name"] = "${themeName}"
        theme["fonts"] = {
            "faces": [],
            "general": "'${sharedFonts.sansSerif.name}', sans-serif",
            "monospace": "'${sharedFonts.monospace.name}', monospace",
        }

        theme["colors"]["accent-color"] = accent
        theme["colors"]["primary-color"] = accent
        for key in (
            "--cpd-color-blue-900",
            "--cpd-color-text-action-accent",
            "--cpd-color-text-link-external",
            "--cpd-color-text-info-primary",
            "--cpd-color-bg-accent-rest",
            "--cpd-color-bg-accent-hovered",
            "--cpd-color-bg-accent-pressed",
            "--cpd-color-icon-accent-primary",
            "--cpd-color-icon-info-primary",
            "--cpd-color-border-focused",
        ):
            theme["compound"][key] = accent

        config = {
            "default_theme": f"custom-{theme['name']}",
            # The app bundle is owned by Homebrew (darwin) / Nix (linux), so Element's
            # Squirrel updater can never replace it and only nags. A falsy
            # update_base_url makes electron-main skip updater.start() entirely.
            "update_base_url": "",
            "features": {
                "feature_custom_themes": True,
            },
            "setting_defaults": {
                "custom_themes": [theme],
            },
        }

        with open(os.environ["out"], "w") as output:
            json.dump(config, output, indent=2)
            output.write("\n")
        PY
      '';
in
{
  # Element Desktop loads config.json from a platform-specific per-user path.
  # The config provides and defaults to the generated Catppuccin/Stylix theme.
  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    "Library/Application Support/Element/config.json".source = elementConfig;
  };

  xdg.configFile = lib.mkIf pkgs.stdenv.isLinux {
    "Element/config.json".source = elementConfig;
  };
}
