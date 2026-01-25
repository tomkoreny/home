# Shared configuration values used across NixOS and Darwin
# This reduces duplication and provides a single source of truth
#
# Usage in system configs:
#   let common = import ../../../lib/common {}; in { ... }
#
# Then access: common.user.name, common.network.localDns, etc.
{ lib ? null, ... }:
rec {
  # User identity - used in git config, user definitions, etc.
  user = {
    name = "tom";
    fullName = "Tom Koreny";
    email = "tom@tomkoreny.com";
    
    # Platform-specific home directory
    homeDir = { isDarwin ? false }: 
      if isDarwin then "/Users/${user.name}" else "/home/${user.name}";
  };

  # Network configuration
  network = {
    # Local DNS server (AdGuard Home)
    localDns = "192.168.1.93";
    
    # Home repository URL for auto-upgrade
    repoUrl = "https://github.com/tomkoreny/home.git";
  };

  # Docker daemon configuration
  docker = {
    # Insecure registries (internal harbor, etc.)
    insecureRegistries = [ "harbor.acho.loc:443" ];
    
    # DNS options for containers
    dnsOpts = [ "ndots:0" ];
    
    # Generate address pools programmatically (requires lib)
    # Usage: common.docker.addressPools lib
    addressPools = l: l.genList (i: {
      base = "172.${toString (17 + i)}.0.0/16";
      size = 24;
    }) 10;
  };

  # Stylix theme base configuration
  # Usage: common.stylix.base pkgs // { fonts.sizes = ...; }
  stylix = {
    # Shared wallpaper (relative to this file)
    wallpaper = ./wallpaper.png;

    # Core theme settings (shared across all platforms)
    base = pkgs: {
      enable = true;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
      override.base00 = "#000000"; # OLEDpuccin - true black
      opacity = {
        applications = 1.0;
        terminal = 1.0;
        desktop = 1.0;
        popups = 1.0;
      };
    };
    
    # Shared fonts (used everywhere)
    fonts = pkgs: inputs: {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };
      serif = {
        package = inputs.apple-fonts.packages.${pkgs.system}.ny-nerd;
        name = "NYDisplay Nerd Font";
      };
    };
    
    # Unified font sizes (all platforms)
    fontSizes = { applications = 12; terminal = 13; desktop = 10; popups = 10; };
    
    # Cursor theme (NixOS only, Darwin uses system cursor)
    cursor = pkgs: {
      package = pkgs.rose-pine-cursor;
      name = "BreezeX-RosePine-Linux";
      size = 32;
    };
  };

  # Nix binary caches (shared between NixOS and Darwin)
  nix = {
    substituters = [
      "https://cache.nixos.org/"
      "https://hyprland.cachix.org"
    ];
    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0g7Cz6y5T3J5iCkqDPe7t3BhY1zYdg="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };
}
