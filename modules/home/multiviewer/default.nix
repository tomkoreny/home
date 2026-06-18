{
  pkgs,
  lib,
  ...
}: let
  multiviewer = pkgs.stdenv.mkDerivation rec {
    pname = "multiviewer";
    version = "2.7.1";

    src = pkgs.fetchurl {
      url = "https://releases.multiviewer.app/download/373278730/multiviewer_${version}_amd64.deb";
      hash = "sha256-BKXw8a4fUT+B7KBc6p/Heo+sAtWAG5b/D2iohuNOotY=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
      zstd
    ];

    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      libdrm
      libgbm
      libnotify
      libsecret
      libuuid
      libxkbcommon
      mesa
      nspr
      nss
      pango
      systemd
      libx11
      libxscrnsaver
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
    ];

    unpackPhase = ''
      runHook preUnpack
      ar x $src
      tar --no-same-permissions -xf data.tar.zst
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin $out/share
      cp -R usr/lib/multiviewer $out/lib/
      cp -R usr/share/applications usr/share/pixmaps $out/share/

      makeWrapper $out/lib/multiviewer/multiviewer $out/bin/multiviewer \
        --add-flags "--no-sandbox"

      substituteInPlace $out/share/applications/multiviewer.desktop \
        --replace-fail "Exec=multiviewer %U" "Exec=$out/bin/multiviewer %U"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Motorsport desktop client for watching F1 and more";
      homepage = "https://multiviewer.app";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "multiviewer";
    };
  };
in {
  home.packages = lib.optionals pkgs.stdenv.isLinux [
    multiviewer
  ];
}
