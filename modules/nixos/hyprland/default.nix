{ ... }:
{
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = true;

  # Quickshell needs a patch to follow Hyprland main's workspace IPC schema;
  # see overlays/quickshell.nix.
  nixpkgs.overlays = [ (import ../../../overlays/quickshell.nix) ];
}
