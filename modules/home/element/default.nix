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
  accentLightColor = common.stylix.accentLight;
  darkThemeName = "Catppuccin Mocha (Stylix)";
  lightThemeName = "Catppuccin Latte (Stylix)";

  # Both flavors come from the same pinned commit so they stay structurally
  # identical; the generator below rewrites the same keys in each.
  catppuccinElementMocha = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/element/f8236600302ef016c7366b96414a09e086996b71/themes/mocha/blue.json";
    hash = "sha256-SFskzt4ywG65x6nIdInLeWKPjYUffvHhKzhgJbohXhk=";
  };

  catppuccinElementLatte = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/element/f8236600302ef016c7366b96414a09e086996b71/themes/latte/blue.json";
    hash = "sha256-zj4vTIJ415ImXHiW/Wyf/skC4JWVy9A2dQC1IK6yaf8=";
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
        import re

        background = "${backgroundColor}"
        accent = "${accentColor}"
        accent_light = "${accentLightColor}"

        # Compound tokens that carry the accent in both flavors.
        accent_tokens = (
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
        )

        # Compound's numbered ramps run from "closest to the background" at 100
        # to "closest to the foreground" at 1400, so the light and dark ramps
        # run in opposite lightness directions. catppuccin/element derives Latte
        # by substituting palette names into the Mocha structure, which leaves
        # every Latte ramp running dark-to-light like a dark theme: measured on
        # the shipped build, that puts `--cpd-color-gray-1400` (which Compound
        # uses for the primary button fill) at Latte crust `#dce0e8`, under
        # `--cpd-color-text-on-solid-primary` `#eff1f5` - a white label on a
        # near-white button.
        #
        # The gray ramp is therefore rebuilt from the Latte palette in
        # Compound's own direction, extending past `text` with two shaded inks
        # the way Mocha extends past its text colour with two tints.
        latte_gray_ramp = (
            "#eff1f5",  # base
            "#e6e9ef",  # mantle
            "#dce0e8",  # crust
            "#ccd0da",  # surface0
            "#bcc0cc",  # surface1
            "#acb0be",  # surface2
            "#9ca0b0",  # overlay0
            "#8c8fa1",  # overlay1
            "#7c7f93",  # overlay2
            "#6c6f85",  # subtext0
            "#5c5f77",  # subtext1
            "#4c4f69",  # text
            "#3c3f54",  # text shaded 20% toward black
            "#2e2f3f",  # text shaded 40% toward black
        )
        ramp_slots = (100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400)
        HUE_RAMP = re.compile(r"^--cpd-color-(?!gray-)[a-z]+-\d+$")

        def build_theme(
            path,
            name,
            accent_color,
            replacements,
            canvas_color=None,
            gray_ramp=None,
        ):
            with open(path) as source:
                theme = json.load(source)

            def replace_colors(value):
                if isinstance(value, str):
                    return replacements.get(value.lower(), value)
                if isinstance(value, list):
                    return [replace_colors(item) for item in value]
                if isinstance(value, dict):
                    return {key: replace_colors(item) for key, item in value.items()}
                return value

            theme = replace_colors(theme)
            theme["name"] = name
            theme["fonts"] = {
                "faces": [],
                "general": "'${sharedFonts.sansSerif.name}', sans-serif",
                "monospace": "'${sharedFonts.monospace.name}', monospace",
            }

            if canvas_color is not None:
                # OLED background: only the page canvas goes true black. The
                # upstream Mocha theme also paints secondary buttons, subtle
                # backgrounds and the gray-300 ramp step with Mocha `base`, and
                # blanket-replacing every occurrence would flatten those into
                # the canvas now that the tokens actually apply (see below).
                for token in ("--cpd-color-theme-bg", "--cpd-color-bg-canvas-default"):
                    theme["compound"][token] = canvas_color
                theme["colors"]["timeline-background-color"] = canvas_color

            if gray_ramp is not None:
                # Rebuild the gray ramp in Compound's direction and drop the
                # hue ramps, which run the wrong way for a light theme too.
                # Their semantic tokens stay Catppuccin; only the numbered steps
                # fall back to Compound's own light ramps, which are correct by
                # construction. `--cpd-color-blue-900` is re-set as the accent
                # slot right below.
                for token in [t for t in theme["compound"] if HUE_RAMP.match(t)]:
                    del theme["compound"][token]
                for slot, value in zip(ramp_slots, gray_ramp):
                    theme["compound"][f"--cpd-color-gray-{slot}"] = value

            theme["colors"]["accent-color"] = accent_color
            theme["colors"]["primary-color"] = accent_color
            for key in accent_tokens:
                theme["compound"][key] = accent_color

            # A theme's `compound` block never reaches the page in element-web
            # 1.12.26. Element renders it into a `<style>` element that carries
            # `title="custom-theme-compound"`, and a titled stylesheet only
            # applies while it is the document's selected stylesheet set - which
            # it is not, because Element's own theme `<link>`s are titled and it
            # switches them by toggling `disabled`. Measured on the shipped
            # bundle: the element is present, `sheet.disabled === false`, the
            # rules parse, and none of them appear in the matched styles for
            # `<body>`; copying the identical CSS into an untitled `<style>`
            # applies it immediately. So `--cpd-color-bg-accent-rest` stayed
            # Element green `#129a78` and `--cpd-color-bg-canvas-default` stayed
            # `#101317`.
            #
            # `colors` entries take a different path: Element writes them with
            # `document.body.style.setProperty("--" + key, value)`, and an inline
            # style does apply. Re-declaring every token there is what makes the
            # palette land. The `compound` block is kept so the theme still works
            # if upstream drops the `title` attribute; identical values mean the
            # two paths cannot disagree.
            for token, value in theme["compound"].items():
                theme["colors"][token.removeprefix("--")] = value

            return theme

        # Dark: Catppuccin Mocha with the shared accent replacing Catppuccin
        # blue, and the shared true-black background as the page canvas.
        dark_theme = build_theme(
            "${catppuccinElementMocha}",
            "${darkThemeName}",
            accent,
            {
                "#89b4fa": accent,
            },
            canvas_color=background,
        )

        # Light: Catppuccin Latte keeps its own surfaces - there is no light
        # counterpart to the true-black background - and only swaps Latte blue
        # for the darkened accent.
        light_theme = build_theme(
            "${catppuccinElementLatte}",
            "${lightThemeName}",
            accent_light,
            {
                "#1e66f5": accent_light,
            },
            gray_ramp=latte_gray_ramp,
        )

        for theme, expected_dark in ((dark_theme, True), (light_theme, False)):
            # Element picks the light-custom or dark-custom base stylesheet and
            # the cpd-theme-* body class from this flag, so a wrong value ships
            # a Latte palette on top of dark base CSS.
            if theme.get("is_dark") is not expected_dark:
                raise RuntimeError(f"{theme['name']}: expected is_dark={expected_dark}")

        config = {
            "default_theme": f"custom-{dark_theme['name']}",
            # The app bundle is owned by Homebrew (darwin) / Nix (linux), so Element's
            # Squirrel updater can never replace it and only nags. A falsy
            # update_base_url makes electron-main skip updater.start() entirely.
            "update_base_url": "",
            "features": {
                "feature_custom_themes": True,
            },
            "setting_defaults": {
                "custom_themes": [dark_theme, light_theme],
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
