{
  pkgs,
  lib,
  ...
}:
{
  # MultiViewer (F1 viewer) is packaged in nixpkgs — no need for the old
  # hand-rolled .deb repack with its hardcoded download-ID URL.
  home.packages = lib.optionals pkgs.stdenv.isLinux [
    pkgs.multiviewer-for-f1
  ];
}
