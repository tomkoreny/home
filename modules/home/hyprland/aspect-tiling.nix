{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.python-xlib
    ps.inotify-simple
  ]);
  controller = pkgs.replaceVars ./aspect-tiling.py {
    fitScript = ./aspect-fit.lua;
  };
in
pkgs.runCommand "hyprland-aspect-tiling" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
  mkdir -p "$out/lib" "$out/bin"
  cp ${controller} "$out/lib/aspect-tiling.py"
  cp ${./aspect_x11.py} "$out/lib/aspect_x11.py"
  makeWrapper ${python}/bin/python3 "$out/bin/hyprland-aspect-tiling" \
    --add-flags "$out/lib/aspect-tiling.py"
''
