{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  libglvnd,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
}:
let
  version = "0.3.0";
in
stdenv.mkDerivation {
  pname = "daruda";
  inherit version;

  src = fetchurl {
    url = "https://github.com/daruda-ai/daruda/releases/download/v${version}/daruda-${version}-linux-x86_64.deb";
    hash = "sha256-WHb6mKT6Yng9sgXaoBB5fJZEvSh0JQ1WBCgWBZOBPy0=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
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

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r usr/bin usr/share "$out/"

    runHook postInstall
  '';

  meta = {
    description = "Native workspace for running coding agents side by side";
    homepage = "https://github.com/daruda-ai/daruda";
    license = lib.licenses.agpl3Only;
    mainProgram = "daruda";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
