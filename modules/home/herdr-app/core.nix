{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.1.21";

  # Upstream's release builds. nixpkgs builds herdr-core from source but
  # trails the releases (0.1.15 against 0.1.20 in November 2026), and upstream
  # moves the app and the core together.
  sources = {
    x86_64-linux = fetchurl {
      url = "https://releases.herdr.dev/core/${version}/herdr-core-linux-x86_64.tar.gz";
      hash = "sha256-eEJHVcEKQN3jigvbVcIKwZcG6a4F7Wj8Ks8fz/DZQcE=";
    };

    aarch64-darwin = fetchurl {
      url = "https://releases.herdr.dev/core/${version}/herdr-core-macos-aarch64.tar.gz";
      hash = "sha256-GrON2ScPY6j3lNbWDocC6w0chacr2oXXNeXupD8F/+0=";
    };
  };
in
stdenvNoCC.mkDerivation (
  {
    pname = "herdr-core";
    inherit version;

    src =
      sources.${stdenvNoCC.hostPlatform.system}
        or (throw "Unsupported herdr-core system: ${stdenvNoCC.hostPlatform.system}");

    sourceRoot = ".";

    installPhase =
      if stdenvNoCC.hostPlatform.isDarwin then
        ''
          runHook preInstall

          # The whole signed bundle, as upstream's installer keeps it: macOS
          # asks for and remembers what terminal programs may use (the
          # microphone, Documents, other apps) under "Herdr Core", named by
          # the bundle's signature. It is not in Applications/ because it has
          # no window and nothing to launch.
          mkdir -p "$out/share/herdr-core" "$out/bin"
          cp -R "Herdr Core.app" "$out/share/herdr-core/Herdr Core.app"
          ln -s "../share/herdr-core/Herdr Core.app/Contents/MacOS/herdr-core" "$out/bin/herdr-core"
          ln -s herdr-core "$out/bin/hc"

          runHook postInstall
        ''
      else
        ''
          runHook preInstall

          install -Dm755 herdr-core "$out/bin/herdr-core"
          # Upstream's installer puts the short name everyone types beside it.
          ln -s herdr-core "$out/bin/hc"

          runHook postInstall
        '';

    meta = {
      description = "Runs terminals and coding agents that stay alive after their window closes";
      homepage = "https://github.com/herdrdev/herdr-core";
      license = lib.licenses.asl20;
      mainProgram = "hc";
      platforms = builtins.attrNames sources;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
  // lib.optionalAttrs stdenvNoCC.hostPlatform.isDarwin {
    # Stripping or patching a file would break the bundle's signature.
    dontFixup = true;
  }
)
