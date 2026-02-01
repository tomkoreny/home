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
  common = import ../../../lib/common {};

  # Shortcuts for frequently used values
  inherit (common.network) localDns;
  inherit (common.user) name fullName;
in {
  # Enable auto-upgrade from git
  tomkoreny.nixos.auto-upgrade.enable = true;

  # Enable Clawdbot node - connects to gateway at 192.168.1.93:18789
  tomkoreny.nixos.clawdbot-node = {
    enable = true;
    displayName = "NixOS Desktop";
    gatewayHost = "192.168.1.93";
    gatewayPort = 18789;
  };

  # Your configuration.
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Note: modules in modules/nixos/ are auto-loaded by Snowfall Lib
    # (caddy, openfortivpn, clawdbot-node)
  ];

  # Configure swap file
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 128 * 1024; # 128GB in MB
    }
  ];

  boot = {
    # this section is wierd and does not work, fix one day
    #  i18n.inputMethod = {
    #	  enable = true;
    #	  type = "ibus";
    #	  ibus.engines = with pkgs.ibus-engines; [ /* any engine you want, for example */ uniemoji ];
    #  };

    # end of section

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
    settings.experimental-features = ["nix-command" "flakes"];
    gc = {
      automatic = false;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

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
    # Use local stub; dnsmasq forwards exclusively to 192.168.1.93
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
    # Local caching resolver forwarding all queries to local DNS
    dnsmasq = {
      enable = true;
      settings = {
        no-resolv = true;
        strict-order = true;
        bind-interfaces = true;
        listen-address = [ "127.0.0.1" "::1" ];
        # Do not include resolvconf-provided auxiliary configs
        conf-file = lib.mkForce [];
        resolv-file = lib.mkForce [];
        # Forward exclusively to local resolver
        server = lib.mkForce [ localDns ];
        cache-size = 400;
      };
    };
    k3s = {
      enable = false;
      role = "server";
      extraFlags = toString [
        "--disable traefik"
        "--cluster-dns=10.43.0.10"
        "--resolv-conf=/etc/rancher/k3s/resolv.conf"
      ];
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
      videoDrivers = ["nvidia"];
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

    # Open ports in the firewall.
    # networking.firewall.allowedTCPPorts = [ ... ];
    # networking.firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    # networking.firewall.enable = false;

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
        default = ["ghostty.desktop"];
      };
    };
  };

  # NOTE: Passwordless sudo for ALL commands is convenient but carries security risk.
  # Any process running as 'tom' can escalate to root without authentication.
  # For a more secure setup, consider restricting to specific commands:
  #   command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
  #   command = "${pkgs.systemd}/bin/systemctl";
  security.sudo.extraRules = [
    {
      users = [ name ];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD" "SETENV"];
        }
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
    extraGroups = ["networkmanager" "wheel" "docker" "video" "render"];
    packages = [];
  };

  # Maaaybe make this home manager somehow someday
  # maybe make some proper config, inspire from lazyvim

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    sbctl
    mangohud
    protonup
    docker-buildx
    docker-compose
    mkcert
    caddy
    libva
    libva-utils
    nvidia-vaapi-driver
  ];

  # Create a proper resolv.conf for k3s
  environment.etc."rancher/k3s/resolv.conf".text = ''
    nameserver ${localDns}
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05";
  hardware = {
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
  };

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = false;
      setSocketVariable = false;
    };
    daemon.settings = {
      # Ensure containers also use local DNS server
      dns = lib.mkForce [ localDns ];
      dns-opts = common.docker.dnsOpts;
      insecure-registries = common.docker.insecureRegistries;
      default-address-pools = common.docker.addressPools lib;
    };
  };
  programs = {
    steam.enable = true;
    steam.gamescopeSession.enable = true;
    gamemode.enable = true;
  };

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
    LIBVA_DRIVER_NAME = "nvidia";
    VDPAU_DRIVER = "nvidia";
    NVD_BACKEND = "direct";
  };
}
