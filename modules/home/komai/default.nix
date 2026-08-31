{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.komai;
  version = "2026.08.24.1";
  src = pkgs.fetchurl {
    url = "https://github.com/etkecc/komai/releases/download/v${version}/komai-${version}-x86_64.AppImage";
    hash = "sha256-Zh+TIx+TVaixE3wS0+CJxewJvs1O7F0oQLFe8Zut5qw=";
  };
  appimageContents = pkgs.appimageTools.extract {
    pname = "komai";
    inherit version src;
    postExtract = ''
      # Upstream records Ubuntu's oldest supported glibc (2.20), causing AppRun
      # to prefer NixOS's 2.42 over the bundled 2.43 compatibility runtime.
      # Record the actual build glibc so AppRun selects its compatible runtime.
      substituteInPlace $out/AppRun.env \
        --replace-fail 'APPDIR_LIBC_VERSION=2.20' 'APPDIR_LIBC_VERSION=2.43'
      ln -s usr/lib64 $out/runtime/compat/lib64
    '';
  };
  komai = pkgs.appimageTools.wrapAppImage {
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
    meta = {
      description = "Native Matrix desktop client";
      homepage = "https://komai.chat";
      license = lib.licenses.gpl3Plus;
      mainProgram = "komai";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  options.tomkoreny.komai.enable = lib.mkEnableOption "the Komai Matrix client";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The Komai module currently packages only the x86_64 Linux release.";
      }
    ];

    home.packages = [ komai ];
  };
}
