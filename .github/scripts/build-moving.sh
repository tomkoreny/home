#!/usr/bin/env bash
# Build the packages that move with each scheduled update and that hosts would
# otherwise be the first to build.
#
# Building the whole system is not practical on a hosted runner: its closure is
# ~40 GiB and a fresh runner would compile thousands of derivations (NVIDIA
# driver, JetBrains, ...) every hour. What breaks in practice is narrower:
# - source-built flake inputs that change with every lock update and are in no
#   binary cache: omp (a stale native-addon stamp left every host failing to
#   upgrade in September 2026) and herdr;
# - the Linux packages behind the release pins in bump-pins.py, which are
#   cheap downloads or small builds.
# Everything is taken from the host configuration so overrides and `follows`
# match exactly what the hosts build.
set -euo pipefail

nix build --no-link --print-build-logs --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    tom = flake.nixosConfigurations.nixos.config.home-manager.users.tom;
    fromHome = name:
      lib.findFirst (p: lib.getName p == name)
        (throw "${name} is no longer in tom@nixos home.packages; update build-moving.sh")
        tom.home.packages;
  in
  [
    tom.programs.omp.package
    flake.inputs.herdr.packages.x86_64-linux.default
  ]
  ++ map fromHome [ "helium-browser" "betterbird" "orca-ide" "komai" "jellyfin-mpv-shim" ]'
