# Terka's home config — second seat (seat1) on the NixOS desktop.
# All modules under modules/home/ are shared with tom's home (they come in via
# home-manager.sharedModules in flake.nix); this file only overrides what
# differs for her.
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home.username = "terka";
  home.homeDirectory = "/home/terka";

  # Her monitor hangs off the iGPU, whose connectors are DP-1/HDMI-A-1.
  # Listing both means the bar shows up regardless of which port is used.
  tomkoreny.waybar.outputs = [
    "DP-1"
    "HDMI-A-1"
  ];

  # The shared git module sets tom's identity; override it for her.
  programs.git.settings.user = {
    name = lib.mkForce "Terka";
    email = lib.mkForce "mvdr@terka.vet";
  };

  # Replace tom's Hyprland config wholesale: his Lua config pins monitors by
  # EDID and disables every unmatched output, which would blank her screen;
  # his startup commands also go through UWSM.
  wayland.windowManager.hyprland.extraConfig = lib.mkForce (builtins.readFile ./hyprland.lua);

  home.packages = [
    # Referenced by binds in hyprland.lua (tom carries these in his own home
    # config, not in a shared module)
    pkgs.wl-clipboard
    pkgs.cliphist
    # Keep hyprshot on the same upstream package as the running compositor;
    # nixpkgs' independently packaged Hyprland can diverge or fail to build.
    (pkgs.hyprshot.override {
      hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    })
    pkgs.libnotify

    # Run an app on the NVIDIA dGPU while the desktop itself runs on the iGPU:
    # render nodes are not seat-bound, so PRIME offload works from seat1.
    # Usage: `nvidia-run <game>`, or `nvidia-run %command%` in Steam.
    (pkgs.writeShellScriptBin "nvidia-run" ''
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      exec "$@"
    '')
  ];

  programs.wofi.enable = true; # app launcher used by the Super+R bind

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    # The system-wide session variables point VA-API/VDPAU at NVIDIA; this
    # seat renders on the AMD iGPU.
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
  };

  # First installed mid-2026; do not change.
  home.stateVersion = "25.05";
}
