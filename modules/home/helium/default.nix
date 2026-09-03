{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  version = "0.8.5.1";
  common = import ../../../lib/common { };
  sharedFonts = common.stylix.fonts pkgs inputs;
  backgroundColor = common.stylix.background;
  accentColor = common.stylix.accent;
  accentLightColor = common.stylix.accentLight;
  sansSerifFont = sharedFonts.sansSerif.name;
  monospaceFont = sharedFonts.monospace.name;
  hexDigit =
    digit:
    (builtins.getAttr digit {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
      "8" = 8;
      "9" = 9;
      a = 10;
      b = 11;
      c = 12;
      d = 13;
      e = 14;
      f = 15;
    });
  hexByte =
    value: hexDigit (builtins.substring 0 1 value) * 16 + hexDigit (builtins.substring 1 1 value);
  hexColor =
    value:
    let
      hex = lib.toLower (lib.removePrefix "#" value);
    in
    map (offset: hexByte (builtins.substring offset 2 hex)) [
      0
      2
      4
    ];
  browserChromeTheme = pkgs.writeTextDir "manifest.json" (
    builtins.toJSON {
      manifest_version = 3;
      name = "Tom OLED Black";
      version = "1.0";
      theme.colors = {
        frame = [
          0
          0
          0
        ];
        frame_inactive = [
          0
          0
          0
        ];
        toolbar = [
          0
          0
          0
        ];
        toolbar_text = hexColor "#cdd6f4";
        tab_text = hexColor accentColor;
        tab_background_text = hexColor "#6c7086";
        bookmark_text = hexColor "#cdd6f4";
        button_background = [
          0
          0
          0
        ];
        toolbar_button_icon = hexColor "#cdd6f4";
        omnibox_background = [
          0
          0
          0
        ];
        omnibox_text = hexColor "#cdd6f4";
      };
    }
  );
  nextcloudHost = "nextcloud.home.tomkoreny.com";
  # Themed server-side by the homelab repo (apps/services/lemmy/theme), so Dark
  # Reader must leave it alone; see docs/theming.md.
  lemmyHost = "lemmy.tomkoreny.com";

  externalExtensions = [
    {
      id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; # Dark Reader
      version = "4.9.129";
      crx = pkgs.fetchurl {
        url = "https://clients2.googleusercontent.com/crx/blobs/AUU14H9YtxdbklhtavhDLIp6EU8GdmXC3s7q0P0PsnAkubhNGm_yGgKNuLxRPYOpqUQXiTrGZ4gaqFx5ZZNytiwD4IqjQ4eX1gVnkI5BY-Ue8BckMsvs3B2Kf4bFoNOBZGwAxlKa5dIXbQ5C_UZngYeYTTw7KV6YfEFt/EIMADPBCBFNMBKOPOOJFEKHNKHDBIEEH_4_9_129_0.crx";
        hash = "sha256-ncsb1tytQ4kt3AKP9l+YLfPtuhNammRF5PpxZx43qhM=";
      };
    }
    {
      id = "clngdbkpkpeebahjckkjfobafhncgmne"; # Stylus
      version = "2.4.9";
      crx = pkgs.fetchurl {
        url = "https://clients2.googleusercontent.com/crx/blobs/AUU14H_L17NKC6GXuvEa7-QEv8MJXZDoFNwg0Q3v_OYxHGy82eeTFxxFbakr0044ifr0NDaK_9SPccGcWMdmgPlfOHmhXx1ZXf6T_nUbpY3XJQNtHlp1dUewhvT4HNnSjPoAxlKa5bPBkddnonM7Y9AgBcA1Ic-YFE9z/CLNGDBKPKPEEBAHJCKKJFOBAFHNCGMNE_2_4_9_0.crx";
        hash = "sha256-qMU7PiV38+dCIH+NbWv1PA4PoSX3simCQeT4sTqmXGM=";
      };
    }
  ];
  externalExtensionFiles =
    directory:
    lib.listToAttrs (
      map (extension: {
        name = "${directory}/External Extensions/${extension.id}.json";
        value.text = builtins.toJSON {
          external_crx = "${extension.crx}";
          external_version = extension.version;
        };
      }) externalExtensions
    );

  # `all-userstyles-export` is a rolling release tag that upstream regenerates,
  # and there is no versioned artifact to point at instead, so this hash has to
  # be refreshed whenever the export changes. Verify the download before
  # trusting a new hash: it must be a JSON array that still contains the style
  # names selected below, or the generator fails in a much less obvious way.
  catppuccinStylusExport = pkgs.fetchurl {
    url = "https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json";
    hash = "sha256-kPWI8G5P0CsT6rI/MB6GzpoPTw9rTOAgmj1ASLcjhd4=";
  };
  # Upstream migrated the standard library to a versioned path and left
  # lib/lib.less as a two-line shim that imports this file. The shim is a moving
  # target that breaks the pin whenever it is touched; the versioned URL is
  # stable, and the hash below is unchanged because the content is the same.
  catppuccinUserstyleLibrary = pkgs.fetchurl {
    url = "https://userstyles.catppuccin.com/lib/std/v1.less";
    hash = "sha256-XK9Oqan7Kz81DNyE3+ryl5sPi/OpvV+EkgL7WuLoGfM=";
  };
  notionCatppuccinUsercss = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/OlaoluwaM/notion-catppuccin/main/catppuccin.user.css";
    hash = "sha256-4Xtg3vyhHyYcfw1U9A2L/cqqAfWE4XIfomFYDZLwFhk=";
  };
  nextcloudCatppuccinCss = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/byted/catppuccin-nextcloud/main/catppuccin.css";
    hash = "sha256-QZLTtpVwbhdhf0XHsz46d2/9E9yZK+TakC+lUTsXoFo=";
  };
  stylusCatppuccinImport =
    pkgs.runCommand "stylus-catppuccin-import.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - <<'PY'
        import json
        import os
        import re
        from pathlib import Path

        background = "${backgroundColor}"
        accent = "${accentColor}"
        accent_light = "${accentLightColor}"
        with open("${catppuccinStylusExport}") as source:
            export = json.load(source)

        library = Path("${catppuccinUserstyleLibrary}").read_text()
        library = re.sub(r"@blue:\s+#[0-9a-fA-F]{6};", f"@blue: {accent};", library)
        library, background_replacements = re.subn(
            r"(@mocha:\s*\{[^}]*?@base:)\s*#[0-9a-fA-F]{6};",
            lambda match: f"{match.group(1)} {background};",
            library,
        )
        if background_replacements != 1:
            raise RuntimeError("Unable to replace the Catppuccin Mocha background")
        accent_filter = (
            "brightness(0) saturate(100%) invert(55%) sepia(99%) "
            "saturate(2704%) hue-rotate(179deg) brightness(98%) contrast(102%)"
        )
        library = re.sub(
            r"@blue:\s+brightness\([^;]+;",
            f"@blue: {accent_filter};",
            library,
        )
        library_import = '@import "https://userstyles.catppuccin.com/lib/std/v1.less";'

        selected_names = {"GitHub Catppuccin", "YouTube Catppuccin"}
        selected = [
            item
            for item in export
            if item.get("name") in selected_names or "settings" in item
        ]

        for style in selected:
            variables = style.get("usercssData", {}).get("vars", {})
            for name, value in {
                "lightFlavor": "latte",
                "darkFlavor": "mocha",
                "accentColor": "blue",
            }.items():
                if name in variables:
                    variables[name]["value"] = value
            if style.get("name") == "YouTube Catppuccin":
                variables["oled"]["value"] = "1"
            if "sourceCode" in style:
                if library_import not in style["sourceCode"]:
                    raise RuntimeError(f"Catppuccin library import missing from {style['name']}")
                style["sourceCode"] = style["sourceCode"].replace(library_import, library)
                style.pop("updateUrl", None)
                style.pop("originalDigest", None)
                style["usercssData"].pop("updateURL", None)

        notion_source = Path("${notionCatppuccinUsercss}").read_text()
        notion_source = re.sub(
            r"(--blue_(?:theme|darken):)\s*[^;]+;",
            r"\1 206, 100%, 56%;",
            notion_source,
        )
        notion_source = re.sub(r"--main:\s*[^;]+;", f"--main: {accent};", notion_source)
        notion_source = re.sub(
            r"--bg(?:-light|-lighter)?:\s*[^;]+;",
            lambda match: f"{match.group(0).split(':', 1)[0]}: {background};",
            notion_source,
        )
        selected.append({
            "name": "Notion Catppuccin",
            "enabled": True,
            "sourceCode": notion_source,
            "usercssData": {
                "name": "Notion Catppuccin",
                "namespace": "https://github.com/OlaoluwaM",
                "version": "1.0.2",
                "description": "Soothing pastel theme for Notion",
                "author": "OlaoluwaM",
                "homepageURL": "https://github.com/OlaoluwaM/notion-catppuccin",
                "vars": {},
            },
        })

        def rgb(color):
            value = color.removeprefix("#")
            return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))

        background_rgb = rgb(background)
        accent_rgb = rgb(accent)
        nextcloud_source = Path("${nextcloudCatppuccinCss}").read_text()
        nextcloud_source = nextcloud_source.replace("#1e1e2e", background)
        nextcloud_source = nextcloud_source.replace("30,30,46", ",".join(map(str, background_rgb)))
        nextcloud_source = nextcloud_source.replace(
            "30, 30, 46",
            ", ".join(map(str, background_rgb)),
        )
        for original in ("#89b4fa", "#cba6f7", "#b4befe", "#1e66f5", "#8839ef", "#7928db"):
            nextcloud_source = nextcloud_source.replace(original, accent)
        for original in ("203, 166, 247", "136, 57, 239"):
            nextcloud_source = nextcloud_source.replace(
                original,
                ", ".join(map(str, accent_rgb)),
            )
        nextcloud_source = f"""/* ==UserStyle==
        @name           Nextcloud Catppuccin
        @namespace      https://github.com/byted/catppuccin-nextcloud
        @version        2026.05.24
        @description    Catppuccin theme for Nextcloud 32+
        @author         byted
        @homepageURL    https://github.com/byted/catppuccin-nextcloud
        ==/UserStyle== */
        @-moz-document domain("${nextcloudHost}") {{
        {nextcloud_source}
        }}
        """
        selected.append({
            "name": "Nextcloud Catppuccin",
            "enabled": True,
            "sourceCode": nextcloud_source,
            "usercssData": {
                "name": "Nextcloud Catppuccin",
                "namespace": "https://github.com/byted/catppuccin-nextcloud",
                "version": "2026.05.24",
                "description": "Catppuccin theme for Nextcloud 32+",
                "author": "byted",
                "homepageURL": "https://github.com/byted/catppuccin-nextcloud",
                "vars": {},
            },
        })

        # Microsoft Teams 2 renders with Fluent UI v9, whose design tokens are
        # CSS custom properties on the `.fui-FluentProvider` wrapper - not on
        # `:root` or `body`. Every portal root (menus, dialogs, flyouts) carries
        # the same class, so one selector covers the whole surface. Fluent
        # injects its own token rule at runtime with the same 0-1-0 specificity,
        # hence `!important`.
        #
        # The blocks key on Teams' own `<html>` theme class instead of
        # `prefers-color-scheme`, so the palette stays in lockstep with the base
        # theme Teams picked (icon fills, shadows, illustrations). Set
        # Appearance -> Follow OS theme once in Teams and it tracks the system,
        # which makes this follow the system too.
        #
        # `--colorNeutralBackgroundAlpha*` matter as much as the solid
        # backgrounds: the app bar, chat list and title bar paint with those, so
        # skipping them leaves half the chrome stock grey.
        teams_flavors = [
            {
                "html_classes": ("theme-defaultV2", "theme-tfl-default"),
                # Catppuccin Latte, with the shared accent darkened for a light
                # background (see lib/common/default.nix).
                "tokens": {
                    "--colorNeutralBackground1": "#eff1f5",
                    "--colorNeutralBackground1Hover": "#e6e9ef",
                    "--colorNeutralBackground1Pressed": "#dce0e8",
                    "--colorNeutralBackground1Selected": "#e6e9ef",
                    "--colorNeutralBackground2": "#e6e9ef",
                    "--colorNeutralBackground3": "#dce0e8",
                    "--colorNeutralBackground4": "#ccd0da",
                    "--colorNeutralBackground5": "#bcc0cc",
                    "--colorNeutralBackground6": "#acb0be",
                    "--colorNeutralBackgroundStatic": "#dce0e8",
                    "--colorNeutralBackgroundInverted": "#4c4f69",
                    "--colorNeutralBackgroundAlpha": "rgba(230, 233, 239, 0.92)",
                    "--colorNeutralBackgroundAlpha2": "rgba(220, 224, 232, 0.92)",
                    "--colorSubtleBackgroundHover": "#dce0e8",
                    "--colorSubtleBackgroundPressed": "#ccd0da",
                    "--colorSubtleBackgroundSelected": "#dce0e8",
                    "--colorTransparentBackgroundHover": "#e6e9ef",
                    "--colorTransparentBackgroundPressed": "#dce0e8",
                    "--colorNeutralForeground1": "#4c4f69",
                    "--colorNeutralForeground2": "#5c5f77",
                    "--colorNeutralForeground3": "#6c6f85",
                    "--colorNeutralForeground4": "#8c8fa1",
                    "--colorNeutralForegroundOnBrand": "#eff1f5",
                    "--colorNeutralStroke1": "#bcc0cc",
                    "--colorNeutralStroke2": "#ccd0da",
                    "--colorNeutralStroke3": "#e6e9ef",
                    "--colorBrandBackground": accent_light,
                    "--colorBrandBackgroundHover": accent_light,
                    "--colorBrandBackground2": "rgba(23, 111, 179, 0.14)",
                    "--colorBrandForeground1": accent_light,
                    "--colorBrandForeground2": accent_light,
                    "--colorBrandForegroundLink": accent_light,
                    "--colorBrandStroke1": accent_light,
                    "--colorBrandStroke2": "rgba(23, 111, 179, 0.4)",
                    "--colorCompoundBrandBackground": accent_light,
                    "--colorCompoundBrandForeground1": accent_light,
                    "--colorCompoundBrandStroke": accent_light,
                },
                "legacy": {
                    "--themeBackgroundColor": "#eff1f5",
                    "--themeTitleBarBackgroundColor": "#e6e9ef",
                    "--themeTitleBarColor": "#4c4f69",
                    "--themeLoadingScreenColor": "#eff1f5",
                },
            },
            {
                "html_classes": ("theme-darkV2", "theme-tfl-dark"),
                # Catppuccin Mocha on the shared true-black background.
                "tokens": {
                    "--colorNeutralBackground1": background,
                    "--colorNeutralBackground1Hover": "#11111b",
                    "--colorNeutralBackground1Pressed": "#181825",
                    "--colorNeutralBackground1Selected": "#11111b",
                    "--colorNeutralBackground2": "#11111b",
                    "--colorNeutralBackground3": "#181825",
                    "--colorNeutralBackground4": "#313244",
                    "--colorNeutralBackground5": "#45475a",
                    "--colorNeutralBackground6": "#585b70",
                    "--colorNeutralBackgroundStatic": "#181825",
                    "--colorNeutralBackgroundInverted": "#cdd6f4",
                    "--colorNeutralBackgroundAlpha": "rgba(17, 17, 27, 0.92)",
                    "--colorNeutralBackgroundAlpha2": "rgba(24, 24, 37, 0.92)",
                    "--colorSubtleBackgroundHover": "#181825",
                    "--colorSubtleBackgroundPressed": "#313244",
                    "--colorSubtleBackgroundSelected": "#181825",
                    "--colorTransparentBackgroundHover": "#11111b",
                    "--colorTransparentBackgroundPressed": "#181825",
                    "--colorNeutralForeground1": "#cdd6f4",
                    "--colorNeutralForeground2": "#bac2de",
                    "--colorNeutralForeground3": "#a6adc8",
                    "--colorNeutralForeground4": "#7f849c",
                    "--colorNeutralForegroundOnBrand": "#11111b",
                    "--colorNeutralStroke1": "#45475a",
                    "--colorNeutralStroke2": "#313244",
                    "--colorNeutralStroke3": "#181825",
                    "--colorBrandBackground": accent,
                    "--colorBrandBackgroundHover": accent,
                    "--colorBrandBackground2": "rgba(33, 159, 255, 0.18)",
                    "--colorBrandForeground1": accent,
                    "--colorBrandForeground2": accent,
                    "--colorBrandForegroundLink": accent,
                    "--colorBrandStroke1": accent,
                    "--colorBrandStroke2": "rgba(33, 159, 255, 0.4)",
                    "--colorCompoundBrandBackground": accent,
                    "--colorCompoundBrandForeground1": accent,
                    "--colorCompoundBrandStroke": accent,
                },
                "legacy": {
                    "--themeBackgroundColor": background,
                    "--themeTitleBarBackgroundColor": "#11111b",
                    "--themeTitleBarColor": "#cdd6f4",
                    "--themeLoadingScreenColor": background,
                },
            },
        ]

        teams_blocks = []
        for flavor in teams_flavors:
            for selector_suffix, declarations in (
                (" .fui-FluentProvider", flavor["tokens"]),
                ("", flavor["legacy"]),
            ):
                selectors = ",\n".join(
                    f"html.{name}{selector_suffix}" for name in flavor["html_classes"]
                )
                body = "\n".join(
                    f"    {token}: {value} !important;"
                    for token, value in declarations.items()
                )
                teams_blocks.append(f"{selectors} {{\n{body}\n}}")

        teams_rules = "\n\n".join(teams_blocks)
        teams_source = f"""/* ==UserStyle==
        @name           Teams Catppuccin
        @namespace      tomkoreny.com/stylix
        @version        1.0.0
        @description    Catppuccin theme for Microsoft Teams, following the Teams light/dark base
        @author         Tom Koreny
        ==/UserStyle== */
        @-moz-document domain("teams.cloud.microsoft"), domain("teams.microsoft.com") {{
        {teams_rules}
        }}
        """
        selected.append({
            "name": "Teams Catppuccin",
            "enabled": True,
            "sourceCode": teams_source,
            "usercssData": {
                "name": "Teams Catppuccin",
                "namespace": "tomkoreny.com/stylix",
                "version": "1.0.0",
                "description": "Catppuccin theme for Microsoft Teams",
                "author": "Tom Koreny",
                "vars": {},
            },
        })

        sans_serif = "${sansSerifFont}"
        monospace = "${monospaceFont}"
        font_source = f"""/* ==UserStyle==
        @name           Stylix Fonts
        @namespace      tomkoreny.com/stylix
        @version        1.0.0
        @description    Apply the shared Stylix fonts to web content
        @author         Tom Koreny
        ==/UserStyle== */
        @-moz-document regexp("^https?://.*") {{
        *:not(
            pre, pre *, code, [aria-hidden="true"],
            [class*="fa-"], .fa, .fab, .fad, .fal, .far, .fas,
            [class*="icon"], [class*="Icon"],
            [class*="symbol"], [class*="Symbol"],
            [class*="material-symbol"], [class*="material-icon"]
        ) {{
            font-family: "{sans_serif}" !important;
        }}
        pre, pre *, code, kbd, samp, tt {{
            font-family: "{monospace}" !important;
        }}
        }}
        """
        selected.append({
            "name": "Stylix Fonts",
            "enabled": True,
            "sourceCode": font_source,
            "usercssData": {
                "name": "Stylix Fonts",
                "namespace": "tomkoreny.com/stylix",
                "version": "1.0.0",
                "description": "Apply the shared Stylix fonts to web content",
                "author": "Tom Koreny",
                "vars": {},
            },
        })

        with open(os.environ["out"], "w") as output:
            json.dump(selected, output, indent=2)
            output.write("\n")
        PY
      '';
  darkReaderSettings = {
    fetchNews = false;
    theme = {
      mode = 1;
      brightness = 100;
      contrast = 100;
      grayscale = 0;
      sepia = 0;
      useFont = true;
      fontFamily = sansSerifFont;
      textStroke = 0;
      engine = "dynamicTheme";
      stylesheet = "";
      darkSchemeBackgroundColor = backgroundColor;
      darkSchemeTextColor = "#cdd6f4";
      lightSchemeBackgroundColor = "#eff1f5";
      lightSchemeTextColor = "#4c4f69";
      scrollbarColor = accentColor;
      selectionColor = accentColor;
      styleSystemControls = false;
      lightColorScheme = "Default";
      darkColorScheme = "Default";
      immediateModify = false;
    };
    # Avoid running the dynamic engine over applications which already provide
    # a native dark theme. Reprocessing their dark borders turns subtle neutral
    # separators into bright blue outlines.
    disabledFor = [
      "github.com"
      "youtube.com"
      "notion.so"
      nextcloudHost
      lemmyHost
      "dash.home.tomkoreny.com"
      "teams.cloud.microsoft"
    ];
    syncSettings = false;
    automation = {
      enabled = true;
      mode = "system";
      behavior = "Scheme";
    };
  };

  # Helium Browser - privacy-focused Chromium fork
  # Not yet in nixpkgs. Using AppImage for Linux, Homebrew cask for macOS.
  # Track upstream: https://github.com/imputnet/helium-linux
  # macOS: managed via Homebrew cask in systems/aarch64-darwin/macos/default.nix
  heliumAppImage = pkgs.appimageTools.wrapType2 {
    pname = "helium-browser";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
      hash = "sha256-jFSLLDsHB/NiJqFmn8S+JpdM8iCy3Zgyq+8l4RkBecM=";
    };
    extraPkgs =
      pkgs: with pkgs; [
        nss
        nspr
        atk
        at-spi2-atk
        cups
        dbus
        libdrm
        gtk3
        pango
        cairo
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        libxcb
        mesa
        expat
        alsa-lib
      ];
  };
  # Native Wayland applies Hyprland's per-monitor fractional scale. XWayland
  # stays unscaled by policy and makes Chromium's UI too small on HiDPI outputs.
  helium-browser = pkgs.writeShellScriptBin "helium-browser" ''
    exec ${lib.getExe heliumAppImage} --ozone-platform=wayland --load-extension=${browserChromeTheme} "$@"
  '';
in
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    helium-browser
  ];

  home.sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    BROWSER = "helium-browser";
  };

  # Helium has no Home Manager module, but supports Chromium's external-extension
  # manifests. Install Dark Reader as a fallback and Stylus for site-specific
  # Catppuccin userstyles on both platforms.
  home.file = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    externalExtensionFiles "Library/Application Support/net.imput.helium"
  );
  xdg.configFile = {
    "helium/stylus-catppuccin-import.json".source = stylusCatppuccinImport;
    "helium/dark-reader-settings.json".text = builtins.toJSON darkReaderSettings;
    "helium/theme-setup.md".text = ''
      # Helium website theming setup

      The shared OLED background is `${backgroundColor}`, the accent is `${accentColor}`,
      and web content uses `${sansSerifFont}` plus `${monospaceFont}` for code.
      Change them only through `common.stylix` in `~/home/lib/common/default.nix`; see
      `~/home/docs/theming.md` for propagation and maintenance details.

      The extension installation and import files are declarative. Import them after
      initial setup and again whenever shared colors, fonts, or pinned userstyles change:

      1. In Stylus, open **Manage**, select **Import**, and choose
         `~/.config/helium/stylus-catppuccin-import.json`.
         Import the bundled options when prompted so CSP patching is enabled.
      2. In Dark Reader, open **Settings → Advanced → Import Settings** and choose
         `~/.config/helium/dark-reader-settings.json`.
      3. Select each site's native dark appearance so its Catppuccin dark flavor is used:
         GitHub **Dark default**, YouTube **Dark theme**, and Notion **Dark**.
      4. In Teams, set **Settings → Appearance → Follow OS theme** once. The
         `Teams Catppuccin` style keys off the theme class Teams applies, so it then
         follows the system appearance: Latte in light mode, Mocha in dark mode.
         Only the browser client is themed; the desktop app cannot be.

      GitHub and YouTube use the official Catppuccin userstyles. Notion and
      `${nextcloudHost}` use community Catppuccin styles because they are not in
      the official Catppuccin userstyles collection. `${lemmyHost}` needs no
      userstyle: the instance itself serves a Catppuccin theme which follows the
      system light or dark preference, so Dark Reader is disabled there. Select
      **catppuccin** in its user settings if the account overrides the instance
      default theme. The Teams style is written in this repo; no Catppuccin
      userstyle exists for the current Teams client.
    '';
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (externalExtensionFiles "net.imput.helium");

  # The AppImage wrapper ships no desktop entry, so provide one — without it
  # the mimeApps defaults below point at a .desktop file that doesn't exist
  # and xdg-open/portal default-browser resolution fails.
  xdg.desktopEntries.helium-browser = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "Helium";
    genericName = "Web Browser";
    exec = "helium-browser %U";
    terminal = false;
    icon = "web-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeType = [
      "text/html"
      "application/xhtml+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
  };

  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications = {
      "text/html" = [ "helium-browser.desktop" ];
      "application/xhtml+xml" = [ "helium-browser.desktop" ];
      "x-scheme-handler/http" = [ "helium-browser.desktop" ];
      "x-scheme-handler/https" = [ "helium-browser.desktop" ];
      "x-scheme-handler/about" = [ "helium-browser.desktop" ];
      "x-scheme-handler/unknown" = [ "helium-browser.desktop" ];
    };
  };
}
