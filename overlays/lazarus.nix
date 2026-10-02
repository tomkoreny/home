# nixpkgs' makeWrapper now rejects empty PATH-like segments, and lazarus's
# postInstall passes `--prefix NIX_LDFLAGS` a value with leading/trailing
# spaces left over from stripping `-rpath` flags. lazarus-qt6 therefore fails
# to build, and goverlay (which depends on it) takes the whole system with it.
# This applies NixOS/nixpkgs#568901, merged to master on 2026-10-01 but not yet
# in nixos-unstable. Once the locked nixpkgs carries it, evaluation warns and
# this file should be deleted.
final: prev:
let
  broken = "sed -re 's/-rpath [^ ]+//g')";
  fixed = "sed -re 's/-rpath [^ ]+//g' | sed -re 's/(^ *| *$)//g;')";
  fixLazarus =
    package:
    package.overrideAttrs (old: {
      postInstall =
        if prev.lib.hasInfix broken old.postInstall then
          prev.lib.replaceStrings [ broken ] [ fixed ] old.postInstall
        else
          prev.lib.warn "overlays/lazarus.nix: nixpkgs already fixes lazarus's wrapper; delete this overlay" old.postInstall;
    });
in
{
  lazarus = fixLazarus prev.lazarus;
  lazarus-qt = fixLazarus prev.lazarus-qt;
  lazarus-qt6 = fixLazarus prev.lazarus-qt6;
}
