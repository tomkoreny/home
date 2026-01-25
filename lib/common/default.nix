# Shared configuration values used across NixOS and Darwin
# This reduces duplication and provides a single source of truth
{ lib, ... }:
{
  # User identity - used in git config, user definitions, etc.
  user = {
    name = "tom";
    fullName = "Tom Koreny";
    email = "tom@tomkoreny.com";
    
    # Platform-specific home directory
    homeDir = system:
      if lib.strings.hasInfix "darwin" system
      then "/Users/tom"
      else "/home/tom";
  };

  # Network configuration
  network = {
    # Local DNS server (Pi-hole, AdGuard, etc.)
    localDns = "192.168.1.93";
    
    # Home repository URL for auto-upgrade
    repoUrl = "https://github.com/tomkoreny/home.git";
  };

  # Stylix theme base configuration
  # Import and extend with platform-specific font sizes
  stylix = { pkgs }: {
    enable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    override.base00 = "#000000"; # True black background
    opacity = {
      applications = 1.0;
      terminal = 1.0;
      desktop = 1.0;
      popups = 1.0;
    };
  };

  # Generate Docker address pools programmatically
  # Instead of manually listing 10 identical entries
  dockerAddressPools = lib.genList (i: {
    base = "172.${toString (17 + i)}.0.0/16";
    size = 24;
  }) 10;
}
