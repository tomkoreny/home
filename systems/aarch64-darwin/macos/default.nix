{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  # lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,
  # Additional metadata is provided by Snowfall Lib.
  # namespace, # The namespace used for your flake, defaulting to "internal" if not set.
  # system, # The system architecture for this host (eg. `x86_64-linux`).
  # target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
  # format, # A normalized name for the system target (eg. `iso`).
  # virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
  # systems, # An attribute map of your defined hosts.
  # All other arguments come from the system system.
  config,
  ...
}: 
let
  # Import shared configuration from lib/common
  common = import ../../../lib/common {};
  
  # Shortcuts for frequently used values
  inherit (common.user) name fullName;
  homeDir = common.user.homeDir { isDarwin = true; };
in {
  # Enable auto-upgrade from git
  tomkoreny.darwin.auto-upgrade.enable = true;

  imports = [
    ../../../modules/darwin/vpn
  ];

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [
    pkgs.rustc
    pkgs.rustup
  ];

  # Necessary for using flakes on this system.
  nix.channel.enable = false;

  # Nix settings for faster builds
  nix.settings = {
    experimental-features = "nix-command flakes";

    # Binary caches - CRITICAL for build speed
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWz7Cz6y5T3J5iCkqDPe7t3BhY1zYdg="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Performance optimizations
    max-jobs = "auto";
    cores = 0; # Use all cores

    # Keep build dependencies for faster rebuilds
    keep-outputs = true;
    keep-derivations = true;
  };

  # Make `nix shell nixpkgs#foo` use locked nixpkgs
  nix.optimise.automatic = true;
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  networking.hostName = "macos"; # Define your hostname.
  networking.knownNetworkServices = [
    "Wi-Fi"
    "Thunderbolt Bridge"
  ];
  system = {
    # Enable alternative shell support in nix-darwin.
    # programs.fish.enable = true;

    # Set Git commit hash for darwin-version.
    #      system.configurationRevision = self.rev or self.dirtyRev or null;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    stateVersion = 5;
    defaults = {
      dock = {
        persistent-apps = [
          "${pkgs.google-chrome}/Applications/Google Chrome.app"
          "${homeDir}/Applications/Home Manager Trampolines/WebStorm.app"
          "${homeDir}/Applications/Home Manager Trampolines/Ghostty.app"
        ];
        show-recents = false;
        autohide = true;
      };
    };
    primaryUser = name;

    #    activationScripts.postUserActivation.text = ''
    #      apps_source="${config.system.build.applications}/Applications"
    #      moniker="Nix Trampolines"
    #      app_target_base="$HOME/Applications"
    #      app_target="$app_target_base/$moniker"
    #      mkdir -p "$app_target"
    #      ${pkgs.rsync}/bin/rsync --archive --checksum --chmod=-w --copy-unsafe-links --delete "$apps_source/" "$app_target"
    #    '';
  };

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";


  launchd.user.envVariables = {
    DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
    SDKROOT = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk";
    ANDROID_SDK_ROOT = "${homeDir}/Library/Android/sdk";
    ANDROID_HOME = "${homeDir}/Library/Android/sdk";
  };

  environment.variables = {
    DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
    # Optional but keeps clang/cctools from the same SDK:
    SDKROOT = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    ANDROID_SDK_ROOT = "${homeDir}/Library/Android/sdk";
    ANDROID_HOME = "${homeDir}/Library/Android/sdk";
  };


  sops = {
    age = {
      keyFile = "${homeDir}/.config/sops/age/keys.txt";
      sshKeyPaths = [];
    };
    gnupg.sshKeyPaths = [];
  };

  users.knownUsers = [ name ];
  users.users.${name} = {
    uid = 501;
    description = fullName;
    shell = pkgs.bashInteractive;
  };
  services.tailscale.enable = true;
  services.tailscale.overrideLocalDns = true;
  nix-homebrew = {
    # Install Homebrew under the default prefix
    enable = true;

    # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
    enableRosetta = true;

    # User owning the Homebrew prefix
    user = name;
    # Optional: Declarative tap management
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "puma/homebrew-puma" = inputs.puma-rails;
    };

    # Optional: Enable fully-declarative tap management
    #
    # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    casks = [
      "android-studio"
      "android-platform-tools"
      "android-commandlinetools"
      "flutter"
      "temurin"
      "orbstack"
      "microsoft-teams"
      "readdle-spark"
      "wifiman"
      "home-assistant"
      "bitwarden"
      "rustdesk"
    ];
    brews = [
      "argocd"
      "cocoapods"
      "cloudflared"
      "mkcert"
      "caddy"
      "rbenv"
      "ruby-build"
      "nodenv"
      "puma/puma/puma-dev"
      "postgresql"
      "redis"
      "libyaml"
      "libsodium"
      "vips"
      "git-crypt"
      "git-lfs"
      "python-setuptools"
    ];
  };
}
