{
  pkgs,
  ...
}:
{
  # NOTE: all modules under modules/home/ are auto-imported by Snowfall Lib —
  # no explicit imports needed here, just per-host knobs.

  tomkoreny.waybar.outputs = [
    "DP-2"
    "DP-4"
  ];

  # Always show notifications on the main screen (Dell AW3225QF = DP-4),
  # never the second monitor.
  tomkoreny.mako.output = "DP-4";

  home.packages = [
    pkgs.sshpass
    pkgs.atool
    pkgs.docker
    pkgs.wl-clipboard
    pkgs.cliphist # clipboard history (see Hyprland exec-once + Super+Shift+V)
    pkgs.hyprshot # screenshots (see Hyprland Print binds)
    pkgs.libnotify # notify-send, used by hyprshot to confirm captures
    pkgs.teams-for-linux
    pkgs.slack
    pkgs.git-credential-oauth
    pkgs.gnome-keyring
    pkgs.seahorse
    pkgs.toybox
    pkgs.element-desktop
    pkgs.prismlauncher
    pkgs.remmina
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.whitelist.prefix = [ "/home/tom/projects" ];
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
