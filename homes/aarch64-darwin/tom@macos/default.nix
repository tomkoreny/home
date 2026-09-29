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
