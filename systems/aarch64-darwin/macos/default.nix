{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
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
  common = import ../../../lib/common { };

  # Shortcuts for frequently used values
  inherit (common.user) name fullName;
  homeDir = common.user.homeDir { isDarwin = true; };
  homeManagerApps = "${homeDir}/Applications/Home Manager Apps";
in
{
  # Enable auto-upgrade from git
  tomkoreny.darwin.auto-upgrade.enable = true;
  # Avoid collisions with pre-existing manual backups like ~/.ssh/config.bak.
  home-manager.backupFileExtension = "hm-bak";

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
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
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
      CustomUserPreferences = {
        "com.apple.controlcenter" = {
          "NSStatusItem Preferred Position Battery" = 213;
          "NSStatusItem Preferred Position BentoBox" = 147;
          "NSStatusItem Preferred Position BentoBox-0" = 133;
          "NSStatusItem Preferred Position FocusModes" = 304;
          "NSStatusItem Preferred Position NowPlaying" = 304;
          "NSStatusItem Preferred Position WiFi" = 175;
          "NSStatusItem Visible BentoBox" = true;
          "NSStatusItem Visible FaceTime" = false;
          "NSStatusItem VisibleCC Battery" = true;
          "NSStatusItem VisibleCC BentoBox-0" = true;
          "NSStatusItem VisibleCC Clock" = true;
          "NSStatusItem VisibleCC FocusModes" = true;
          "NSStatusItem VisibleCC NowPlaying" = true;
          "NSStatusItem VisibleCC WiFi" = true;
        };
        "com.apple.Siri" = {
          StatusMenuVisible = false;
        };
        "com.apple.Spotlight" = {
          MenuItemHidden = true;
        };
      };
      controlcenter = {
        AirDrop = false;
        BatteryShowPercentage = false;
        Bluetooth = false;
        Display = false;
        FocusModes = true;
        NowPlaying = true;
        Sound = false;
      };
      dock = {
        persistent-apps = [
          "/Applications/Helium.app"
          "${homeManagerApps}/Betterbird.app"
          "/Applications/Element Nightly.app"
          "/System/Applications/Calendar.app"
          "/System/Applications/Notes.app"
          "/Applications/Ghostty.app"
          "/Applications/Codex.app"
          "/Applications/Claude.app"
          "${homeDir}/Applications/WebStorm.app"
          "${homeManagerApps}/DataGrip.app"
          "${homeDir}/Applications/PyCharm.app"
          "${homeManagerApps}/Zed.app"
          "${homeDir}/Applications/Android Studio.app"
          "/Applications/Original Prusa Drivers/PrusaSlicer.app"
          "/Applications/Bitwarden.app"
          "/Applications/OrbStack.app"
        ];
        autohide = true;
        magnification = false;
        minimize-to-application = true;
        show-process-indicators = true;
        show-recents = false;
        tilesize = 44;
      };
      menuExtraClock = {
        Show24Hour = true;
        ShowAMPM = false;
        ShowDate = 0;
        ShowDayOfWeek = true;
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
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];
  };

  users.knownUsers = [ name ];
  users.users.${name} = {
    uid = 501;
    description = fullName;
    shell = pkgs.bashInteractive;
  };
  services.tailscale.enable = true;
  environment.etc."resolver/ts.net".enable = lib.mkForce false;
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
    onActivation.extraFlags = [
      # Overwrite pre-existing app bundles and binaries when a declarative cask collides.
      "--force"
    ];
    casks = [
      # Development
      "android-commandlinetools"
      "android-platform-tools"
      "android-studio"
      "arduino-ide"
      "flutter"
      "kicad"
      "temurin"
      "vscodium"

      # Browsers
      "helium-browser"
      "tor-browser"
      "zen"

      # Communication
      "beeper"
      "discord"
      "element@nightly"
      "loom"
      "microsoft-teams"
      "notion"
      "signal"

      # Productivity
      "affinity-designer"
      "readdle-spark"
      "shottr"
      "xnapper"

      # Infrastructure / Remote
      "anydesk"
      "bitwarden"
      "home-assistant"
      "openclaw"
      "orbstack"
      "rustdesk"
      "teamviewer"
      "wifiman"

      # Media & Entertainment
      "curseforge"
      "multiviewer"
      "spotify"
      "vlc"

      # AI
      "claude"

      # Hardware
      "raspberry-pi-imager"
      "prusaslicer"
    ];
    brews = [
      # Kubernetes & DevOps
      "argocd"
      "cloudflared"

      # Ruby / Rails
      "cocoapods"
      "rbenv"
      "ruby-build"
      "puma/puma/puma-dev"

      # Node
      "nodenv"

      # Web / Servers
      "caddy"
      "mkcert"

      # Databases
      "postgresql"
      "redis"

      # Libraries
      "libyaml"
      "libsodium"
      "vips"

      # Tools
      "git-lfs"
      "hugo"
      "imagemagick"
      "pandoc"
      "python-setuptools"
      "socat"
      "sshpass"
      "uv"
      "wakeonlan"

      # Hardware
      "picotool"
    ];
  };
}
