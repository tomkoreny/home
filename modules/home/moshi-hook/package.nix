{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "moshi-hook";
  version = "0.4.12";

  # Upstream publishes only prebuilt archives on its CDN (the Homebrew tap
  # points at the same files). The hash matches upstream's checksums.txt.
  src = fetchurl {
    url = "https://cdn.getmoshi.app/hook/v${finalAttrs.version}/moshi-hook_Linux_x86_64.tar.gz";
    hash = "sha256-2oKfOzYNPM6BdjmzI2aJr3wpHNkVypZPJ8PHHnTOkG4=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 moshi-hook "$out/bin/moshi-hook"
    # The upstream installer adds the short `moshi` alias next to the daemon.
    ln -s moshi-hook "$out/bin/moshi"

    runHook postInstall
  '';

  meta = {
    description = "Companion daemon that connects local coding agents to the Moshi mobile terminal";
    homepage = "https://getmoshi.app/docs/hooks";
    license = lib.licenses.unfree;
    mainProgram = "moshi-hook";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
