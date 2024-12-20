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

    # All other arguments come from the module system.
    config,
    ...
}:
{
config = lib.mkIf (system == "x86_64-linux") {
	  wayland.windowManager.hyprland = {
		  enable = true; # enable Hyprland
		  systemd.enableXdgAutostart = true; # enable HyprlandAutostart
		  extraConfig = (builtins.readFile ./config/hyprland/main.conf);
		  package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
	  };

	  services.hyprpaper.enable = true;
	  services.hypridle.enable = true;
	  services.hypridle.settings = {
		  general = {
			  after_sleep_cmd = "hyprctl dispatch dpms on";
			  ignore_dbus_inhibit = false;
	#		  lock_cmd = "hyprlock";
			  lock_cmd = "hyprctl dispatch dpms off";
		  };

		  listener = [
		  {
			  timeout = 60;
			  on-timeout = "hyprctl dispatch dpms off";
			  on-resume = "hyprctl dispatch dpms on";
		  }
		 # {
		#	  timeout = 900;
		#	  on-timeout = "hyprlock";
		  #}
		  ];
	  };
};
}
