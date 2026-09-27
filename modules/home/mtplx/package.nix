{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mtplx";
  version = "2.12.0";

  src = fetchurl {
    url = "https://github.com/youssofal/MTPLX/releases/download/v${finalAttrs.version}/MTPLX-${finalAttrs.version}.dmg";
    hash = "sha256-wsBbgn4oJK/BU10IEEuSPKGtxMIdmf73Hw5JtlWY3Gc=";
  };

  nativeBuildInputs = [ _7zz ];

  # MTPLX ships an APFS disk image, which undmg cannot extract.
  unpackPhase = ''
    runHook preUnpack
    7zz x -x'!Applications' "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    mv MTPLX.app "$out/Applications/MTPLX.app"

    runHook postInstall
  '';

  # Preserve the upstream code signature and stapled notarization ticket.
  dontFixup = true;

  meta = {
    description = "Native MTP speculative decoding for Apple Silicon";
    homepage = "https://github.com/youssofal/MTPLX";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
