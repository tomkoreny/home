# Terka's home config. She uses the NixOS desktop over SSH only.
# All modules under modules/home/ are shared with tom's home (they come in via
# home-manager.sharedModules in flake.nix); this file only overrides what
# differs for her.
{ lib, ... }:
{
  home.username = "terka";
  home.homeDirectory = "/home/terka";

  # No graphical session: leave out the compositor and the GUI applications.
  tomkoreny.desktop.enable = false;

  # The shared git module sets tom's identity; override it for her.
  programs.git.settings.user = {
    name = lib.mkForce "Terka";
    email = lib.mkForce "mvdr@terka.vet";
  };

  # First installed mid-2026; do not change.
  home.stateVersion = "25.05";
}
