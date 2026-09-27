# The omp package every user gets; not a module (autoModules only imports
# directories), imported by ./default.nix and ../agents/default.nix.
#
# Since 18.3.2 omp refuses to embed a native addon without its post-link
# version stamp, but upstream's nix/package.nix builds the addon with plain
# cargo and never stamps it, so every Nix build fails. Stamp it between the
# cargo build and the Bun compile. Guarded so this is a no-op once upstream's
# buildPhase stamps the addon itself; delete it then.
#
# On Darwin the stamp script re-signs the patched Mach-O by spawning
# `codesign` from PATH, which the sandbox lacks. sigtool ships a drop-in
# `codesign` (the one upstream's own `signIfRequired` calls by absolute path);
# it needs CODESIGN_ALLOCATE because the sandbox cannot reach /usr/bin either.
{
  inputs,
  lib,
  pkgs,
}:
let
  upstream = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp;
in
if lib.hasInfix "stamp-native-version" upstream.buildPhase then
  upstream
else
  upstream.overrideAttrs (old: {
    nativeBuildInputs =
      old.nativeBuildInputs
      ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.sigtool;
    env =
      old.env
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
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
