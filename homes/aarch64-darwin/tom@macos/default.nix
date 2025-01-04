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
  # All other arguments come from the system system.
  config,
  ...
}: {
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.ansible
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.nodejs
    pkgs.jetbrains.webstorm
#    pkgs.ghostty

    (pkgs.discord.override {
      # withOpenASAR = true; # can do this here too
      withVencord = true;
    })

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.raycast
#    pkgs.teams
  ];
  home.stateVersion = "24.05";
  programs.wezterm.enable = true;
  programs.wezterm.extraConfig = ''
    return {
      front_end = "WebGpu",
      enable_wayland = false,
      default_prog = { '/run/current-system/sw/bin/bash' },
    }
  '';

  home.activation = {
    rsync-home-manager-applications = lib.hm.dag.entryAfter ["writeBoundary"] ''
      rsyncArgs="--archive --checksum --chmod=-w --copy-unsafe-links --delete"
      apps_source="$genProfilePath/home-path/Applications"
      moniker="Home Manager Trampolines"
      app_target_base="${config.home.homeDirectory}/Applications"
      app_target="$app_target_base/$moniker"
      mkdir -p "$app_target"
      ${pkgs.rsync}/bin/rsync $rsyncArgs "$apps_source/" "$app_target"
    '';
    set-wallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
      /usr/bin/osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"/Users/tom/home/modules/darwin/stylix/wallpaper.png\" as POSIX file"
    '';
  };
}
