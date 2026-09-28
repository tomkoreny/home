# The omp package every user gets; not a module (autoModules only imports
# directories), imported by ./default.nix and ../agents/default.nix.
#
# Two Darwin-only repairs of upstream's nix/package.nix:
#
# 1. Since 18.3.2 omp refuses to embed a native addon without its post-link
#    version stamp, but upstream builds the addon with plain cargo and never
#    stamps it, so every Nix build fails. Stamp it between the cargo build and
#    the Bun compile. Guarded so this is a no-op once upstream's buildPhase
#    stamps the addon itself; delete it then.
#
#    The stamp script re-signs the patched Mach-O by spawning `codesign` from
#    PATH, which the sandbox lacks. sigtool ships a drop-in `codesign` (the one
#    upstream's own `signIfRequired` calls by absolute path); it needs
#    CODESIGN_ALLOCATE because the sandbox cannot reach /usr/bin either.
#
# 2. Since 18.3.5 pi-natives carries a Swift bridge to Apple Foundation Models.
#    Its build.rs probes the host through /usr/bin/xcrun and the Command Line
#    Tools (the Darwin sandbox is off), finds Swift 6.4 with the macOS 27 SDK,
#    compiles the bridge, and asks the linker to weak-link that SDK's
#    FoundationModels.tbd. nixpkgs' ld64 cannot parse it ("malformed file ...
#    arm64e.x1-macos"), drops it, and the framework's 372 symbols end up as
#    flat-namespace weak imports bound to NULL. On macOS 27 the bridge passes
#    its OS-version gate at startup and calls address 0: SIGSEGV on a "Bun
#    Pool" thread within a second of the TUI drawing. Neuter the toolchain
#    probe so build-bridge.sh takes its supported no-toolchain path and builds
#    stub.c, which reports the bridge as not built; the on-device Apple model
#    provider is then simply absent. Delete once upstream links the bridge
#    with a linker that reads the SDK 27 tbd, or gates the probe on an env var.
{
  inputs,
  lib,
  pkgs,
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  upstream = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  stampsItself = lib.hasInfix "stamp-native-version" upstream.buildPhase;
in
upstream.overrideAttrs (old: {
  postPatch =
    (old.postPatch or "")
    + lib.optionalString isDarwin ''
      substituteInPlace crates/pi-natives/src/applefm/build-bridge.sh \
        --replace-fail 'detect) detect ;;' 'detect) ;;'
    '';
}
// lib.optionalAttrs (!stampsItself) {
  nativeBuildInputs = old.nativeBuildInputs ++ lib.optional isDarwin pkgs.darwin.sigtool;
  env =
    old.env
    // lib.optionalAttrs isDarwin {
      CODESIGN_ALLOCATE = "${pkgs.darwin.cctools}/bin/codesign_allocate";
    };
  buildPhase =
    builtins.replaceStrings
      [ ''echo "Compiling OMP"'' ]
      [
        ''
          for addon in packages/natives/native/pi_natives.*.node; do
            bun scripts/stamp-native-version.ts "$addon"
          done
          echo "Compiling OMP"''
      ]
      old.buildPhase;
})
