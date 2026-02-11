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
  home, # The home architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this home (eg. `x86_64-home`).
  format, # A normalized name for the home target (eg. `home`).
  virtual, # A boolean to determine whether this home is a virtual target using nixos-generators.
  host, # The host name for this home.
  # All other arguments come from the home home.
  config,
  ...
}: {
  imports = [
    (import ../../../modules/home/waybar {
      inherit lib pkgs;
      outputs = [
        "DP-2"
        "DP-4"
      ];
    })
    ../../../modules/home/kubeconfig
    ../../../modules/home/helium
  ];

  home.packages = [
    pkgs.sshpass
    pkgs.atool
    pkgs.docker
    pkgs.wl-clipboard
    pkgs.tiramisu
    pkgs.teams-for-linux
    pkgs.slack
#    pkgs.rustdesk

    pkgs.thunderbird
    pkgs.hypridle
    pkgs.git-credential-oauth
    pkgs.gnome-keyring
    pkgs.seahorse
    pkgs.toybox
    pkgs.element-desktop
    pkgs.prismlauncher
    pkgs.qmk
    pkgs.remmina
  ];
  home.sessionPath = [
    "/home/tom/.local/share/JetBrains/Toolbox/apps"
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.whitelist.prefix = ["/home/tom/projects"];
  };

  # The state version is required and should stay at the version you
  # originally installed.
  home.stateVersion = "24.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  programs = {
    wofi.enable = true; # required for the default Hyprland config
  };
  programs.tmux.enable = true;
  programs.tmux.sensibleOnTop = true;
}
