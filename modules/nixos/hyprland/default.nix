{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,
  # Additional metadata is provided by Snowfall Lib.
  namespace, # The namespace used for your flake, defaulting to "internal" if not set.
  system, # The system architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
  format, # A normalized name for the system target (eg. `iso`).
  virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
  systems, # An attribute map of your defined hosts.
  # All other arguments come from the module system.
  config,
  ...
}: {
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM  = true;

  # The hyprland input tracks main, which since v0.56 reports workspaces as
  # {address, type, name} without a numeric "id" in hyprctl JSON and socket2
  # selectors. Quickshell 0.3.1 keys its Hyprland workspace model on "id", so
  # every workspace parsed as 0 and collapsed into one entry, blanking the bar's
  # workspace strip. Upstream Quickshell has no fix yet; drop this once it does.
  nixpkgs.overlays = [
    (final: prev: {
      quickshell = prev.quickshell.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./quickshell-hyprland-workspace-address.patch ];
      });
    })
  ];
}
