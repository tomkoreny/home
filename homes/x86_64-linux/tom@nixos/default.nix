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
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerdfetch
    pkgs.sshpass
    pkgs.ansible
    pkgs.atool
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.httpie
    pkgs.docker
    pkgs.wl-clipboard
    pkgs.nodejs
    pkgs.node-gyp
    pkgs.tiramisu
    pkgs.teams-for-linux
    # (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.webstorm ["github-copilot"])
    pkgs.jetbrains.webstorm
    pkgs.beeper
    pkgs.ghostty

    pkgs.nodePackages.vercel

    (pkgs.discord.override {
      # withOpenASAR = true; # can do this here too
      withVencord = true;
    })

    pkgs.thunderbird
    pkgs.hypridle
    pkgs.git-credential-oauth
    pkgs.gnome-keyring
    pkgs.seahorse
    pkgs.toybox
    pkgs.typescript
    pkgs.typescript-language-server
    pkgs.element-desktop
    pkgs.prismlauncher
    pkgs.qmk
  ];

  programs.waybar = {
    enable = true;
    settings = lib.importJSON ./config/waybar/config.json;
  };

  home.file.".config/waybar/scripts/polytiramisu.sh" = {
    source = ./config/waybar/polytiramisu.sh;
  };
  # The state version is required and should stay at the version you
  # originally installed.
  home.stateVersion = "24.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  programs = {
    #    kitty.enable = true; # required for the default Hyprland config
    wofi.enable = true; # required for the default Hyprland config
    #nvidia fix :(
    chromium = {
      commandLineArgs = [
        "--disable-gpu-compositing"
      ];
    };
  };
  programs.tmux.enable = true;
  programs.tmux.sensibleOnTop = true;
}
