{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "orca-ide";
  version = "1.4.254";
  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-PH9bBqFSurfe+keW9H8zCuJFl0Mt1/AqyqBSSH2A8RY=";
  };
  contents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/orca-ide.desktop $out/share/applications/orca-ide.desktop
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=orca-ide'
    install -Dm444 ${contents}/orca-ide.png $out/share/icons/hicolor/512x512/apps/orca-ide.png
  '';

  meta = {
    description = "Agent development environment for parallel coding agents";
    homepage = "https://www.onorca.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca-ide";
  };
}
