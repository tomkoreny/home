{
  pkgs,
  lib,
  ...
}: let
  version = "0.8.5.1";

  # Helium Browser - privacy-focused Chromium fork
  # Not yet in nixpkgs. Using AppImage for Linux, Homebrew cask for macOS.
  # Track upstream: https://github.com/imputnet/helium-linux
  # macOS: managed via Homebrew cask in systems/aarch64-darwin/macos/default.nix
  helium-browser = pkgs.appimageTools.wrapType2 {
    pname = "helium-browser";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
      hash = "sha256-jFSLLDsHB/NiJqFmn8S+JpdM8iCy3Zgyq+8l4RkBecM=";
    };
    extraPkgs = pkgs: with pkgs; [
      nss nspr atk at-spi2-atk cups dbus libdrm gtk3 pango cairo
      xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext
      xorg.libXfixes xorg.libXrandr xorg.libxcb mesa expat alsa-lib
    ];
  };
in {
  home.packages = lib.optionals pkgs.stdenv.isLinux [
    helium-browser
  ];

  home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux {
    BROWSER = "helium-browser";
  };

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "text/html" = ["helium-browser.desktop"];
      "application/xhtml+xml" = ["helium-browser.desktop"];
      "x-scheme-handler/http" = ["helium-browser.desktop"];
      "x-scheme-handler/https" = ["helium-browser.desktop"];
      "x-scheme-handler/about" = ["helium-browser.desktop"];
      "x-scheme-handler/unknown" = ["helium-browser.desktop"];
    };
  };
}
