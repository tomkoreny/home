{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-core";
  version = "0.1.21";

  # Upstream's static release binary. nixpkgs builds herdr-core from source
  # but trails the releases (0.1.15 against 0.1.20 in November 2026), and
  # upstream moves the app and the core together.
  src = fetchurl {
    url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-linux-x86_64.tar.gz";
    hash = "sha256-eEJHVcEKQN3jigvbVcIKwZcG6a4F7Wj8Ks8fz/DZQcE=";
  };

  sourceRoot = ".";

  installPhase = ''
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
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
