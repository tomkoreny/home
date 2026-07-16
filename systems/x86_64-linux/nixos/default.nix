{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  # inputs,
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
  inherit (common.network) upstreamDns;
  inherit (common.user) name fullName;
in
{
  tomkoreny.nixos = {
    # TCP tuning + IPv6 privacy-address fixes (module auto-loaded by Snowfall)
    networking-fixes.enable = true;

    # FortiVPN tunnel + its sops secret
    openfortivpn.enable = true;

    # OpenClaw node - connects to gateway via Traefik
    # Same as Mac: clawdbot.home.tomkoreny.com:443 with TLS (defaults)
    clawdbot-node = {
      enable = true;
      displayName = "NixOS Desktop";
    };
  };

  # Pull the latest pushed config and rebuild (CI keeps flake.lock fresh).
  # Fetches straight from GitHub, so there is no local clone to go stale.
  system.autoUpgrade = {
    enable = true;
    flake = "github:tomkoreny/home#nixos";
    operation = "switch";
    dates = "hourly";
    randomizedDelaySec = "10min";
  };

  # Your configuration.
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Note: modules in modules/nixos/ are auto-loaded by Snowfall Lib
    # (openfortivpn, clawdbot-node)
  ];

  # Configure swap file
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 128 * 1024; # 128GB in MB
    }
  ];

  boot = {
    # Bootloader.
    plymouth.enable = true;
    loader = {
      systemd-boot.enable = lib.mkForce false;
      systemd-boot.configurationLimit = 5;
      #boot.loader.systemd-boot.netbootxyz.enable = true;
      efi.canTouchEfiVariables = true;
    };

    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      # Auto-enroll Secure Boot keys via systemd-boot on next boot (requires
      # firmware to be in Setup Mode at that boot). includeMicrosoftKeys keeps
      # Microsoft's certs in db so the Windows bootloader still passes Secure
      # Boot validation in this dual-boot setup — without it, Windows won't boot.
      autoEnrollKeys = {
        enable = true;
        includeMicrosoftKeys = true; # default, but explicit: dual-boot needs it
        # autoReboot stays off so keys are only enrolled on a manual reboot,
        # after firmware has been put into Setup Mode.
      };
    };
    kernelParams = [
      # "quiet"
      # "loglevel=3"
      # "splash"
      # "plymouth.ignore-serial-consoles"
      # "nvidia-drm.modeset=1"
      # THESE 2 LINES ARE FIX FOR SHITTY NETWORK CARD, thanks intel
      "pcie_port_pm=off"
      "pcie_aspm.policy=performance"
      # Add delay to ensure second NVMe drive is ready
      "rootdelay=10"
      "nvme_core.default_ps_max_latency_us=0"
    ];
  };
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    optimise.automatic = true;

    settings = {
      # Binary caches from shared config
      substituters = common.nix.substituters;
      trusted-public-keys = common.nix.trustedPublicKeys;
    };
  };

  networking = {
    hostName = "nixos"; # Define your hostname.
    extraHosts = builtins.readFile ./config/hosts/hosts;

    # Enable networking
    networkmanager = {
      enable = true;
      # Let a system-level dnsmasq handle DNS on 127.0.0.1
      dns = "default";
    };
    # Use local stub; dnsmasq forwards exclusively to the upstream resolver.
    nameservers = [ "127.0.0.1" ];
  };

  # Set your time zone.
  time.timeZone = "Europe/Prague";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Trust mkcert CA
  security.pki.certificateFiles = [
    ./mkcert-ca.pem
  ];

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "cs_CZ.UTF-8";
    LC_IDENTIFICATION = "cs_CZ.UTF-8";
    LC_MEASUREMENT = "cs_CZ.UTF-8";
    LC_MONETARY = "cs_CZ.UTF-8";
    LC_NAME = "cs_CZ.UTF-8";
    LC_NUMERIC = "cs_CZ.UTF-8";
    LC_PAPER = "cs_CZ.UTF-8";
    LC_TELEPHONE = "cs_CZ.UTF-8";
    LC_TIME = "cs_CZ.UTF-8";
  };

  services = {
    # Local caching resolver forwarding all queries to the upstream resolver
    dnsmasq = {
      enable = true;
      settings = {
        no-resolv = true;
        strict-order = true;
        bind-interfaces = true;
        listen-address = [
          "127.0.0.1"
          "::1"
        ];
        # Do not include resolvconf-provided auxiliary configs
        conf-file = lib.mkForce [ ];
        resolv-file = lib.mkForce [ ];
        # Forward exclusively to the upstream resolver
        server = lib.mkForce [ upstreamDns ];
        cache-size = 400;
      };
    };
    tailscale = {
      enable = true;
      useRoutingFeatures = "client";
      extraSetFlags = [
        "--accept-dns=false"
      ];
    };
    xserver = {
      # Enable the X11 windowing system.
      enable = true;

      # Configure keymap in X11
      xkb = {
        layout = "us";
        variant = "";
      };

      # Load "nvidia" driver for Xorg and Wayland
      videoDrivers = [ "nvidia" ];
    };

    gnome.gnome-keyring.enable = true;
    displayManager = {
      # Enable the XFCE Desktop Environment.
      sddm.enable = true;
      sddm.wayland.enable = true;

      # Enable automatic login for the user.
      autoLogin.enable = true;
      autoLogin.user = name;
    };

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable sound with pipewire.
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
    };

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
    #   enable = true;
    #   enableSSHSupport = true;
    # };

    # List services that you want to enable:

    # Enable the OpenSSH daemon with hardened settings
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };

    hardware.openrgb = {
      enable = true;
      package = pkgs.openrgb-with-all-plugins;
      motherboard = "amd";
      server = {
        port = 6742;
      };
    };

    # Disable systemd-resolved to prevent excessive cache flushes that
    # trigger application-level network change events.
    resolved.enable = lib.mkForce false;
  };
  xdg = {
    autostart = {
      enable = true;
    };
    portal = {
      enable = true;
      #      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    };
    terminal-exec = {
      settings = {
        default = [ "ghostty.desktop" ];
      };
    };
  };

  # Passwordless sudo only for nixos-rebuild (what `sw` runs) and systemctl;
  # everything else prompts for a password (wheel default). Note nh cannot be
  # allowlisted instead: it wraps its elevated calls as `sudo env ... <cmd>`,
  # and allowlisting `env` would allow everything. This is still
  # root-equivalent for someone who can author and activate an arbitrary
  # closure, but it stops compromised user processes from running plain
  # `sudo <anything>`.
  security.sudo.extraRules = [
    {
      users = [ name ];
      commands = map (command: {
        inherit command;
        options = [ "NOPASSWD" ];
      }) [
        "/run/current-system/sw/bin/nixos-rebuild"
        "/run/current-system/sw/bin/systemctl"
      ];
    }
  ];
  security.rtkit.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.${name} = {
    isNormalUser = true;
    description = fullName;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "video"
      "render"
    ];
    packages = [ ];
  };

  # Maaaybe make this home manager somehow someday
  # maybe make some proper config, inspire from lazyvim

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  # Rename clobbered unmanaged files instead of failing activation (matches
  # darwin; ported from a hotfix found in the old /etc/nixos/home clone).
  home-manager.backupFileExtension = "hm-bak";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    v4l-utils
    ffmpeg-headless
    sbctl
    mangohud
    protonup-ng
    protontricks
    prusa-slicer
    goverlay
    docker-buildx
    docker-compose
    libva
    libva-utils
    nvidia-vaapi-driver
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05";
  # Disable USB autosuspend for Logitech C920 webcam (prevents white/blank frames)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="08e5", ATTR{power/autosuspend}="-1", ATTR{power/control}="on"
  '';

  hardware = {
    steam-hardware.enable = true;

    # Did you read the comment?

    # Enable graphics driver in NixOS unstable/NixOS 24.11
    graphics.enable = true;
    graphics.enable32Bit = true;
    graphics.extraPackages = with pkgs; [
      nvidia-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];

    nvidia = {
      # Modesetting is required.
      modesetting.enable = true;

      # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
      # Enable this if you have graphical corruption issues or application crashes after waking
      # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
      # of just the bare essentials.
      powerManagement.enable = false;

      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      powerManagement.finegrained = false;

      # Use the NVidia open source kernel module (not to be confused with the
      # independent third-party "nouveau" open source driver).
      # Support is limited to the Turing and later architectures. Full list of
      # supported GPUs is at:
      # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
      # Only available from driver 515.43.04+
      # Currently "beta quality", so false is currently the recommended setting.
      open = false;

      # Enable the Nvidia settings menu,
      # accessible via `nvidia-settings`.
      nvidiaSettings = true;

      # Optionally, you may need to select the appropriate driver version for your specific GPU.
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };
  };

  # Reduce IPv6 address churn (privacy temp addresses) to avoid frequent
  # netlink address change events that some applications interpret as
  # network changes.
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.use_tempaddr" = lib.mkForce 0;
    "net.ipv6.conf.default.use_tempaddr" = lib.mkForce 0;
    # Helps newer games/launchers that allocate many memory maps.
    "vm.max_map_count" = 2147483642;
  };

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = false;
      setSocketVariable = false;
    };
    daemon.settings = {
      # Ensure containers also use the same upstream resolver
      dns = lib.mkForce [ upstreamDns ];
      dns-opts = common.docker.dnsOpts;
      insecure-registries = common.docker.insecureRegistries;
      default-address-pools = common.docker.addressPools lib;
    };
  };
  programs = {
    steam = {
      enable = true;
      gamescopeSession.enable = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
    gamescope = {
      enable = true;
      capSysNice = true;
    };
    gamemode.enable = true;
  };

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
    LIBVA_DRIVER_NAME = "nvidia";
    VDPAU_DRIVER = "nvidia";
    NVD_BACKEND = "direct";
  };
}
