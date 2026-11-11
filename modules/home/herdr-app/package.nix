{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  libglvnd,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
  # Programs that mods run and the login PATH may lack.
  extraPath ? [ ],
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.15";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-linux-x86_64.tar.gz";
    hash = "sha256-+Z4eBL6CwOELL2nudAPKNDhvSA2SUR31hlr0cD52Vd0=";
  };

  sourceRoot = "herdr-app";

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
  ];

  buildInputs = [
    libxcb
    libxkbcommon
    stdenv.cc.cc.lib
  ];

  # GPUI opens these at run time instead of linking them, so they are absent
  # from the binary's NEEDED entries and autoPatchelf cannot find them.
  runtimeDependencies = [
    libglvnd
    vulkan-loader
    wayland
  ];

  dontConfigure = true;
  dontBuild = true;

  # extraPath goes last on PATH, and so into every terminal the app starts,
  # only as a fallback behind what the user's own PATH provides.
  installPhase = ''
    runHook preInstall

    install -Dm755 herdr-app "$out/libexec/herdr-app/herdr-app"
    install -Dm644 herdr-app.svg "$out/share/icons/hicolor/scalable/apps/herdr-app.svg"
    makeWrapper "$out/libexec/herdr-app/herdr-app" "$out/bin/herdr-app" \
      --set-default HERDR_TELEMETRY 0 ${
        lib.optionalString (extraPath != [ ]) "--suffix PATH : ${lib.makeBinPath extraPath}"
      }

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      categories = [ "Development" ];
      startupWMClass = "herdr-app";
    })
  ];

  meta = {
    description = "Desktop app for terminals and coding agents, drawn by editable layouts and mods";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    mainProgram = "herdr-app";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
