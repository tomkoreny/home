{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.komai;
  common = import ../../../lib/common { };
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  themeFormat = pkgs.formats.yaml { };
  themePython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  profileConfigRoot =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Preferences/komai"
    else
      "${config.xdg.configHome}/komai";

  mkUserColors = self: others: {
    self.background = self;
    others = map (background: { inherit background; }) others;
  };

  darkTheme = themeFormat.generate "dark-catppuccin-stylix.yml" {
    name = "Catppuccin Mocha (Stylix)";
    author = "Stylix / Catppuccin";
    variant = "dark";
    palette = {
      window = common.stylix.background;
      windowText = "#cdd6f4";
      base = "#181825";
      alternateBase = "#313244";
      text = "#cdd6f4";
      brightText = "#b4befe";
      button = "#181825";
      buttonText = "#9aa1bb";
      light = "#45475a";
      mid = "#4f5165";
      dark = "#3d3d43";
      highlight = common.stylix.accent;
      highlightedText = common.stylix.background;
      link = common.stylix.accent;
      toolTipBase = "#181825";
      toolTipText = "#cdd6f4";
      attention = "#f38ba8";
      attentionText = common.stylix.background;
      success = "#a6e3a1";
      warning = "#fab387";
      error = "#f38ba8";
    };
    userColors = mkUserColors "#333e59" [
      "#3f252f"
      "#253f37"
      "#342549"
      "#3f3c2f"
      "#3f253d"
      "#303f2f"
      "#3f2e2f"
      "#253f41"
      "#3e2549"
      "#383f2f"
      "#3f2533"
      "#263f2f"
      "#2b2549"
    ];
  };

  lightTheme = themeFormat.generate "light-catppuccin-stylix.yml" {
    name = "Catppuccin Latte (Stylix)";
    author = "Stylix / Catppuccin";
    variant = "light";
    palette = {
      window = "#eff1f5";
      windowText = "#4c4f69";
      base = "#e6e9ef";
      alternateBase = "#ccd0da";
      text = "#4c4f69";
      brightText = "#000000";
      button = "#e6e9ef";
      buttonText = "#54566c";
      light = "#ccd0da";
      mid = "#9ea2b1";
      dark = "#8a8c8f";
      highlight = common.stylix.accentLight;
      highlightedText = "#ffffff";
      link = common.stylix.accentLight;
      toolTipBase = "#e6e9ef";
      toolTipText = "#4c4f69";
      attention = "#d20f39";
      attentionText = "#ffffff";
      success = "#40a02b";
      warning = "#9c3a01";
      error = "#d20f39";
    };
    userColors = mkUserColors "#acc4f3" [
      "#dbc1c5"
      "#beddce"
      "#cfc1e2"
      "#dbdac5"
      "#dbc1d5"
      "#caddc5"
      "#dbcbc5"
      "#beddd8"
      "#d9c1e2"
      "#d4ddc5"
      "#dbc1ca"
      "#bfddc5"
      "#c5c1e2"
    ];
  };
  version = "2026.08.24.1";
  meta = {
    description = "Native Matrix desktop client";
    homepage = "https://komai.chat";
    license = lib.licenses.gpl3Plus;
    mainProgram = "komai";
  };

  linuxSrc = pkgs.fetchurl {
    url = "https://github.com/etkecc/komai/releases/download/v${version}/komai-${version}-x86_64.AppImage";
    hash = "sha256-Zh+TIx+TVaixE3wS0+CJxewJvs1O7F0oQLFe8Zut5qw=";
  };
  appimageContents = pkgs.appimageTools.extract {
    pname = "komai";
    inherit version;
    src = linuxSrc;
    postExtract = ''
      # Upstream records Ubuntu's oldest supported glibc (2.20), causing AppRun
      # to prefer NixOS's 2.42 over the bundled 2.43 compatibility runtime.
      # Record the actual build glibc so AppRun selects its compatible runtime.
      substituteInPlace $out/AppRun.env \
        --replace-fail 'APPDIR_LIBC_VERSION=2.20' 'APPDIR_LIBC_VERSION=2.43'
      ln -s usr/lib64 $out/runtime/compat/lib64
    '';
  };
  linuxKomai = pkgs.appimageTools.wrapAppImage {
    pname = "komai";
    inherit version;
    src = appimageContents;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    extraPkgs = pkgs': [ pkgs'.hicolor-icon-theme ];
    extraInstallCommands = ''
      install -m 444 -D \
        ${appimageContents}/cc.etke.komai.desktop \
        $out/share/applications/cc.etke.komai.desktop
      cp -r ${appimageContents}/usr/share/icons $out/share/

      # Keep profile switches and generated per-profile launchers on the outer
      # AppImage wrapper instead of trying to execute the inner ELF directly.
      wrapProgram $out/bin/komai \
        --set KOMAI_EXECUTABLE_PATH $out/bin/komai
    '';
    meta = meta // {
      platforms = [ "x86_64-linux" ];
    };
  };

  darwinSrc = pkgs.fetchurl {
    url = "https://github.com/etkecc/komai/releases/download/v${version}/komai-${version}-macos-arm64.dmg";
    hash = "sha256-7xnp7xb9k3XX/5DdblHejkuzESnZVMfDHx++VUjgDvs=";
  };
  darwinKomai = pkgs.stdenvNoCC.mkDerivation {
    pname = "komai";
    inherit version;
    src = darwinSrc;
    nativeBuildInputs = [ pkgs.undmg ];
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications"
      mv Komai.app "$out/Applications/Komai.app"

      runHook postInstall
    '';
    meta = meta // {
      platforms = [ "aarch64-darwin" ];
    };
  };

  komai = if pkgs.stdenv.hostPlatform.isDarwin then darwinKomai else linuxKomai;
in
{
  options.tomkoreny.komai.enable = lib.mkEnableOption "the Komai Matrix client";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.elem pkgs.stdenv.hostPlatform.system [
          "x86_64-linux"
          "aarch64-darwin"
        ];
        message = "The Komai module supports x86_64 Linux and Apple silicon macOS.";
      }
    ];

    home.packages = [ komai ];

    home.file = lib.mkIf isDarwin {
      "Library/Application Support/komai/themes/dark-catppuccin-stylix.yml".source = darkTheme;
      "Library/Application Support/komai/themes/light-catppuccin-stylix.yml".source = lightTheme;
    };

    xdg.dataFile = lib.mkIf isLinux {
      "komai/themes/dark-catppuccin-stylix.yml".source = darkTheme;
      "komai/themes/light-catppuccin-stylix.yml".source = lightTheme;
    };

    # Komai owns the rest of each profile config. Merge only the theme choice so
    # account settings remain writable while every existing profile follows the
    # OS between the paired generated light and dark themes.
    home.activation.komaiTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${themePython}/bin/python3 ${./theme-config.py} ${lib.escapeShellArg profileConfigRoot}
    '';
  };
}
