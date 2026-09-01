{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.komai;
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
  };
}
