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
# - the Linux packages behind the release pins and rolling downloads in
#   bump-pins.py, which are cheap downloads or small builds;
# - the Steam skin from modules/home/steam-theme, which follows upstream's
#   branch and fails to build when upstream renames a variable it overrides;
# - the herdr-chat mod from modules/home/herdr-app, whose build loads it in
#   the Herdr app and fails when a bumped app no longer accepts it.
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
    tom.xdg.dataFile."Steam/millennium/themes/adwaita-stylix".source
    tom.tomkoreny.herdr-app.chatPackage
  ]
  ++ map fromHome [ "helium-browser" "betterbird" "orca-ide" "komai" "jellyfin-mpv-shim" "moshi-hook" "flectar-mail" "herdr-app" "herdr-core" ]'
