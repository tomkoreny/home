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
}:
{
    # Your configuration.
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  swapDevices = [{
    device = "/swapfile";
    size = 16 * 1024; # 16GB
  }];

# this section is wierd and does not work, fix one day
#  i18n.inputMethod = {
#	  enable = true;
#	  type = "ibus";
#	  ibus.engines = with pkgs.ibus-engines; [ /* any engine you want, for example */ uniemoji ];
#  };

# end of section

  # Bootloader.
  boot.plymouth.enable = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = 5;
  #boot.loader.systemd-boot.netbootxyz.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;


            boot.lanzaboote = {
              enable = true;
              pkiBundle = "/etc/secureboot";
            };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = { automatic = false; dates = "weekly"; options = "--delete-older-than 7d"; };


  networking.hostName = "nixos"; # Define your hostname.
  networking.extraHosts = (builtins.readFile ./config/hosts/hosts);

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Prague";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

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

  services.tailscale.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the XFCE Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  xdg = {
	  portal = {
		  enable = true;
	  };
  };

  security.sudo.extraRules= [
  {  users = [ "tom" ];
	  commands = [
	  { command = "ALL" ;
		  options= [ "NOPASSWD" ]; # "SETENV" # Adding the following could be a good idea
	  }
	  ];
  }
  ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.tom = {
    isNormalUser = true;
    description = "Tom Koreny";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
    ];
  };

  # Maaaybe make this home manager somehow someday
  # maybe make some proper config, inspire from lazyvim
  programs.nixvim = {
		enable = true;
		globals.mapleader = " ";
		opts = {
			tabstop = 2;
			shiftwidth = 2;
			expandtab = true;
			mouse = "a";
		};

	  plugins.lualine.enable = true;
	  plugins.typescript-tools.enable = true;

	  plugins.auto-save.enable = true;
	  plugins.auto-session.enable = true;
	  plugins.coq-nvim.enable = true;
	  plugins.coq-nvim.settings.auto_start = true;
	  plugins.treesitter = {
		  enable = true;
		  settings.highlight.enable = true;
		  settings.indent.enable = true;
	  };
	  plugins.telescope.enable = true;
	  plugins.nvim-tree.enable = true;
	  plugins.mini.enable = true;
	  plugins.mini.modules.icons = {
      style = "glyph";
    };
	  plugins.mini.mockDevIcons = true;


	  plugins.lsp.enable = true;
	  plugins.lsp.inlayHints = true;

	  colorschemes.catppuccin.enable = true;


		keymaps = [
      {
        action = "<cmd>Telescope find_files<CR>";
        key = "<leader>ff";
      }
      {
        action = "<cmd>Telescope git_files<CR>";
        key = "<leader>fg";
      }
      {
        action = "<cmd>Telescope buffers<CR>";
        key = "<leader>fb";
      }
		];

  };


  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;

# Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "tom";

# Allow unfree packages
  nixpkgs.config.allowUnfree = true;

# List packages installed in system profile. To search, run:
# $ nix search wget
  environment.systemPackages = with pkgs; [
    sbctl
    mangohud
    protonup
  ];

# Some programs need SUID wrappers, can be configured further or are
# started in user sessions.
# programs.mtr.enable = true;
# programs.gnupg.agent = {
#   enable = true;
#   enableSSHSupport = true;
# };

# List services that you want to enable:

# Enable the OpenSSH daemon.
  services.openssh.enable = true;

# Open ports in the firewall.
# networking.firewall.allowedTCPPorts = [ ... ];
# networking.firewall.allowedUDPPorts = [ ... ];
# Or disable the firewall altogether.
# networking.firewall.enable = false;

  services.hardware.openrgb = {
	  enable = true;
	  package = pkgs.openrgb-with-all-plugins;
	  motherboard = "amd";
	  server = {
		  port = 6742;
	  };
  };

# This value determines the NixOS release from which the default
# settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

  # Enable graphics driver in NixOS unstable/NixOS 24.11
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Load "nvidia" driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];


  hardware.nvidia = {

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
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };


  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.gamemode.enable = true;

 environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS =
      "\${HOME}/.steam/root/compatibilitytools.d";
  };

}
