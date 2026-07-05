{
  pkgs,
  lib,
  ...
}:
let
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
in
{
  home.packages = lib.optionals pkgs.stdenv.isLinux [
    helium-browser
  ];

  home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux {
    BROWSER = "helium-browser";
  };

  # The AppImage wrapper ships no desktop entry, so provide one — without it
  # the mimeApps defaults below point at a .desktop file that doesn't exist
  # and xdg-open/portal default-browser resolution fails.
  xdg.desktopEntries.helium-browser = lib.mkIf pkgs.stdenv.isLinux {
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

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
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
