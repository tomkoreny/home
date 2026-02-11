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
      # Run `nix build` once to get the real hash, then replace this:
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
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
}
