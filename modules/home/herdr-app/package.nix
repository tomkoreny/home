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
}:
let
  version = "0.1.15";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://releases.herdr.dev/app/${version}/herdr-app-linux-x86_64.tar.gz";
      hash = "sha256-+Z4eBL6CwOELL2nudAPKNDhvSA2SUR31hlr0cD52Vd0=";
    };

    aarch64-darwin = fetchurl {
      url = "https://releases.herdr.dev/app/${version}/herdr-app-macos-aarch64.tar.gz";
      hash = "sha256-NjPqXYaOpBD4Tfu3eiYgXeMx9N9S/bP7AGsrOXhFhFk=";
    };
  };
in
stdenv.mkDerivation (
  {
    pname = "herdr-app";
    inherit version;

    src =
      sources.${stdenv.hostPlatform.system}
        or (throw "Unsupported Herdr app system: ${stdenv.hostPlatform.system}");

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
      copyDesktopItems
      makeWrapper
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      libxcb
      libxkbcommon
      stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase =
      if stdenv.hostPlatform.isDarwin then
        ''
          runHook preInstall

          # The signed bundle as it is, and its executable under the name the
          # Linux build has, for `herdr-app ls`, `do` and `check`.
          mkdir -p "$out/Applications" "$out/bin"
          cp -R Herdr.app "$out/Applications/Herdr.app"
          ln -s ../Applications/Herdr.app/Contents/MacOS/Herdr "$out/bin/herdr-app"

          runHook postInstall
        ''
      else
        ''
          runHook preInstall

          install -Dm755 herdr-app "$out/libexec/herdr-app/herdr-app"
          install -Dm644 herdr-app.svg "$out/share/icons/hicolor/scalable/apps/herdr-app.svg"
          makeWrapper "$out/libexec/herdr-app/herdr-app" "$out/bin/herdr-app" \
            --set-default HERDR_TELEMETRY 0

          runHook postInstall
        '';

    meta = {
      description = "Desktop app for terminals and coding agents, drawn by editable layouts and mods";
      homepage = "https://github.com/herdrdev/herdr-app";
      license = lib.licenses.asl20;
      mainProgram = "herdr-app";
      platforms = builtins.attrNames sources;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    sourceRoot = "herdr-app";

    # GPUI opens these at run time instead of linking them, so they are absent
    # from the binary's NEEDED entries and autoPatchelf cannot find them.
    runtimeDependencies = [
      libglvnd
      vulkan-loader
      wayland
    ];

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
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    sourceRoot = ".";
    # Stripping or patching a file would break the bundle's signature, and the
    # bundle cannot be wrapped for the same reason.
    dontFixup = true;
  }
)
