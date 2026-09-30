{
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
in
{
  # NOTE: all modules under modules/home/ are auto-imported by Snowfall Lib —
  # no explicit imports needed here, just per-host settings.

  home.username = "tom";
  home.homeDirectory = "/Users/tom";

  tomkoreny.komai.enable = true;
  # Status island in the menu bar: Notion todos, Polaris tasks, timers, herdr, AI usage.
  tomkoreny.sketchybar.enable = true;
  # Tiling with Caps Lock as Super, mirroring the Hyprland binds.
  tomkoreny.aerospace.enable = true;
  # The Waveshare bar panel to the left shows a BetterDisplay stream of the
  # WSMirror virtual screen; its own 740x160 display is covered by that stream.
  # Workspaces 1-5 and S stay on the MacBook, 6-10 live on the panel (and come
  # home when it is unplugged), like the Hyprland workspace columns.
  tomkoreny.aerospace.parkedMonitors = [ "WaveShsare" ];
  tomkoreny.aerospace.workspaceMonitors =
    lib.genAttrs [ "1" "2" "3" "4" "5" "S" ] (_: [ "built-in" ])
    // lib.genAttrs [ "6" "7" "8" "9" "10" ] (_: [
      "WSMirror"
      "built-in"
    ]);
  tomkoreny.bar-backends.workTasks = {
    enable = true;
    provider = "mantisbt";
    baseUrl = "https://polaris.i2ginfra.cz";
    label = "Polaris";
    sopsFile = ../../../secrets/polaris/work-tasks.json;
  };
  home.packages = [
    pkgs.raycast
  ];
  home.stateVersion = "24.05";
  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };

  home.activation = {
    # Use the store path of the shared wallpaper so this works regardless of
    # where the repo checkout lives.
    set-wallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /usr/bin/osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${common.stylix.wallpaper}\" as POSIX file"
    '';
  };
}
