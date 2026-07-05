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
